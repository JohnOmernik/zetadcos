#!/bin/bash
CONF="./zeta_cluster.conf"
# Pull in Cluster conf
. $CONF

# Source Shared Env

. /mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh

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


SOURCE_IMG="osixia/phpldapadmin"

sudo docker pull $SOURCE_IMG
APP_IMG="${ZETA_DOCKER_REG_URL}/ldapadmin"

sudo docker tag $SOURCE_IMG $APP_IMG

sudo docker push $APP_IMG


APP_ROOT="/mapr/$CLUSTERNAME/zeta/shared/ldapadmin"

if [ -d "$APP_ROOT" ]; then
    echo "LDAP Admin Root at $APP_ROOT already exists. Refusing to go on..."
    exit 1
fi


mkdir -p ${APP_ROOT}
mkdir -p ${APP_ROOT}/conf

sudo chown -R zetaadm:zetaadm ${APP_ROOT}
sudo chmod -R 750 ${APP_ROOT}

echo "What port do you want to run ldap admin on? (Default 6443)"
read -e -p "LDAP Admin Port: " -i "6443" APP_PORT

cat > /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/ldapadmin.sh << EOL
export ZETA_LDAPADMIN_HOST="ldapadmin-shared.marathon.agentip.dcos.thisdcos.directory"
export ZETA_LDAPADMIN_PORT="$APP_PORT"
EOL

sudo chmod +x /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/ldapadmin.sh

MARFILE="${APP_ROOT}/ldapadmin.shared.marathon"


cat > $MARFILE << EOF
{
  "id": "shared/ldapadmin",
  "cpus": 1,
  "mem": 1024,
  "instances": 1,
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "env": {
  "PHPLDAPADMIN_LDAP_HOSTS":"#PYTHON2BASH:[{'openldap-shared.marathon.agentip.dcos.thisdcos.directory': [{'server': [{'tls': False}]}, {'login': [{'bind_id': 'cn=admin,dc=marathon,dc=mesos'}]}]}]"
  },
  "ports": [],
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "$APP_IMG",
      "network": "BRIDGE",
      "portMappings": [
        { "containerPort": 443, "hostPort": ${APP_PORT}, "servicePort": 0, "protocol": "tcp"}
      ]
    }
  }
}

EOF


echo "Submitting to Marathon"
curl -X POST $MARATHON_SUBMIT -d @${MARFILE} -H "Content-type: application/json"
echo ""
echo ""
echo ""
echo ""

echo ""

rm $TFILE

