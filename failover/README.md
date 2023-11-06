
# RutOS failover 
Connection check lua script provides a ubus service for checking wheter internet connectivity is available on main interface. failover.sh script takes two arguments of main and a backup interface and periodically checks wheter internet is available on the main interface if not it switches to backup interface 

