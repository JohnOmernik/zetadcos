#!/bin/bash

CONF="./zeta_cluster.conf"

. $CONF

CURUSER=$(whoami)
SUDO_TEST=$(sudo whoami)


if [ "$CURUSER" != "$IUSER" ]; then
    echo "Must use $IUSER: User: $CURUSER"
fi


HOSTS=$1

if [ "$HOSTS" == "" ]; then
    echo "This script takes a single argument, enclosed by double quotes, of space separated node names to update"
    exit 1
fi


# Make sure we only have one argument, if not, exit
TEST=$2
UNATTEND="0"
if [ "$TEST" != "" ]; then
    if [ "$TEST" != "1" ]; then
        echo "Please only provide a single argument, enclosed by double quotes, of space separated node names to update"
        exit 1
    else
        UNATTEND="1"
    fi
fi
# Check to see if we are root (by running the $SUDO_TEST)
if [ "$SUDO_TEST" != "root" ]; then
    echo "This script must be run with a user with sudo privileges"
    exit 1
fi

# Iterate through each node specified in the hosts argument and check to see if the user is root or not
echo ""
echo "-------------------------------------------------------------------"
echo "Status of requested Nodes. If root is listed, permissions are setup correctly"
echo "-------------------------------------------------------------------"

CHOSTS=$(echo "$HOSTS"|tr "," " ")

for HOST in $CHOSTS; do
    OUT=$(ssh -t -t -n -o StrictHostKeyChecking=no $HOST "sudo whoami" 2> /dev/null)
    echo "$HOST     $OUT"
done

echo "-------------------------------------------------------------------"
echo ""
echo "If any of the above nodes do not say root next to the name, then the permissions are not set correctly" 
echo "If permissions are not set correctly, this script will not run well."



# Verify that the user wants to continue
if [ "$UNATTEND" == "1" ]; then
    echo "Unattended requested, I hope your permissions are correct!"
else
    read -p "Do you wish to proceed with this script? Y/N: " OURTEST

    if [ "$OURTEST" != "Y" ] && [ "$OURTEST" != "y" ]; then
        echo "Exiting"
        exit 0
    fi
fi

echo ""
echo "Creating LDAP Update Script"

SCRIPTSRC="/home/$IUSER/ldapupdate_src.sh"
SCRIPTDST="/home/$IUSER/ldapupdate.sh"

cat > $SCRIPTSRC << EOF
#!/bin/bash
DIST_CHK=\$(egrep -i -ho 'ubuntu|redhat|centos' /etc/*-release | awk '{print toupper(\$0)}' | sort -u)
UB_CHK=\$(echo \$DIST_CHK|grep UBUNTU)
RH_CHK=\$(echo \$DIST_CHK|grep REDHAT)
CO_CHK=\$(echo \$DIST_CHK|grep CENTOS)

if [ "\$UB_CHK" != "" ]; then
    INST_TYPE="ubuntu"
    echo "Ubuntu"
elif [ "\$RH_CHK" != "" ] || [ "\$CO_CHK" != "" ]; then
    INST_TYPE="rh_centos"
    echo "Redhat"
else
    echo "Unknown lsb_release -a version at this time only ubuntu, centos, and redhat is supported"
    echo \$DIST_CHK
    exit 1
fi

echo "\$INST_TYPE"

if [ "\$INST_TYPE" == "ubuntu" ]; then
   sudo DEBIAN_FRONTEND=noninteractive apt-get install -qq -y libpam-ldapd libnss-ldapd nscd

   sudo tee /usr/share/pam-configs/my_mkhomedir << EOL
Name: activate mkhomedir
Default: yes
Priority: 900
Session-Type: Additional
Session:
        required                                 pam_mkhomedir.so umask=0022 skel=/etc/skel

EOL

sudo  tee /etc/ldap.conf << EOR
# The distinguished name of the search base.
base dc=marathon,dc=mesos
# Another way to specify your LDAP server is to provide an
uri ldap://openldap-shared.marathon.slave.mesos
# The LDAP version to use (defaults to 3 if supported by client library)
ldap_version 3
pam_password md5
bind_policy soft
binddn cn=readonly,dc=marathon,dc=mesos
bindpw readonly
EOR



sudo tee /etc/nslcd.conf << EON
# /etc/nslcd.conf
# nslcd configuration file. See nslcd.conf(5)
# for details.

# The user and group nslcd should run as.
uid nslcd
gid nslcd

# The location at which the LDAP server(s) should be reachable.
uri ldap://openldap-shared.marathon.slave.mesos

# The search base that will be used for all queries.
base dc=marathon,dc=mesos

# The LDAP protocol version to use.
ldap_version 3

# The DN to bind with for normal lookups.
binddn cn=readonly,dc=marathon,dc=mesos
bindpw readonly

# The DN used for password modifications by root.
#rootpwmoddn cn=admin,dc=example,dc=com

# SSL options
#ssl off
#tls_reqcert never
tls_cacertfile /etc/ssl/certs/ca-certificates.crt

# The search scope.
#scope sub

EON

sudo DEBIAN_FRONTEND=noninteractive pam-auth-update

sudo sed -i "s/compat/compat ldap/g" /etc/nsswitch.conf

sudo /etc/init.d/nscd restart
sudo service nslcd restart

elif [ "\$INST_TYPE" == "rh_centos" ]; then
   echo "Needs work"
else
    echo "Relase not found, not sure why we are here, exiting"
    exit 1
fi

EOF

chmod +x $SCRIPTSRC

for HOST in $CHOSTS; do
    scp $SCRIPTSRC $HOST:$SCRIPTDST
    ssh $HOST "chmod +x $SCRIPTDST && $SCRIPTDST && rm $SCRIPTDST"
done

rm $SCRIPTSRC

