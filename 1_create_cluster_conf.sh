#!/bin/bash

CONF="./zeta_cluster.conf"

if [ -f "$CONF" ]; then
    echo "There already appears to be a conf at $CONF. Please rename or delete and try again"
    exit 0
fi

echo "Let's Create a zeta_cluster.conf for Zeta Running over DCOS/MAPR!"

echo "---------------------------------------"
echo "It's highly recommened your intial user for this is zetaadm. This user should be setup on all nodes, and have passwordless sudo access (preferablly on UID 2500 the default)"
echo "You can change the initial user in the generated config, however the user must have the proper privileges"
echo ""
ZIUSER="zetaadm"
echo ""
echo "Please pass the path to the private key for the initial user ($ZIUSER). (This may be located at /home/$ZIUSER/.ssh/id_rsa, or whereever you may have put it)"
read -p "Path to keyfile: " -e -i "/home/$ZIUSER/.ssh/id_rsa" IKEY


if [ ! -f "$IKEY" ]; then
    echo "There doesn't appear to be a key file at $IKEY"
    exit
fi


CURUSER=$(whoami)
if [ "$CURUSER" != "$ZIUSER" ]; then
    echo "I am sorry, this script must be run as the initial user"
    echo "Zeta Initial User: $ZIUSER"
    echo "Current User: $CURUSER"
    exit 0
fi


TMP_SRC="/home/$ZIUSER/maprdcos/cluster.conf"

echo ""
echo "---------------------------------------"
echo "We want to install a basic layout for zeta that can be easily recreated, support growth, and run on DC/OS with MapR running"
echo "At this point, we assume you already have the DC/OS and MapR part up and running"
echo "At this point, we can source the cluster.conf from that to get information about the cluster"
echo ""
echo "Where is the mapr cluster.conf located?"
read -p "Path to MapR cluster.conf: " -e -i "$TMP_SRC" MAPR_CONF

if [ ! -f "$MAPR_CONF" ]; then
    echo "Path not found, please try again"
    exit 1
fi

. $MAPR_CONF

if [ "$IUSER" != "$ZIUSER" ]; then 
    echo "The MapR IUSER and Zeta Install IUser should match"
    echo "Mapr: $IUSER"
    echo "Zeta: $ZIUSER"
    exit 1
fi 


NFSTEST=$(ls /mapr/$CLUSTERNAME)
if [ "$NFSTEST" == "" ]; then
    echo "It doesn't appear that the cluster $CLUSTERNAME is mounted /mapr. We need that"
    exit 1
fi

INSTALLED_TEST=$(ls -1 /mapr/$CLUSTERNAME|grep zeta)
if [ "$INSTALLED_TEST" != "" ]; then
    echo "It appears zeta is already installed, you likely don't want to overwrite"
    exit 1
fi
ls /mapr/$CLUSTERNAME


echo ""
echo "---------------------------------------"
echo "In the zeta install, there are four base directories, plus the user home, as listed below."
echo ""
echo "apps,etl,data,zeta"
echo ""
echo "For each of these directories, every time a role is installed, a mapr volume is created for that role under the directory."
echo "In addition, a user for data service, and groups are created to help manage the data in the directories"
echo "For each directory (apps, mesos, data, etl):"
echo "---- a group zeta%role%%dir% is created that has write permissions by default to /directory/%role% (i.e. for role prod, /apps/prod)"
echo ""
echo "Then there is also a user created that can be used as a data service writing user (zetasvc%role%data)"
echo ""
echo ""
echo "The purpose of the initial directories is:"
echo "***********************************************"
echo ""
echo "data: A place to store data that is sharable. This is not application specific (like a database for a web front end) this is any data that may be queried accross multiple tools"
echo ""
echo "etl: A place to store jobs that load, process, enrich, and move data in the system. This includes definitions for services in marathon or job definitions in chronos"
echo ""
echo "apps: This is where specific applications that are not considered shared services may be stored. Models, front ends, anything that isn't something to be shared like a Spark service or Drill Service"
echo ""
echo "zeta: This is where shared services may be run and sourced. Services like Kafka, Drill, Confluent. Etc"
echo "---- Under zeta there is also a special directory called kstore for keeping secrets, env scripts, users management etc."
echo ""
echo "You may add more root directories now (or just hit enter for blank)"
echo "If you want to add more just add a comma sep list. Ex: toys,cars,trucks"
echo ""
read -p "Enter more directories if you wish: " ADD_DIRS
if [ "$ADD_DIRS" == "" ]; then
    ROOT_DIRS="apps,data,etl,zeta"
else
    ROOT_DIRS="apps,data,etl,zeta,$ADD_DIRS"
fi

echo "The root directories will be $ROOT_DIRS"
echo ""

echo ""
echo "---------------------------------------"


cat > $CONF << EOF
#!/bin/bash

#########################
# Path to MapR cluster.conf
export MAPR_CONF="$MAPR_CONF"

# Source the MapR Conf
. \$MAPR_CONF

#########################
export ROOT_DIRS="$ROOT_DIRS"


EOF
