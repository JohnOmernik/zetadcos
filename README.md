# zetadcos
Basic opinionated layout for Zeta on DCOS running with a shared mapr filesystem


--------

This layout is used to create a basic shared zeta layout. It assume Mapr is running, healthy and self mounted on nodes. 

It also installs a shared docker registry backed by maprfs and offers an option to setup a ldap server running in docker on the cluster. 

It creates four basic directories, and allows you to specify more.  The idea is for each role that, you want to create a role based directory. 


