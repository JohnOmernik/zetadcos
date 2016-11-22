# zetadcos
Basic opinionated layout for Zeta on DCOS running with a shared mapr filesystem

--------
This layout is used to create a basic shared zeta layout. It assume Mapr is running, healthy and self mounted on nodes. 

It also installs a shared docker registry backed by maprfs and offers an option to setup a ldap server running in docker on the cluster. 

It creates four basic directories, and allows you to specify more.

## Requirements
--------

This opinionated install of Zeta Architecture assumes somethings about your cluster. 
* DCOS is running and is happy/healthy on the cluster.  This is tested with 1.7 at this time. 
* MapR on DCOS https://github.com/JohnOmernik/maprdcos is running and in a "happy" state.  
  * Happy state means running and happy. 
  * At this time we expect you to manually mount the cluster filesystem at /mapr on each node.
    * Currently we use the shared NFS with the free MapR version (community). We recommend using a licensed version so each node can self mount the cluster. Another option is to use the FUSE client, however see the maprdcos repo for bugs. 
* It does assume curl is installed on all nodes.  

## Installation
--------
The initial install is done via the numbered scripts (1_, 2_, etc) They should be run in order. 

After the ininital install, helper scripts are included for future operations (installing new nodes, or roles to the cluster). Other helperscripts needs to be created, such as user/group creation automation). 


* host_ldap_config.sh - This script is to configure the physical host to use the LDAP directory
* add_role_schema.sh - This creates OUs/Groups in the directory for roles
* install_zeta_role.sh - This creates directories etc for new roles in Zeta


## Opinions and Reasoning
--------
As stated above, this is a reference architecture that is opinionate in its layout. The idea is to create a shareable environment that can rely on a clustered filesystem, and have a reasonable foundate for multi-tenant, isolated workload environments. 

This is a work in progress, and other opinions will be considered (please enter an issue).  We are looking for simple and eleagant, and something that just works. 
--------
### Base Directories
At the root of the shared filesystem, there are included in this 5 base directories that pertain to Zeta. Except for the user directory, each directory contains a "roled" named directory that is actually a volume in MapR FS. 

This reference architecture will allow us to, for each of base directories, create a volume dedicated to a role. This provides isolation, performance control, and audit/accounting settings for each role. 

This repo allows you install more directories. However, groups are only created for access to the 4 roles based directories as part of the repo. 

The administrators can always create more volumes under the role based volumes for each directory for performance and other data management reasons, but the volumes as created provide the basis for Zeta. 


The 5 directories (4 role based) that are created:

#### apps

The apps directory is intended for applications that are running in your cluster. This is separate from frameworks, data location, or etl jobs. Apps that do not produce shareable data (say a MongoDB application and the data files Mongo uses) would store the data in the apps folder structure. If an application produces data that is intended to be read and parsed by other applications (say CSV, or Parquet files) they should be stored in the data directory. 

#### data

The data directory is for shareable data. Sharable means in a portable format that multiple applications or frameworks can utilize. (Parquet, csv, etc) This is not intended for application specific data stores (say the data files from a Mysql data base, only the instance of Mysql that is using that data should be accessing those files)

#### etl

The etl directory is for scheduled jobs and services that focus on moving data in the cluster. While this line may be blurred with apps, the intent here is to have one place for all data oriented jobs in order to keep things organized. a

#### zeta

The zeta directory is intended for frameworks/services on the cluster. Consider them apps, but cluster facing/using services. Spark, Drill, Myriad, Docker Registries etc.  While these are technically apps, we wanted an area that focused on cluster services as separate from user applications. 

#### user

The user directory is for user home directories. This directy is not role based, and instead focused on users on the cluster. 
--------

##### Example layout 
Say you had a small cluster with 3 roles, shared (installed by default), prod, and dev. On this cluster you have 5 users, will, karen, alicia, jim, and ted.  The layout would look like this:

* apps
  * shared
  * prod
  * dev
* data
  * shared
  * prod
  * dev
* etl
  * shared
  * prod
  * dev
* zeta
  * shared
  * prod
  * dev
* user
  * will
  * karen
  * alicia
  * jim
  * ted 


### Roles
--------
Only one role, "shared" is installed by this repo. More work needs to be done to automated the creation of the roles to line up with the Mesos side of things. The goal of roles is to provide a bases for multi-tenancy in the cluster. 

The shared role, installed by default provides a basis to run shared cluster services that help support the foundation of zeta. Please see below for what is installed, and what is desired in the future. 

When a role is installed, certain things need to happen, here are some lists of both what is happening, and what is desired:

#### Currently working

* When a role is created, an OU is setup in the directory (included in the base install, work needs to be done if you wish to automate this with your own internal corp directory). Note the role creation scripts needs some automation, right now add the schema first, then create the role. 
  * Under that OU, two more OUs are created, users and groups.
  * A user zetasvc%role% is created. For shared, the user name is zetasvcshared.  This user can be used as base user for data jobs or other service operating in the role
  * 4 groups are created one for each of the role directories. So for shared, the 4 groups are: zetasharedapps, zetashareddata, zetasharedetl, zetasharedzeta.  
* The volumes for each of the 4 role based directories are created in MapR with permissions set to be the groups created above. 

#### Desired

* Base services for roles. Should provide role install time base services options
  * Docker Registry
  * Marathon
  * Chronos
  * Others? 
* Better one click automation (currently you have to run the schema script first, then the directory script, it needs to be a bit smoother)
* Setting up the roles/weights in Mesos for isolation purposes. 


### Shared Services
--------
The shared role, as stated above, is designed to provide cluster wide services.  Each service here will be vetted and designed to run in the shared role, (althought another "version" to duplicate service maybe available for other roles)

#### Current Services
* SSL Certificate authority. (Actually installed in maprdcos, but moved to permanent location in this Repo)
* Docker Registry - A docker registry for cluster wide images to be stored in. This runs on port 5005 and can be found via dockerregv2-shared.marathon.slave.mesos
* Open LDAP server as a shared directory for the cluster. This runs in host mode on ports 389/636 (standard LDAP ports) and can be found via openldap-shared.marathon.slave.mesos
* Ldap Administration application for administrating the cluster directory. This runs (if defaults are used) at ldapadmin-shared.marathon.slave.mesos:6443





