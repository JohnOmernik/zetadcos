#!/bin/bash

CONF="./zeta_cluster.conf"

. $CONF

CURUSER=$(whoami)

CLUSTERNAME=$(ls /mapr)

. /mapr/$CLUSTERNAME/zeta/kstore/env/zeta_shared.sh

if [ "$CURUSER" != "$IUSER" ]; then
    echo "Must use $IUSER: User: $CURUSER"
fi

NEW_APP_LOC="/mapr/$CLUSTERNAME/zeta/shared/zetaca"
echo ""
echo "This script updates and moves the currently running zetaca to be running from the MapR Filesystem"
echo ""
read -e -p "Please enter location of current zetaca: " -i "/home/$IUSER/zetaca" OLD_APP_LOC
echo ""
echo "When we create the new location at $NEW_APP_LOC you have the option to remove the old location at $OLD_APP_LOC"
echo "This is entirely up to you, if you want to keep a copy of your CA or not"
echo ""
read -e -p "Remove location zetaCA Location? " -i "Y" REMOVE_CA
echo ""
echo ""
echo "************************************"
echo ""
echo "We will be copying the CA located at $OLD_APP_LOC to $NEW_APP_LOC"
echo ""
echo "We will also be:"
echo ""
echo "- Stopping the current instance of ZetaCA"
echo "- Updating the location of the CA certs in the marathon definition"
echo "- Updating the ENV information for Zeta CA"
echo "- Restarting ZetaCA in Marathon"

echo "At this point no changes have been made, do you wish to proceed?"
read -e -p "Do you wish to proceed with Zeta CA Move? " -i "N" PROCEED

if [ -d "$NEW_APP_LOC" ]; then
    echo "The new Zeta CA Location already exists at $NEW_APP_LOC, exiting"
    exit 1
fi
if [ ! -d "$OLD_APP_LOC" ]; then
    echo "Could not find old Zeta CA location at $OLD_APP_LOC, exiting"
    exit 1
fi

if [ "$PROCEED" != "Y" ]; then
    echo "No changes made"
    exit 1
fi


mkdir -p $NEW_APP_LOC
mkdir -p ${NEW_APP_LOC}/CA
sudo chown -R zetaadm:zetaadm ${NEW_APP_LOC}
sudo chmod -R 770 ${NEW_APP_LOC}/CA
cp -R ${OLD_APP_LOC}/CA/* ${NEW_APP_LOC}/CA/
cp ${OLD_APP_LOC}/gen_java_keystore.sh ${NEW_APP_LOC}/
cp ${OLD_APP_LOC}/gen_server_cert.sh ${NEW_APP_LOC}/
cp ${OLD_APP_LOC}/zetaca_env.sh /mapr/$CLUSTERNAME/zeta/kstore/env/env_shared/
MAR_FILE="/mapr/$CLUSTERNAME/zeta/shared/zetaca/marathon.json"

APP_IMG="${ZETA_DOCKER_REG_URL}/zetaca"

. ${OLD_APP_LOC}/zetaca_env.sh


DOCKER_TAG=$(sudo docker images|grep zetaca|grep -o -P "[a-f0-9]{12}")
sudo docker tag $DOCKER_TAG $APP_IMG
sudo docker push $APP_IMG

cat > ${MAR_FILE} << EOL4
{
  "id": "shared/zetaca",
  "cpus": 1,
  "mem": 512,
  "cmd":"/bin/bash -l -c '/root/ca_rest/main.rb'",
  "instances": 1,
  "env": {
     "SERVER_PORT": "3000",
     "CA_ROOT": "/root/ca_rest/CA"
  },
  "labels": {
   "CONTAINERIZER":"Docker"
  },
  "container": {
    "type": "DOCKER",
    "docker": {
      "image": "${APP_IMG}",
      "network": "BRIDGE",
      "portMappings": [
        { "containerPort": 3000, "hostPort": ${ZETA_CA_PORT}, "servicePort": 0, "protocol": "tcp"}
      ]
    },
  "volumes": [
      {
        "containerPath": "/root/ca_rest/CA",
        "hostPath": "${NEW_APP_LOC}/CA",
        "mode": "RW"
      }
    ]
  }
}

EOL4



echo ""
echo "Removing old instance"
echo ""


MARID="shared/zetaca"
curl -X DELETE ${MARATHON_SUBMIT}/${MARID} -H "Content-type: application/json"
echo "Waiting for the deployment to finish"
sleep 10
echo "Submitting new Zeta CA"
curl -X POST $MARATHON_SUBMIT -d @${NEW_APP_LOC}/marathon.json -H "Content-type: application/json"
echo ""
echo "CA Moved!"

echo "This is where I would delete the old one"
