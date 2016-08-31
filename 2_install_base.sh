#!/bin/bash


CONF="./zeta_cluster.conf"

. $CONF

CURUSER=$(whoami)

if [ "$CURUSER" != "$IUSER" ]; then
    echo "Must use $IUSER: User: $CURUSER"
fi



CREDS="/home/$IUSER/creds/creds.txt"
HOST=$(echo $CLDBS|cut -d"," -f1|cut -d":" -f1)
WEBHOST="$HOST:8443"
TFILE="/tmp/netrc.tmp"

touch $TFILE
chown $IUSER:$IUSER $TFILE
chmod 600 $TFILE
cat > $TFILE << EOF
machine $HOST login $(cat $CREDS|grep mapr|cut -d":" -f1) password $(cat $CREDS|grep mapr|cut -d":" -f2)
EOF



BASE_REST="https://$WEBHOST/rest"

CURL_GET_BASE="/opt/mesosphere/bin/curl -k --netrc-file $TFILE $BASE_REST"

#VOL_LIST="/volume/list"
#echo "$CURL_GET_BASE$VOL_LIST"

echo "Checking for default hbase volume and removing"
if [ -d "/mapr/$CLUSTERNAME/hbase" ]; then
    CMD="$CURL_GET_BASE/volume/remove?name=mapr.hbase"
    echo "Removing mapr.hbase volume"
    $CMD
    echo ""
    sudo rm -rf /mapr/$CLUSTERNAME/hbase
fi
echo "Checking for default apps volume and removing"
if [ -d "/mapr/$CLUSTERNAME/apps" ]; then
    CMD="$CURL_GET_BASE/volume/remove?name=mapr.apps"
    echo "Removing mapr.apps volume"
    $CMD
    echo ""
    sudo rm -rf /mapr/$CLUSTERNAME/apps
fi

echo "Checking for marp and zetaadm user home directories in MapR FS"
USERS="mapr zetaadm"
for U in $USERS; do
    echo "Checking for $U user home directory at /user/$U"
    if [ ! -d "/mapr/$CLUSTERNAME/user/$U" ]; then
        echo "$U Home Directory not found: Creating"
        CMD="$CURL_GET_BASE/volume/create?name=user.$U&path=/user/$U&rootdirperms=775&user=$U:fc,a,dump,restore,m,d%20zetaadm:fc,a,dump,restore,m,d%20mapr:fc,a,dump,restore,m,d&ae=$U"
        $CMD
        echo ""
        T=""
        while [ "$T" == "" ]; do
            sleep 1
            T=$(ls -1 /mapr/$CLUSTERNAME/user|grep $U)
        done
        sudo chown $U:$U /mapr/$CLUSTERNAME/user/$U
    fi
done

OLDIFS=$IFS
IFS=","
echo "Checking for, and creating if needed the root dirs for your cluster"
for DIR in $ROOT_DIRS; do
    echo "Checking /mapr/$CLUSTERNAME/$DIR"
    if [ -d "/mapr/$CLUSTERNAME/$DIR" ]; then
        echo "Directory /mapr/$CLUSTERNAME/$DIR already exists, skipping creation but resetting permissions"
    else
        sudo mkdir -p /mapr/$CLUSTERNAME/$DIR
    fi
    sudo chown -R zetaadm:2501 /mapr/$CLUSTERNAME/$DIR
    sudo chmod -R 750 /mapr/$CLUSTERNAME/$DIR
done
IFS=$OLDIFS

#####################################################
# Create base Zeta Key Store locations
# the kstore directory under zeta is used to house zeta specific configuration data, as well as zeta specific clusterwide information
# Descriptions of the locations are below
echo "Setting up zeta kstore information"
DIR="/mapr/$CLUSTERNAME/zeta/kstore"
sudo mkdir -p $DIR
sudo chown zetaadm:2501 $DIR
sudo chmod 755 $DIR

# Group Sync
DIR="/mapr/$CLUSTERNAME/zeta/kstore/zetasync"
sudo mkdir -p $DIR
sudo chown zetaadm:zetaadm $DIR
sudo chmod 775 $DIR

if [ ! -f "$DIR/zetagroups.list" ]; then
    cat > ${DIR}/zetagroups.list << GRPEOF
GRPEOF
else
   echo "Not clobbering existing zetagroups.list"
fi
if [ ! -f "$DIR/zetausers.list" ]; then
    cat > ${DIR}/zetausers.list << USROF
USROF
else
    echo "Not clobbering existing zetausers.list"
fi

if [ ! -f "$DIR/zetauid.list" ]; then
    touch ${DIR}/zetauid.list
else
    echo "Not clobbering existing zetauid.list"
fi

# ENV Main
DIR="/mapr/$CLUSTERNAME/zeta/kstore/env"
sudo mkdir -p $DIR
sudo chown zetaadm:zetaadm $DIR
sudo chmod 775 $DIR

if [ ! -f "$DIR/master_env.sh" ]; then
    echo "Building Zeta Master ENV File"
    cat > $DIR/master_env.sh << EOL3
#!/bin/bash

# START GLOBAL ENV Variables for Zeta Environment

export ZETA_CLUSTERNAME="${CLUSTERNAME}"
export ZETA_NFS_ROOT="/mapr/\$ZETA_CLUSTERNAME"

export ZETA_MESOS_DOMAIN="mesos"
export ZETA_MESOS_LEADER="leader.\${ZETA_MESOS_DOMAIN}"
export ZETA_MESOS_LEADER_PORT="5050"

# END GLOBAL ENV VARIABLES
EOL3
else
    echo "Not clobbering existing master_env.sh"
fi


#########
# By creating a world reable directory in MapRFS for tickets, and then setting permission on each ticket to be only user readble, we have a one stop shop to store tickets
# The only caveat is the mapr and zetaadm tickets need TLC, if especially the mapr ticket expires on a secure cluster, the result is NFS mount that don't work breaking all the things
DIR="/mapr/$CLUSTERNAME/zeta/kstore/maprtickets"
sudo mkdir -p $DIR
sudo chown mapr:zetaadm $DIR
sudo chmod 775 $DIR

##########
# Installing global role directories
# This is only available to zetaadm and is used for shared services like a cluster wide docker registry, and cluster wide ldap server
#
echo "Checking for shared dir in each root directory."


RDS=$(echo "$ROOT_DIRS"|tr "," " ")

for DIR in $RDS; do
    echo "Looking for /mapr/$CLUSTERNAME/$DIR/shared"
    if [ -d "/mapr/$CLUSTERNAME/$DIR/shared" ]; then
        echo "/mapr/$CLUSTERNAME/$DIR/shared already exists, skipping"
    else
        CMD="$CURL_GET_BASE/volume/create?name=$DIR.shared&path=/$DIR/shared&rootdirperms=770&user=zetaadm:fc,a,dump,restore,m,d%20mapr:fc,a,dump,restore,m,d&ae=zetaadm"
        $CMD
        echo ""
        T=""
        while [ "$T" == "" ]; do
            sleep 1
            T=$(ls -1 /mapr/$CLUSTERNAME/$DIR|grep shared)
        done
        sudo chown zetaadm:zetaadm /mapr/$CLUSTERNAME/$DIR/shared
    fi
done

DIR="/mapr/$CLUSTERNAME/zeta/kstore/env/env_shared"
sudo mkdir -p $DIR
sudo chown zetaadm:zetaadm $DIR
sudo chmod 775 $DIR
ENV_FILE="/mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh"

tee $ENV_FILE << EOL3
# Source Master Zeta ENV File
. /mapr/\$(ls -1 /mapr)/zeta/kstore/env/master_env.sh
# START GLOBAL ENV Variables for Zeta Environment

export ZETA_MARATHON_ENV="marathon"
export ZETA_MARATHON_HOST="\${ZETA_MARATHON_ENV}.\${ZETA_MESOS_DOMAIN}"
export ZETA_MARATHON_PORT="8080"
export ZETA_MARATHON_URL="\$ZETA_MARATHON_HOST:\$ZETA_MARATHON_PORT"
export ZETA_MARATHON_SUBMIT="http://\$ZETA_MARATHON_URL/v2/apps"
export ZETA_ZKS="$ZKS"

# Source env_prod
for SRC in /mapr/\$ZETA_CLUSTERNAME/zeta/kstore/env/env_shared/*.sh; do
   . \$SRC
done

if [ "\$1" == "1" ]; then
    env|grep -P "^ZETA_"
fi

EOL3

chmod +x $ENV_FILE



#Create a dummy script in the env_prod directory so that file not found errors don't appear when sourcing main file
cat > /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/env_shared.sh << EOL5
#!/bin/bash
# Basic script to keep file not found errors from happening 
EOL5


echo "Base Layout installed:"
ls -ls /mapr/$CLUSTERNAME

rm $TFILE



