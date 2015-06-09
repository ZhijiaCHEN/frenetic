import frenetic, sys, json, time
import os.path
from functools import partial
from frenetic.syntax import *
import single_switch_forwarding
import array
from ryu.lib.packet import packet
from tornado.ioloop import PeriodicCallback
from tornado.ioloop import IOLoop
from tornado.concurrent import return_future
from tornado.gen import sleep

client_port = 1
client_ip = "10.0.0.1"
public_server_ip = "10.0.0.2"
public_server_mac = "00:00:00:00:00:02"

def get(pkt,protocol):
    for p in pkt:
        if p.protocol_name == protocol:
            return p

def address_translation(server_port):
  assert server_port != client_port, "port is for the client"
  to_this_server = Filter(Test(Location(Physical(server_port))))
  to_client = Filter(Test(Location(Physical(1))))
  masquarade_to_this_server = Mod(IP4Dst("10.0.0.%s" % server_port)) \
    >> Mod(EthDst("00:00:00:00:00:0%s" % server_port))
  masquarade_from_public_server = Mod(IP4Src("10.0.0.1")) >> \
    Mod(EthSrc("00:00:00:00:00:01"))
  return ((to_this_server >> masquarade_to_this_server) |
          (to_client >> masquarade_from_public_server))

# Returns 0 as a default
def packet_src_port(payload):
  pkt = packet.Packet(array.array('b', payload.data))
  ip = get(pkt, "ipv4")

  if ip.proto == 6:
    return get(pkt, "tcp").src_port
  else:
    return 0

def route(src_tcp_port, dst_sw_port):
  client_to_server = \
    Filter(Test(Location(Physical(1))) & Test(TCPSrcPort(src_tcp_port))) >> \
    Mod(Location(Physical(dst_sw_port)))
  server_to_client = \
    Filter(Test(Location(Physical(dst_sw_port))) & Test(TCPDstPort(src_tcp_port))) >> \
    Mod(Location(Physical(1)))
  return Filter(Test(IPProto(6))) >> (client_to_server | server_to_client)

def to_controller(known_src_ports):
  return Filter(Test(Location(Physical(1))) & ~Or(Test(TCPSrcPort(pt)) for pt in known_src_ports)) >> \
    Mod(Location(Pipe("http")))

class State(object):

  def __init__(self, filename, connections, max_servers):
    assert max_servers >= 1
    self.filename = filename
    self.connections = {}
    # Deals with JSON
    for key in connections:
      self.connections[int(key)] = connections[key]
    self.max_servers = max_servers
    self.__next_server = 0

  def next_server_port(self):
    n = self.__next_server
    self.__next_server = (n + 1) % self.max_servers
    return 2 + n

  def new_connection(self, src_port):
    if not(src_port in self.connections):
      self.connections[src_port] = self.next_server_port()

    if self.filename != "/dev/null":
      f = open(self.filename, "w")
      json.dump(self.connections, f)
      f.flush()
      f.close()

    return self.connections[src_port]

class LoadBalancer(frenetic.App):

  client_id = "load_balancer"

  def __init__(self, state):
    frenetic.App.__init__(self)
    self.state = state

  def policy(self):
    conns = self.state.connections
    pol = (Union(route(src_port, conns[src_port])  for src_port in conns) |
            to_controller(conns.keys()))
    return Filter(Test(EthType(0x800))) >> pol

  def connected(self):
      self.update(self.policy())

  def packet_in(self, switch_id, port_id, payload):
    src = packet_src_port(payload)
    server_port = self.state.new_connection(src)
    print "Sending traffic from TCP port %s to switch port %s" % (src, server_port)
    self.update(self.policy())

    # Assumes no address-translation
    self.pkt_out(switch_id = switch_id, payload = payload, actions = [Output(Physical(server_port))])


def main(max_servers, state_filename):
    if state_filename != "/dev/null" and os.path.isfile(state_filename):
      f = open(state_filename, "r")
      conns = json.load(f)
      f.close()
    else:
      conns = {}
    app = LoadBalancer(State(state_filename, conns, max_servers))
    app.start_event_loop()

if __name__ == '__main__':
  main(int(sys.argv[1]), sys.argv[2])
