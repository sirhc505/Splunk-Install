#!/bin/bash
###########################################################################
# Splunk Repair script v2.0                                               #
#                                                                         #
#       - This script will test the status of Splunk                      #
#                                                                         #
#       - Created by chris at uconn dot edu 11-20-2020                    #
#       - Updated for RHEL 9 by chris at uconn dot edu 07-12-2023         #  
###########################################################################
DEV_MODE="TRUE"

if [ "$DEV_MODE" == "TRUE" ] ; then
    echo "***************************************************************************"
    echo "*                                 WARNING                                 *"
    echo "***************************************************************************"
    echo "# Script not ready for use. You have been warned. Press CTRL + C to abort *"
    echo "***************************************************************************"
    for i in 1 2 3 4 5
    do
        echo -n "."
        sleep 1
    done
    echo ""
    echo "Continuing..."
fi

#+----------------------------------------------------------------------------------+
#| BEGIN SECTION: BASH SCRIPT VARIABLES                                             |
#+----------------------------------------------------------------------------------+
FULL_SPLUNK="/opt/splunk/bin/splunk"
UF_SPLUNK="/opt/splunkforwarder/bin/splunk"
CURRENT_SPLUNK_SERVICE_NAME=`systemctl list-unit-files|grep -i splunk | awk ' { print $1 } ' | grep -v -i swap`
SPLUNK_SERVICE_FILE="splunk.service"
NUM_OF_SERVICES=`systemctl |grep -i splunk | awk ' { print $1 } ' | grep -v -i swap | wc -l`
TMP_MESSAGE_FILE="/tmp/1$(uuidgen).msg.tmp"
ACTIVE_STATE=`systemctl show -p ActiveState $SPLUNK_SERVICE_FILE | cut -f 2 -d \=`
SUB_STATE=`systemctl show -p SubState $SPLUNK_SERVICE_FILE | cut -f 2 -d \=`
SYSTEMD_FILE=`systemctl show - $SPLUNK_SERVICE_FILE | grep FragmentPath | cut -f2 -d\=`
SPLUNK_VERSION=`/opt/splunkforwarder/bin/splunk version |grep build | sed -n -e 's/^.*\(\ [0-9]\..*\)/\1/p' |sed 's/^[ \t]*//;s/[ \t]*$//'`
SPLUNK_REV=`echo $SPLUNK_VERSION | awk ' { print $1 } ' | cut -f 1 -d\ `
YUM_VERSION=`dnf list splunkforwarder |tail -n 1 |awk ' { print $2 } ' |cut -f1 -d\-`
MIN_SPLUNK_VERSION="9"
SYSTEM_RAM=`free -g | grep Mem | awk '{ print $2 }'`
DEPLOYMENT_SERVER_FQDN="deploy.splunk.uconn.edu"
DEPLOYMENT_SERVER_PORT="8089"
DEPLOYMENT_SERVER="$DEPLOYMENT_SERVER_FQDN:$DEPLOYMENT_SERVER_PORT"
DEPLOY_SVR_TEST=`grep deploy.splunk.uconn.edu /opt/splunkforwarder/etc/system/local/deploymentclient.conf|awk '{ print $3 }'`


# KVSTORE Vars
SPLUNK_SVR_CONF="/opt/splunkforwarder/etc/system/local/server.conf"
KVSTORE=`grep -A1 kvstore $SPLUNK_SVR_CONF`
IS_KV_SET="[kvstore] disabled = true"
KVSET="[kvstore]
disabled = true"
KVUNSET="[kvstore]
disabled = false"

# Send Status Report Vars
#########################################################################################
# IMPORTANT NOTE:                                                                       #
#########################################################################################
# If this is set to true this will install mailx to send a message if it is not already #
# installed. If you do not want to do this then do not set to true.                     #
#########################################################################################
# Additionally the host will need to have the ability to talk to the server defined in  #
# the variable SMTP_SERVER or the client will not be able to send the message. For this #
# reason it will be SET TO NOT SEND AN EMAIL. If the firewall is blocking the port the  #
# script will hang at trying to send an email for an indeterminate amount of time.      #
#########################################################################################
SEND_MESSAGE="FALSE"

############################################################
# Variables that need to be changed for this script to run #
############################################################
SMTP_SERVER="smtp.uconn.edu"
SENDER="splunk-status@uconn.edu"
SUBJECT="Splunk Status Report for: "`hostname`
RECIPIENTS=""
MAILX_STATUS=`rpm -q mailx`
#+----------------------------------------------------------------------------------+
#| END SECTION: BASH SCRIPT VARIABLES                                               |
#+----------------------------------------------------------------------------------+


#+----------------------------------------------------------------------------------+
#| BEGIN SECTION: BASH SCRIPT FUNCTIONS                                             |
#+----------------------------------------------------------------------------------+

create_systemd_service () {
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
    # systemd has decided to change the values of how services will be run we will    #
    # set the new value here.                                                         #
    ###################################################################################
    CPU_WEIGHT="1024"


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

}

execute_installer () {
        # Execute the installer
        if [[ -f "./Splunk_Installer.sh" ]] ; then
            bash ./Splunk_Installer.sh
        else
            echo "************************************************************" >> $TMP_MESSAGE_FILE
            echo "*                        FATAL ERROR                       *" >> $TMP_MESSAGE_FILE
            echo "************************************************************" >> $TMP_MESSAGE_FILE
            echo "* The installer script is missing, please download it and  *" >> $TMP_MESSAGE_FILE
            echo "* place it in the same directory.                          *" >> $TMP_MESSAGE_FILE
            echo "************************************************************" >> $TMP_MESSAGE_FILE
            echo ""
        fi
}

pre_flight_check () {
    # Make sure Splunk Server is not installed
    if [[ -f "$FULL_SPLUNK" ]] ; then
        echo "*************************************************************************" >> $TMP_MESSAGE_FILE
        echo "*                             FATAL ERROR                               *" >> $TMP_MESSAGE_FILE
        echo "*************************************************************************" >> $TMP_MESSAGE_FILE
        echo "* You cannot run this on a server with a full Splunk deployment. It can *" >> $TMP_MESSAGE_FILE
        echo "* only be run on a server that is using the Splunk Universal Forwarder. *" >> $TMP_MESSAGE_FILE
        echo "*************************************************************************" >> $TMP_MESSAGE_FILE
        send_status_report
        echo "Full Splunk install failure"
        exit 1
    fi

    # Make sure the Splunk Universal Forwarder **IS** installed
    if [ ! -f "$UF_SPLUNK" ] ; then
        echo "******************************************************************" >> $TMP_MESSAGE_FILE
        echo "*                            WARNING                             *" >> $TMP_MESSAGE_FILE
        echo "******************************************************************" >> $TMP_MESSAGE_FILE
        echo "* The Splunk Universal Forwarder does not appear to be installed *" >> $TMP_MESSAGE_FILE
        echo "******************************************************************" >> $TMP_MESSAGE_FILE
        dnf -y install splunkforwarder
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

        echo "Universal Forwarder now installed"
        exit 1
    fi
}

validate_single_service () {
    # Make sure there is only one unique Splunk Service
    # also make sure that the service name is splunk.service
    if [ "$NUM_OF_SERVICES" -gt 1 ] || [ "$CURRENT_SPLUNK_SERVICE_NAME" != "splunk.service" ] ; then
        echo "************************************************************" >> $TMP_MESSAGE_FILE
        echo "*                          WARNING                         *" >> $TMP_MESSAGE_FILE
        echo "************************************************************" >> $TMP_MESSAGE_FILE
        echo "* There is more than one splunk systemd service installed. *" >> $TMP_MESSAGE_FILE
        echo "* Fixing.....                                              *" >> $TMP_MESSAGE_FILE
        echo "************************************************************" >> $TMP_MESSAGE_FILE

        # Find all the systemd files that have "splunk in them" and disable them
        echo "Found Multiple systemd services... Getting list!"
        SPLUNKSVC=`systemctl list-unit-files| grep -v temp | grep -v tmp | grep -i splunk |awk ' { print $1 } '`
        for i in $SPLUNKSVC
        do
                systemctl disable $i
                systemctl stop $i
        done

        # Make sure Splunk is for sure dead!
        kill -9 `ps -ax |grep splunkd | awk ' { print $1 } '`

        # Execute the installer. This is likely to create a systemd boot 
        # file which we are not going to want so we will run this BEFORE
        # the "Remove any Splunk Service Files".
        dnf -y upgrade splunkforwarder
        /opt/splunkforwarder/bin/splunk enable boot-start --accept-license --answer-yes --auto-ports --no-prompt


        # Remove any Splunk Service Files. This prevents:
        #   /etc/systemd/system/multi-user.target.wants/splunk.service
        #   /etc/systemd/system/SplunkForwarder.service
        #   /etc/systemd/system/splunk.service
        rm -f `find /etc/systemd/system | grep -v temp | grep -v tmp | grep -i splunk`
        
        # Create new service file
        create_systemd_service

        # Reload daemon
        systemctl daemon-reload
        # enable and start Splunk
        systemctl enable $SPLUNK_SERVICE_FILE
        # execute_installer
    fi
}

repair_kvstore () {
    if [ "$KVSTORE" == "$IS_KV_SET" ] ; then
        echo "PASSED: KV Store Settings"  >> $TMP_MESSAGE_FILE
    else
        if [ "$KVSTORE" != "$IS_KV_SET" ] ; then
            echo "" >> $SPLUNK_SVR_CONF
            echo $KVSET >> $SPLUNK_SVR_CONF
            # Restart Splunk with Proper settings
            systemctl restart $SPLUNK_SERVICE_FILE
        else
                echo "***************************************************************************" >> $TMP_MESSAGE_FILE
                echo "*                                 WARNING                                 *" >> $TMP_MESSAGE_FILE
                echo "***************************************************************************" >> $TMP_MESSAGE_FILE
                echo "* KV Store is manually enabled. Make sure it is not needed then set       *" >> $TMP_MESSAGE_FILE
                echo "* disabled to true in /opt/splunkforwarder/etc/system/local/server.conf   *" >> $TMP_MESSAGE_FILE
                echo "* Then restart the service with systemctl restart splunk.service          *" >> $TMP_MESSAGE_FILE
                echo "***************************************************************************" >> $TMP_MESSAGE_FILE
        fi
    fi

}

validate_service_status () {
    if [ "$ACTIVE_STATE" != "active" ] || [ "$SUB_STATE" != "running" ] ; then

        # Make sure that the current version of files are loaded
        systemctl daemon-reload
        
        # Verift Permissions and FACLs
        /usr/bin/setfacl -m u:splunk:rx /var/log
        /usr/bin/setfacl -R -m u:splunk:rx /var/log/*
        /usr/bin/setfacl -d -m u:splunk:rx /var/log
        /usr/bin/setfacl -d -R -m u:splunk:rx /var/log/*
        chown splunk.splunk /opt/splunkforwarder
        chown splunk.splunk /opt/splunkforwarder/* -R 


        if [ "$ACTIVE_STATE" != "active" ] ; then
            echo "" >> $TMP_MESSAGE_FILE
            echo "***********************************************************" >> $TMP_MESSAGE_FILE
            echo "*                         WARNING                         *" >> $TMP_MESSAGE_FILE
            echo "***********************************************************" >> $TMP_MESSAGE_FILE
            echo "* The current state for Splunk is not active.             *" >> $TMP_MESSAGE_FILE
            echo "* This will not allow the service to start automatically. *" >> $TMP_MESSAGE_FILE
            echo "* Fixing.....                                             *" >> $TMP_MESSAGE_FILE
            echo "***********************************************************" >> $TMP_MESSAGE_FILE
            systemctl enable $SPLUNK_SERVICE_FILE
        fi
        if [ "$SUB_STATE" != "running" ] ; then
            echo "" >> $TMP_MESSAGE_FILE
            echo "***********************************************************" >> $TMP_MESSAGE_FILE
            echo "*                         WARNING                         *" >> $TMP_MESSAGE_FILE
            echo "***********************************************************" >> $TMP_MESSAGE_FILE
            echo "* The current state for Splunk is not running.            *" >> $TMP_MESSAGE_FILE
            echo "* Data collection will not happen. This coule be a result *" >> $TMP_MESSAGE_FILE
            echo "* Fixing.....                                             *" >> $TMP_MESSAGE_FILE
            echo "***********************************************************" >> $TMP_MESSAGE_FILE
            systemctl start $SPLUNK_SERVICE_FILE
        fi
    fi
}

validate_splunk_version () {

    # If the current is not the same as to whaat in Satellite something went wrong
    if [ "$SPLUNK_REV" != $YUM_VERSION ] ; then
            echo "" >> $TMP_MESSAGE_FILE
            echo "***********************************************************" >> $TMP_MESSAGE_FILE
            echo "*                       FATAL ERROR                       *" >> $TMP_MESSAGE_FILE
            echo "***********************************************************" >> $TMP_MESSAGE_FILE
            echo "* The current version of Splunk is : $SPLUNK_REV          *" >> $TMP_MESSAGE_FILE
            echo "* The version that Sattelite has is : $YUM_VERSION        *" >> $TMP_MESSAGE_FILE
            echo "*                                                         *" >> $TMP_MESSAGE_FILE
            echo "* Something went wrong.                                   *" >> $TMP_MESSAGE_FILE
            echo "***********************************************************" >> $TMP_MESSAGE_FILE
    fi
}

send_status_report () {
    ############################################################
    # Lets perform some checks before running this script      #
    ############################################################
    # Make sure that a recipient is specified if 
    # we are sending an email
    if [ "$RECIPIENTS" == "" ] && [ "$SEND_MESSAGE" == "TRUE" ] ; then
        echo "You need to specify a recipient"
        exit 1
    fi

    echo "" >> $TMP_MESSAGE_FILE
    echo -e "-------------------------------System Information----------------------------" >> $TMP_MESSAGE_FILE
    echo -e "Date:\t\t\t"`date`  >> $TMP_MESSAGE_FILE
    echo -e "Memory Used:\t\t"`free | grep Mem | awk '{ printf("%.4f %\n", $4/$2 * 100.0) }'` >> $TMP_MESSAGE_FILE
    echo -e "Swap Space Free:\t"`free | grep Swap | awk '{ printf("%.4f %\n", $4/$2 * 100.0) }'` >> $TMP_MESSAGE_FILE
    echo -e "System Load:\t\t"`w|grep load |awk '{print $10}' |cut -d, -f1` >> $TMP_MESSAGE_FILE
    echo -e "Active User(s):\t\t"`w | cut -d ' ' -f1 | grep -v USER | xargs -n1` >> $TMP_MESSAGE_FILE
    echo -e "Uptime:\t\t\t"`uptime | awk '{print $3,$4}' | sed 's/,//'` >> $TMP_MESSAGE_FILE
    echo -e "Active User:\t\t"`w | cut -d ' ' -f1 | grep -v USER | xargs -n1` >> $TMP_MESSAGE_FILE
    echo -e "Active Processes:\t"`ps --no-headers  -ef|wc -l` >> $TMP_MESSAGE_FILE
    echo -e "System Main IP:\t\t"`hostname -I` >> $TMP_MESSAGE_FILE
    echo -e "Splunk Version:\t\t$SPLUNK_VERSION" >> $TMP_MESSAGE_FILE

    if [ "$SEND_MESSAGE" == "TRUE" ] ; then
        echo "Sending Message"
        if [ "$MAILX_STATUS" == "package mailx is not installed" ] ; then
            echo "Installing mailx"
            yum -y install mailx
        fi
        MSG=`cat $TMP_MESSAGE_FILE`
        echo "$MSG" | /usr/bin/mailx -v -r "$SENDER" -s "$SUBJECT" -S smtp="$SMTP_SERVER" "$RECIPIENTS"
        echo "Message sent"
    fi
    cat $TMP_MESSAGE_FILE
    rm -f $TMP_MESSAGE_FILE
}
#+----------------------------------------------------------------------------------+
#| END SECTION: BASH SCRIPT FUNCTIONS                                               |
#+----------------------------------------------------------------------------------+

###############################################################################
# Make sure we are starting with an empty file. It should be unique each time #
# but who likes suprises?                                                     #
###############################################################################
echo  > $TMP_MESSAGE_FILE

###############################################################################
# This will make sure that we are not trying to run this on a server that has #
# the full version of Splunk or does not have a Universal Forwarder already   #
# installed on it. If the forwarder is not installed then we are going to     #
# install it here.                                                            #
###############################################################################
pre_flight_check

#####################################################################################
# We are going to want to check the status of the service. Notice that the health   #
# checks are being based on CURRENT_SPLUNK_SERVICE_NAME. There is a chance that the #
# Splunk service file is not going to be splunk.service. This is non-optimal so we  #
# will also check to make sure that the correct service name is being used          #
#####################################################################################
validate_single_service

#######################################################################################
# KVSTORE (Key Value Store) is not something that is generally used or needed when    #
# using the Universal Forwarder. It is generally only used on a search head. For this #
# reason we are going to want to make sure that it is disabled. It will also improve  #
# start up times and ease upgrades.                                                   #
#######################################################################################
repair_kvstore

##########################################################################################
# The need for this will decrease over time but there are known to be multiple service   #
# names in our environment. This will remove all of the old ones and standardize on      #
# splunk.service. This remove all the old versions and then launch the installer script. #
# This will also upgrade if there is a need during the install                           #
##########################################################################################
validate_service_status

########################################################################################
# If for some reason Splunk is not running later than version $MIN_SPLUNK_VERSION then #
# this will trigger the upgrade by running the installer script.                       #
########################################################################################
validate_splunk_version

########################################################################################
# This will send or store a status report of the actions taken and either output to a  #
# screen or email it if the options have been set.                                     #
########################################################################################
send_status_report

echo ""
echo "***********************************************************"
echo "*              SPLUNK REPAIR SCRIPT COMPLETE              *"
echo "***********************************************************"
echo ""

systemctl status splunk --no-pager