if frameType = arp then
  (if inPort = 2 then fwd(1)
   else if inPort = 1 then fwd(2))
else  
   let translatePrivate, translatePublic = 
     nat (publicIP = 10.0.0.254) in
   let pol = 
       if switch = 1 && inPort = 1 then 
         (translatePrivate; if inPort = 1 then 2 else pass)
     | if switch = 1 && inPort = 2 then
         (translate_public; if inPort = 2 then 1 else pass) in 
   MonitorTable(1, pol) 
   

