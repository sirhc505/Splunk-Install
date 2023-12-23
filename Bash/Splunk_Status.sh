#!/bin/bash
###########################################################################
# Splunk Status script v1.0                                               #
#                                                                         #
#       - This script will test the status of Splunk                      #
#                                                                         #
#       - Created by chris at uconn dot edu 11-18-2020                    #
###########################################################################
DEV_MODE="FALSE"
if [ "$DEV_MODE" == "TRUE" ] ; then
    echo "Script not ready for use!!"
    exit 1
fi

############################################################
# Variables that need to be changed for this script to run #
############################################################
SMTP_SERVER="smtp.uconn.edu"
SENDER="splunk-status@uconn.edu"
SUBJECT="Splunk Status Report for: "`hostname`
RECIPIENTS=""

#################################
# Variables used in this script #
#################################
FULL_SPLUNK="/opt/splunk/bin/splunk"
UF_SPLUNK="/opt/splunkforwarder/bin/splunk"
CURRENT_SPLUNK_SERVICE_NAME=`systemctl |grep -i splunk | awk ' { print $1 } ' | grep -v -i swap`
NUM_OF_SERVICES=`systemctl |grep -i splunk | awk ' { print $1 } ' | grep -v -i swap | wc -l`
TMP_MESSAGE_FILE="/tmp/1$(uuidgen).msg.tmp"
ACTIVE_STATE=`systemctl show -p ActiveState $CURRENT_SPLUNK_SERVICE_NAME | sed 's/ActiveState=//g'`
SUB_STATE=`systemctl show -p SubState $CURRENT_SPLUNK_SERVICE_NAME | sed 's/SubState=//g'`
SYSTEMD_FILE="`systemctl show - $CURRENT_SPLUNK_SERVICE_NAME | grep FragmentPath | cut -f2 -d\=`"
SPLUNK_VERSION=`/opt/splunkforwarder/bin/splunk version |grep build | sed -n -e 's/^.*\(\ [0-9]\..*\)/\1/p' |sed 's/^[ \t]*//;s/[ \t]*$//'`
SPLUNK_REV=`echo $SPLUNK_VERSION | awk ' { print $1 } ' | cut -f 1 -d\.`
MIN_SPLUNK_VERSION="9"
MAILX_STATUS=`rpm -q mailx`

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

send_status_report () {
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

############################################################
# Lets perform some checks before running this script      #
############################################################
# Make sure that a recipient is specified if 
# we are sending an email
if [ "$RECIPIENTS" == "" ] && [ "$SEND_MESSAGE" == "TRUE" ] ; then
    echo "You need to specify a recipient"
    exit 1
fi

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
    echo "*                          FATAL ERROR                           *" >> $TMP_MESSAGE_FILE
    echo "******************************************************************" >> $TMP_MESSAGE_FILE
    echo "* The Splunk Universal Forwarder does not appear to be installed *" >> $TMP_MESSAGE_FILE
    echo "******************************************************************" >> $TMP_MESSAGE_FILE
    send_status_report
    echo "Universal Forwarder not installed error"
    exit 1
fi

# Make sure there is only one unique Splunk Service
if [ "$NUM_OF_SERVICES" -gt 1 ] ; then
    echo "************************************************************" >> $TMP_MESSAGE_FILE
    echo "*                        FATAL ERROR                       *" >> $TMP_MESSAGE_FILE
    echo "************************************************************" >> $TMP_MESSAGE_FILE
    echo "* There is more than one splunk systemd service installed. *" >> $TMP_MESSAGE_FILE
    echo "* Please fix before running this script                    *" >> $TMP_MESSAGE_FILE
    echo "************************************************************" >> $TMP_MESSAGE_FILE
    send_status_report
    echo "Conflicting Services error"
    exit 1
fi

#####################################################################################
# We are going to want to check the status of the service. Notice that the health   #
# checks are being based on CURRENT_SPLUNK_SERVICE_NAME. There is a chance that the #
# Splunk service file is not going to be splunk.service. This is non-optimal so we  #
# will also check to make sure that the correct service name is being used          #
#####################################################################################
if [ "$ACTIVE_STATE" == "active" ] ; then
    echo "" >> $TMP_MESSAGE_FILE
    echo "PASSED: Systemd service is active"  >> $TMP_MESSAGE_FILE
else 
    echo "" >> $TMP_MESSAGE_FILE
    echo "***********************************************************" >> $TMP_MESSAGE_FILE
    echo "*                       FATAL ERROR                       *" >> $TMP_MESSAGE_FILE
    echo "***********************************************************" >> $TMP_MESSAGE_FILE
    echo "* The current state for Splunk is not active.             *" >> $TMP_MESSAGE_FILE
    echo "* This will not allow the service to start automatically. *" >> $TMP_MESSAGE_FILE
    echo "* This COULD BE fixed by running the installer script in  *" >> $TMP_MESSAGE_FILE
    echo "* this repo.                                              *" >> $TMP_MESSAGE_FILE
    echo "***********************************************************" >> $TMP_MESSAGE_FILE
fi
if [ "$SUB_STATE" == "running" ] ; then
    echo "PASSED: Splunk service currently running"  >> $TMP_MESSAGE_FILE
else 
    echo "" >> $TMP_MESSAGE_FILE
    echo "***********************************************************" >> $TMP_MESSAGE_FILE
    echo "*                         WARNING                         *" >> $TMP_MESSAGE_FILE
    echo "***********************************************************" >> $TMP_MESSAGE_FILE
    echo "* The current state for Splunk is not running.            *" >> $TMP_MESSAGE_FILE
    echo "* Data collection will not happen. This coule be a result *" >> $TMP_MESSAGE_FILE
    echo "* of the upgrade to version and the installer script in   *" >> $TMP_MESSAGE_FILE
    echo "* the repo should be executed.                            *" >> $TMP_MESSAGE_FILE
    echo "***********************************************************" >> $TMP_MESSAGE_FILE
fi
echo $STATUS_MESSAGE

if [ "$CURRENT_SPLUNK_SERVICE_NAME" == "splunk.service" ] ; then
    echo "PASSED: Systemd service name"  >> $TMP_MESSAGE_FILE
else
    echo "" >> $TMP_MESSAGE_FILE
    echo "***************************************************************************" >> $TMP_MESSAGE_FILE
    echo "*                                 WARNING                                 *" >> $TMP_MESSAGE_FILE
    echo "***************************************************************************" >> $TMP_MESSAGE_FILE
    echo "* Splunk is not currently running under the splunk.service systemd file.  *" >> $TMP_MESSAGE_FILE
    echo "* You should disable and remove the other services and then run the       *" >> $TMP_MESSAGE_FILE
    echo "* installer script in the repo.                                           *" >> $TMP_MESSAGE_FILE
    echo "***************************************************************************" >> $TMP_MESSAGE_FILE
fi

if [ "$SPLUNK_REV" -lt $MIN_SPLUNK_VERSION ] ; then
    echo "" >> $TMP_MESSAGE_FILE
    echo "***************************************************************************" >> $TMP_MESSAGE_FILE
    echo "*                                 WARNING                                 *" >> $TMP_MESSAGE_FILE
    echo "***************************************************************************" >> $TMP_MESSAGE_FILE
    echo "* The version of Splunk on this host is old. Please upgrade ASAP!!        *" >> $TMP_MESSAGE_FILE
    echo "***************************************************************************" >> $TMP_MESSAGE_FILE
else
    echo "PASSED: Splunk version $MIN_SPLUNK_VERSION" >> $TMP_MESSAGE_FILE
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
send_status_report