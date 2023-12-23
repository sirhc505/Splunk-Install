#+----------------------------------------------------------------------------------+
#| BEGIN SECTION: BASH SCRIPT VARIABLES                                             |
#+----------------------------------------------------------------------------------+
NUM_OF_SERVICES=`systemctl |grep -i splunk | awk ' { print $1 } ' | grep -v -i swap | wc -l`
CURRENT_SPLUNK_SERVICE_NAME=`systemctl list-unit-files|grep -i splunk | awk ' { print $1 } ' | grep -v -i swap`
TMP_MESSAGE_FILE="/tmp/1$(uuidgen).msg.tmp"

#+----------------------------------------------------------------------------------+
#| BEGIN SECTION: BASH SCRIPT VARIABLES                                             |
#+----------------------------------------------------------------------------------+
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

        # Remove any Splunk Service Files. This prevents:
        #   /etc/systemd/system/multi-user.target.wants/splunk.service
        #   /etc/systemd/system/SplunkForwarder.service
        #   /etc/systemd/system/splunk.service
        rm -f `find /etc/systemd/system | grep -v temp | grep -v tmp | grep -i splunk`
    fi
}

#####################################################################################
# We are going to want to check the status of the service. Notice that the health   #
# checks are being based on CURRENT_SPLUNK_SERVICE_NAME. There is a chance that the #
# Splunk service file is not going to be splunk.service. This is non-optimal so we  #
# will also check to make sure that the correct service name is being used          #
#####################################################################################
validate_single_service