#!/bin/bash
###########################################################################
# Splunk install script v3.4                                              #
#                                                                         #
#       - This script will install and enable Splunk on boot              #
#       - Create File ACLS for Splunk to access logs while running as     #
#         a protected user account                                        #
#                                                                         #
#       - Created by chris at uconn dot edu 09-30-2020                    #
#       - Updated for Splunk 8 by chris at uconn dot edu 07-17-2021       #
#       - Updated for Splunk 9 by chris at uconn dot edu 11-13-2022       #
#               - 3.1 Added option for Dynamic Memory allocation          #
#               - 3.2 Moved KVstore to before launch of splunk and added  #
#                     conditional test to allow multiple runs             #
#               - 3.3 Added Deployment Server Config file test            #
#               - 3.4 Move varaibles to the top and changed Deployment    #
#                     Server to be a variable for others to use!          #
###########################################################################

#################################
# Variables used in this script #
#################################
DEPLOYMENT_SERVER_FQDN="deploy.splunk.uconn.edu"
DEPLOYMENT_SERVER_PORT="8089"
DEPLOYMENT_SERVER="$DEPLOYMENT_SERVER_FQDN:$DEPLOYMENT_SERVER_PORT"
DEPLOY_SVR_TEST=`grep deploy.splunk.uconn.edu /opt/splunkforwarder/etc/system/local/deploymentclient.conf|awk '{ print $3 }'`

SPLUNK_SERVICE_FILE="splunk.service"

SYSTEM_RAM=`free -g | grep Mem | awk '{ print $2 }'`
KVSTORE_STATUS=`grep kvstore /opt/splunkforwarder/etc/system/local/server.conf`
DEPLOY_SVR_TEST=`grep deploy.splunk.uconn.edu /opt/splunkforwarder/etc/system/local/deploymentclient.conf|awk '{ print $3 }'`

if [ "$DEPLOYMENT_SERVER_FQDN" == "" ] ; then
    echo "Please set value for DEPLOYMENT_SERVER_FQDN"
    exit 1
fi
if [ "$DEPLOYMENT_SERVER_PORT" == "" ] ; then
    echo "Please set value for DEPLOYMENT_SERVER_PORT"
    exit 1
fi


###################################################################################
# This will remove and of the old systemd scripts that might have been installed. #
# the SplunkForwarder.service is from the pre v8 installs of the Splunk           #
# Universal Forwarder                                                             #
###################################################################################
SPLUNKSVC=`systemctl list-unit-files| grep -v temp | grep -v tmp | grep -i splunk |awk ' { print $1 } '`
for i in $SPLUNKSVC
do
        systemctl disable $i
        systemctl stop $i
done

################################
# Make sure it is really dead! #
################################
kill -9 `ps -ax |grep splunkd| awk ' { print $1 } '`

#############################################
# Make sure network tools and VMware        #
# tools are installed on this host          #
# because we want LOG ALL THE THINGS (XtoY) #
#############################################
yum -y install net-tools open-vm-tools splunkforwarder

#################################################################
# After Splunk version 8.2.4 this becomes important because it  #
# will try to migrate the kvstore on Splunk to the new version  #
# but unless you are running a search head. You are not going   #
# to have one                                                   #
#################################################################
if [ "$KVSTORE_STATUS" == "[kvstore]" ] ; then
    echo "KV Store already set"
else
echo "

[kvstore]
disabled = true" >>  /opt/splunkforwarder/etc/system/local/server.conf
fi

#############################################
# Complete the last of the installation     #
# so that the agent is completely installed #
#############################################
/opt/splunkforwarder/bin/splunk enable --accept-license --answer-yes --auto-ports --no-prompt


##############################################
# Make sure the Splunk user account actually #
# exists. If not then create it!             #
##############################################
getent passwd splunk > /dev/null 2&>1

if [ $? -eq 0 ]; then
    echo "Yay, the Splunk user account already exists"
else
    echo "No, the user does not exist"
	useradd -d /opt/splunkforwarder/ -s "Splunk User"
fi


###################################################################################
# Make changes to the systemd service file for splunk. This will add the User=    #
# option so the service file. This will make splunk start as the user, splunk.    #
###################################################################################

###################################################################################
# We also need to make sure that Splunk is using less than the total ammount of   #
# system memory. If the system has less than 4GB of RAM, then we do not want to   #
# set it to zero or less!!!                                                       #
###################################################################################
if [ $SYSTEM_RAM -lt 5 ] ; then
        SYSTEM_RAM=`free -g|grep Mem | awk '{ print $2 "G" }'`
else
        SYSTEM_RAM=`free -g|grep Mem | awk '{ print $2 - 4 "G" }'`
fi

###################################################################################
# MAX_SINGLE_THREAD_PERC set the max possible system usage for a single thread.   #
#                        This will not mean that a cpu won't get pegged but as an #
#                        aggregate, the total system usage will never be 100%     #
###################################################################################
# MAX_SINGLE_THREAD_PERC="80"
# CURRENT_CPU_COUNT=`cat /proc/cpuinfo |grep processor|wc -l | awk ' { print $1 } '`
# let CPU_WEIGHT=$CURRENT_CPU_COUNT*$MAX_SINGLE_THREAD_PERC
CPU_WEIGHT=1024

###################################################################################
# Additionally I have found that the systemd file that is created by Splunk is    #
# terrible. I have yet to find an instance where it works, however that could be  #
# due to our environement which is all RHEL 7/8/9                                 #
###################################################################################
echo "#This unit file replaces the traditional start-up script for systemd
#configurations, and is used when enabling boot-start for Splunk on
#systemd-based Linux distributions.

[Unit]
Description=Systemd service file for Splunk, generated by 'splunk enable boot-start'
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
ExecStart=/opt/splunkforwarder/bin/splunk _internal_launch_under_systemd
KillMode=mixed
KillSignal=SIGINT
TimeoutStopSec=360
LimitNOFILE=65536
LimitRTPRIO=99
SuccessExitStatus=51 52
RestartPreventExitStatus=51
RestartForceExitStatus=52
User=splunk
Group=splunk
NoNewPrivileges=yes
AmbientCapabilities=CAP_DAC_READ_SEARCH
ExecStartPre=-/bin/bash -c \"chown -R splunk:splunk /opt/splunkforwarder\"
Delegate=true
MemoryMax=$SYSTEM_RAM
CPUWeight=$CPU_WEIGHT
User=splunk

PermissionsStartOnly=true
ExecStartPost=-/bin/bash -c \"chown -R splunk:splunk /sys/fs/cgroup/cpu/system.slice/%n\"
ExecStartPost=-/bin/bash -c \"chown -R splunk:splunk /sys/fs/cgroup/memory/system.slice/%n\"

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/$SPLUNK_SERVICE_FILE

#################################################################
# Set the configuration for the deployment server so the client #
# will actually start logging to the Splunk indexers            #
#################################################################
if [ "$DEPLOY_SVR_TEST" == "deploy.splunk.uconn.edu:8089" ] ; then
    echo "Deployment server properly set!"
else
    echo "Setting Deployment Server"
    echo "[deployment-client]
[target-broker:deploymentServer]
targetUri = $DEPLOYMENT_SERVER" > /opt/splunkforwarder/etc/system/local/deploymentclient.conf

fi

#####################################
# Set the file ACLs on the box      #
#####################################
/usr/bin/setfacl -m u:splunk:rx /var/log
/usr/bin/setfacl -R -m u:splunk:rx /var/log/*
/usr/bin/setfacl -d -m u:splunk:rx /var/log
/usr/bin/setfacl -d -R -m u:splunk:rx /var/log/*
chown splunk.splunk /opt/splunkforwarder/* -R 

##################################################
# Reload the services with the new Splunk script #
# and make sure the system starts on book time   #
##################################################
systemctl daemon-reload
systemctl enable $SPLUNK_SERVICE_FILE
systemctl start $SPLUNK_SERVICE_FILE

echo "Waiting to download initial config from deployment server"
sleep 30
systemctl stop $SPLUNK_SERVICE_FILE

################################################################
# This has not been needed since 8.2.4 but I will leave it in  #
# just in case there is a future bug that writes files as root #
# on the first start-up of the Splunk UF                       #
################################################################
chown splunk.splunk /opt/splunkforwarder
chown splunk.splunk -R /opt/splunkforwarder/*

systemctl start $SPLUNK_SERVICE_FILE

echo "***********************************"
echo "* Splunk UF Installation Complete *"
echo "***********************************"