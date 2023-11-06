#!/bin/sh
_WHICH="/usr/bin/which"
_UCI=$($_WHICH uci)
_IP=$($_WHICH ip)
_TC=$($_WHICH tc)
_GREP=$($_WHICH grep)
_TEST=$($_WHICH test)
_EXPR=$($_WHICH expr)
_TRUE=$($_WHICH true)

config_file="ifspeed"

is_positive_num(){
    if [[ $1 =~ ^[0-9][0-9]*$ ]]; then
        return 0
    else
        return 1
    fi
}

limit_down_speed(){ #name download_speed 

    name=$1
    download_speed=$2

    ifb_name="ifb4${name}"

    if $_TEST -z "$($_IP link | $_GREP "$ifb_name")"; then
        $_IP link add name "$ifb_name" type ifb
        $_IP link set dev "$ifb_name" up
    fi
    
    download_speed="${download_speed}kbit"

    $_TC qdisc del dev "$ifb_name" root
    $_TC qdisc add dev "$ifb_name" root handle 1: htb r2q 1
    $_TC class add dev "$ifb_name" parent 1:1 classid 1:1 htb rate "$download_speed" ceil "$download_speed"
    $_TC filter add dev "$ifb_name" parent 1: matchall flowid 1:1

    $_TC qdisc replace dev "$name" ingress
    $_TC filter add dev "$name" ingress matchall action mirred egress redirect dev "$ifb_name"    
}

limit_up_speed(){ # name upload_speed
        name=$1
        upload_speed=$2
        upload_speed="${upload_speed}kbit" 
        $_TC qdisc del dev "$name" root
        $_TC qdisc add dev "$name" root cake bandwidth "$upload_speed" besteffort triple-isolate nonat nowash no-ack-filter split-gso rtt 100ms raw overhead 0
}

iteration=-1

while $_TRUE ; do

    iteration=$($_EXPR $iteration + 1)

    if $_UCI get $config_file.@rule"[$iteration]" 2>&1 | $_GREP -q "Entry not found" ; then
        break    
    fi

    name=$($_UCI get $config_file.@rule"[$iteration]".name)
    if [ ! $? -eq 0 ]; then #continue loop if option was not present i.e check for non 0 return
        continue
    fi

    #Check whether the name was an interface and get it's device if it was
    if ! $_IP a | $_GREP -q " $name: " ; then
        name=$($_UCI get network.$name.device 2>&1)
        
        if [ ! $? -eq 0 ]; then #Option was not present continue
            continue
        fi

        if ! $_IP a | $_GREP -q " $name: " ; then # Check wheter the interfaces device is valid, cotinue if not
            continue
        fi
    fi
    
    download_speed=$($_UCI get $config_file.@rule"[$iteration]".downSpeed)
    if [ ! $? -eq 0 ]; then
        continue
    fi
    
    upload_speed=$($_UCI get $config_file.@rule"[$iteration]".upSpeed)
    if [ ! $? -eq 0 ]; then
        continue
    fi

    if is_positive_num $download_speed && [ ! $download_speed -eq 0 ] ; then
        limit_down_speed $name $download_speed
    fi

    if is_positive_num $upload_speed && [ ! $upload_speed -eq 0 ] ; then
        limit_up_speed $name $upload_speed
    fi

done