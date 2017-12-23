#!/bin/sh

function echo_info(){
	echo -e "\033[36m$1\033[0m"
}

if test $# -ne 0 ; then
    time=$(date "+%Y-%m-%d")
    echo_info "************************************************************************************"
    echo_info "***********************                                   **************************"
    echo_info "***********************          RedisScript start        **************************"
    echo_info "***********************          Author: Caiqyxyx         **************************"
    echo_info "***********************          Date: $time         **************************"
    echo_info "***********************                                   **************************"
    echo_info "************************************************************************************"

    case $1 in
        "nodes")
            while true;do
                IP_ARRAY=$(nslookup $CLUSTER_SVC | grep 'Address' |awk '{print $3}')
                CLUSTER_CONFIG=""
                index=0
                for ip in $IP_ARRAY ;
                do
                    redis-cli -h ${ip} -p 6379 INFO > tempinfo.log
                    if test "$?" == "0" ; then
                        CLUSTER_NODE_IP=$ip
                        break
                    fi
                done
            done
            /code/redis/redis-trib.rb check $CLUSTER_NODE_IP:6379 #| grep -E "S|M" | awk '{print $1"@"$2"@" $3}'
            ;;
        "node")
            case $2 in
                "-add")

                    ;;
                "-delete")
                    ;;
                *)
                    ;;
             esac
            ;;
        *)
            echo "end"
        ;;
    esac
fi