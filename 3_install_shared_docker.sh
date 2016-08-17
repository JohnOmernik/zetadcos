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


DOCKER_IMAGE_LOC="/mapr/$CLUSTERNAME/zeta/shared/dockerregv2/images"


echo "Looking for $DOCKER_IMAGE_LOC"
if [ -d "$DOCKER_IMAGE_LOC" ]; then
    echo "$DOCKER_IMAGE_LOC already exists. Please remove volume and/or delete directory prior to installing Shared Docker Registry"
    exit 1
else
    mkdir -p /mapr/$CLUSTERNAME/zeta/shared/dockerregv2

    CMD="$CURL_GET_BASE/volume/create?name=zeta.shared.dockerregv2&path=/zeta/shared/dockerregv2/images&rootdirperms=775&user=zetaadm:fc,a,dump,restore,m,d%20mapr:fc,a,dump,restore,m,d&ae=zetaadm"
    $CMD
    echo ""
    T=""
    while [ "$T" == "" ]; do
        sleep 1
        T=$(ls -1 /mapr/$CLUSTERNAME/zeta/shared/dockerregv2|grep images)
    done
    sudo chown zetaadm:zetaadm $DOCKER_IMAGE_LOC
fi

sudo docker pull registry:2
sudo docker tag registry:2 zeta/registry:2

echo "We use the MapR Bootstrap Docker Registry to host the Shared Docker Registry"

sudo docker tag registry:2 ${DOCKER_REG_URL}/dockerregv2
sudo docker push ${DOCKER_REG_URL}/dockerregv2

echo "What Service port should this new shared Docker Registry use? The MapR Docker Container is using port 5000, we recommend something different: How about 5005?"
read -e -p "What service port should we used for the shared docker registry instance? " -i "5005" NEW_DOCKER_REG_PORT

NEW_DOCKER_REG_HOST="dockerregv2.shared.marathon.mesos"
ZETA_DOCKER_REG_URL="${NEW_DOCKER_REG_HOST}:${NEW_DOCKER_REG_PORT}"

cat > /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/dockerregv2.sh << EOL

export ZETA_DOCKER_REG_HOST="dockerregv2.shared.marathon.mesos"
export ZETA_DOCKER_REG_PORT="$NEW_DOCKER_REG_PORT"
export ZETA_DOCKER_REG_URL="\${ZETA_DOCKER_REG_HOST}:\${ZETA_DOCKER_REG_PORT}"

EOL


sudo chmod +x /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/dockerregv2.sh

MARFILE="/mapr/$CLUSTERNAME/zeta/shared/dockerregv2/dockerregv2.shared.marathon"

cat > $MARFILE << EOF
{
  "id": "shared/dockerregv2",
  "cpus": 1,
  "mem": 1024,
  "instances": 1,
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "ports": [],
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${DOCKER_REG_URL}/dockerregv2",
      "network": "BRIDGE",
      "portMappings": [
        { "containerPort": 5000, "hostPort": ${NEW_DOCKER_REG_PORT}, "servicePort": 0, "protocol": "tcp"}
      ]
    },
    "volumes": [
      { "containerPath": "/var/lib/registry", "hostPath": "${DOCKER_IMAGE_LOC}", "mode": "RW" }
    ]
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
