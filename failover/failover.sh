#!/bin/sh
sleep_time=3


revert_interface_metrics(){ #Function to revert changes to metrics
    uci set network.$main_interface.metric=$main_metric
    uci set network.$backup_interface.metric=$backup_metric
    ubus call network reload
    
}

swap_interface_metrics(){ #Function to swap interface metrics
    uci set network.$main_interface.metric=$backup_metric
    uci set network.$backup_interface.metric=$main_metric
    ubus call network reload
}

signal_handler(){ # Signal handler swaps back metrics and exits
    echo "Exiting script and changing back the metrics"
    revert_interface_metrics
    exit 0
}

main_interface=$1
backup_interface=$2


#check if both main and backup interfaces are valid wan interfaces
if ! uci get network.$main_interface | grep -q interface || ! uci get network.$main_interface._area_type | grep -q wan ; then
    echo "Selected interface either does not exist or is not a wan interface"
    exit 1
fi

if ! uci get network.$backup_interface | grep -q interface || ! uci get network.$backup_interface._area_type | grep -q wan ; then
    echo "Selected interface either does not exist or is not a wan interface"
    exit 1
fi



#store metrics of both interfaces
main_metric=$(uci get network.$main_interface.metric)
backup_metric=$(uci get network.$backup_interface.metric)

#gets the device associated with the main interface
main_device=$(ubus call network.interface.$main_interface status | grep -o '"device": ".*"' | sed 's/"device": "\(.*\)"/\1/')
#gets the device associated with the backup interface
backup_device=$(ubus call network.interface.$backup_interface status | grep -o '"device": ".*"' | sed 's/"device": "\(.*\)"/\1/')

#check if connectivity service is running on ubus
if ubus call connectivity interfaceConnection '{"ifName": "'$main_device'"}' | grep -q failed ; then
    echo "Ubus connectivity service is not running"
    exit 1
fi

#set up signal handling for reverting back interface metrics

trap signal_handler TERM
trap signal_handler INT 
trap signal_handler QUIT       

#check if main interface has connection on script startup
if ubus call connectivity interfaceConnection '{"ifName": "'$main_device'"}' | grep -q True ; then
    connection_status=true
else
    connection_status=false
    #swap interfaces metrics
    echo "Internet is down changing interfaces"
    swap_interface_metrics
fi   

while true; do

    sleep $sleep_time

    if ubus call connectivity interfaceConnection '{"ifName": "'$main_device'"}' | grep -q True ; then
        new_status=true
    else
        new_status=false
    fi 

    if [ "$new_status" = "$connection_status" ]; then #Nothing change since last
        echo "No changes in connectivity"
        continue
    elif [ "$new_status" = "true" ]; then #Connection is back swap metrics back
        echo "Internet is back changing interfaces"
        revert_interface_metrics
    else #Connection is down swap metrics
        echo "Internet is down changing interfaces"
        swap_interface_metrics
    fi

    connection_status=$new_status
    
done
