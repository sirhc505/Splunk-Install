#!/usr/bin/bash
###########################################################################
# Splunk 9 Upgrade script v1.0                                            #
#                                                                         #
#       - This script will test the status of Splunk                      #
#                                                                         #
#       - Created by chris at uconn dot edu 07-07-2022s                   #
###########################################################################

#+----------------------------------------------------------------------------------+
#| BEGIN SECTION: BASH SCRIPT VARIABLES                                             |
#+----------------------------------------------------------------------------------+
VENDOR_SERVICE="/etc/systemd/system/SplunkForwarder.service"
ITS_SERVICE="/etc/systemd/system/splunk.service"
SPLUNK_USER="splunk"
SPLUNK_GROUP="splunk"
DNF_PACKAGE="splunkforwarder"
SPLUNK_EXE="/opt/splunkforwarder/bin/splunk"
DNF="/usr/bin/dnf"
SYSTEMCTL="/usr/bin/systemctl"

dnf update $DNF_PACKAGE

# Make sure there is only one unique Splunk Service
# also make sure that the service name is splunk.service
if [ -f "$VENDOR_SERVICE" ]; then
    $SYSTEMCTL stop SplunkForwarder
    $SYSTEMCTL disable SplunkForwarder 
    rm -f $VENDOR_SERVICE
    $SYSTEMCTL daemon-reload
    VENDOR_SERVICE_EXISTS=0
fi

if [ -f "$ITS_SERVICE" ]; then
    $SYSTEMCTL stop
    $SYSTEMCTL stop splunk
    echo "Waiting for Splunk to stop"
    sleep 1
    echo "Starting Splunk"
    $SYSTEMCTL start splunk
fi

# Get the current status of the splunk service
$SYSTEMCTL is-active --quiet splunk

if [ "$?" -eq 0 ]; then
    echo "Splunk successfully updated without migration required"
else
    echo "Requires migration"
    $SPLUNK_EXE enable --accept-license --answer-yes --auto-ports --no-prompt
    chown $SPLUNK_USER.$SPLUNK_GROUP /opt/splunkforwarder
    chown $SPLUNK_USER.$SPLUNK_GROUP /opt/splunkforwarder/* -R
    $SYSTEMCTL start splunk   
fi

sleep 1
echo "Checking status of Splunk"

$SYSTEMCTL is-active --quiet splunk
if [ "$?" -ne 0 ]; then
    echo "Something is wrong"
fi