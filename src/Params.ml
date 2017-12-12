(** Module with static parameters *)
open! Core

(** switch field *)
let sw = "sw"

(** port field *)
let pt = "pt"

(** counter field *)
let counter = "failures"

(** ttl field *)
let ttl = "ttl"
let max_ttl = 32

(** Destination host. Files generated by Praveen assume this is 1. *)
let destination = 1

(** up bit associated with link *)
let up sw pt = sprintf "up_%d" pt

(** various files *)
let topo_file base_name = base_name ^ ".dot"
let spf_file base_name = base_name ^ "-spf.trees"
let ecmp_file base_name = base_name ^ "-allsp.nexthops"
let car_file base_name = base_name ^ "-disjointtrees.trees"
