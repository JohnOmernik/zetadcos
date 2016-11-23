#!/bin/bash
CONF="./zeta_cluster.conf"

. $CONF

CURUSER=$(whoami)

if [ "$CURUSER" != "$IUSER" ]; then
    echo "Must use $IUSER: User: $CURUSER"
fi
echo ""
echo "Now that your shared services are installed and working, you need to update your hosts to use the new ldap service"
echo "To do that, run:"
echo ""
echo "./host_ldap_config.sh HOSTNAME"
echo ""
echo "This will be need to be run for any new hosts as well"

read -e -p "Do you wish to update on INODES (Agent Nodes?)" -i "Y" IUPDATE

if [ "$IUPDATE" == "Y" ]; then


    echo "Updating ldap on INODES"
    TNODES=$(echo -n "$INODES"|tr ";" " ")
    for N in $TNODES; do
        NODE=$(echo $N|cut -d":" -f1)
        echo "Running on $NODE"
        ./host_ldap_config.sh $NODE 1
    done



fi

echo ""
echo ""
echo "You should probably update masters too: "
echo "> ./host_ldap_config.sh IP_OF_MASTER"
echo ""
echo ""
