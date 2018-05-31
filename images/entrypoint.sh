#!/bin/bash

# define log level, 0:debug 1:info 2:warn 3:error

if test ! $LOG_LEVEL ; then
    LOG_LEVEL=1
fi

if test ! $SHOW_HEALTH_DETAIL ; then
    SHOW_HEALTH_DETAIL=false
fi

function echo_debug(){
    if test $LOG_LEVEL -le 0 ; then
        echo -e "\033[36m$1\033[0m"
    fi 
}

function echo_info(){
    if test $LOG_LEVEL -le 1 ; then
        echo -e "\033[34m$1\033[0m"
    fi 
}

function echo_warn(){
    if test $LOG_LEVEL -le 2 ; then
        echo -e "\033[33m$1\033[0m"
    fi 
}

function echo_error(){
    if test $LOG_LEVEL -le 3 ; then
        echo -e "\033[31m$1\033[0m"
    fi 
}

function log_debug(){
    if test $LOG_LEVEL -le 0 ; then
        time=$(date "+%Y-%m-%d %H:%M:%S")
        echo -e "\033[36m$time  -  $1\033[0m"
    fi 
}

function log_info(){
    if test $LOG_LEVEL -le 1 ; then
        time=$(date "+%Y-%m-%d %H:%M:%S")
        echo -e "\033[34m$time  -  $1\033[0m"
    fi 
}

function log_warn(){
    if test $LOG_LEVEL -le 2 ; then
        time=$(date "+%Y-%m-%d %H:%M:%S")
        echo -e "\033[33m$time  - [WARNNING] $1\033[0m"
    fi 
}

function log_error(){
    if test $LOG_LEVEL -le 3 ; then
        time=$(date "+%Y-%m-%d %H:%M:%S")
        echo -e "\033[31m$time  - [ERROR] $1\033[0m"
    fi 
}


function ip_array_length(){
    ips=$(nslookup $1 2>/dev/null | grep 'Address' |awk '{print $3}')
    index=0
    for ip in $ips ;
    do
        let index++
    done
    echo $index
}

# 获取node的个数
function get_nodes(){
    nodes=$(curl -s ${API_SERVER_ADDR}/api/v1/nodes | jq ".items | length")
    echo $nodes
}

# 获取指定statefulset 下是否使用hostnetwor
function use_hostnetwork(){
    hostnetwork=$(curl -s ${API_SERVER_ADDR}/apis/apps/v1/namespaces/default/statefulsets/$1 | jq ".spec.template.spec.hostNetwork" )
    echo $hostnetwork
}

# 获取指定statefulset 下的副本数
function get_replicas(){
    replicas=$(curl -s ${API_SERVER_ADDR}/apis/apps/v1/namespaces/default/statefulsets/$1 | jq ".spec.replicas")
    echo $replicas
}

# 等待指定的statefulset 下的所有的pod启动完毕
# $1 name of the statfulset
# $2 name of the statfulset's svc
function wait_all_pod_ready(){
    while true ; do
        ready_ip_length=$(ip_array_length $2) 
        replicas=$(get_replicas $1)   

        echo_debug "-------------------- [debug] --------------------"
        echo_debug "IP_ARRAY_LENGTH  :   $ready_ip_length"
        echo_debug "REPLICAS         :   $replicas"

        if test $ready_ip_length == $replicas ; then
            log_info "[OK] Pod Ready!!!"
            break
        else
            sleep 10
        fi  
    done
}

# 保存ip和pod名字的对应关系
function save_relation(){
    file=$1
    REPLICAS=$(get_replicas "sts-redis-cluster")
    rm -f /data/redis/cluster-$file.ip
    index=0
    while test $index -lt $REPLICAS ; do
        curl -s ${API_SERVER_ADDR}/api/v1/namespaces/default/pods/sts-redis-cluster-$index | jq ".status.podIP"  >> /data/redis/cluster-$file.ip 
        let index++
    done
    sed -i "s/\"//g" /data/redis/cluster-$file.ip
}

# 集群模式 普通集群节点启动流程代码
function cluster_launcher(){
    # 等待并保存ip和pod的关系
    wait_all_pod_ready "sts-redis-cluster" "svc-redis-cluster"
    save_relation "new"

    # 如果有旧的关系文件,那么就对nodes.conf进行替换
    
    if test -f /data/redis/cluster-old.ip ; then
        if test -f "/data/redis/nodes.conf" ; then 
            index=0
            cat /data/redis/cluster-old.ip | while read oldip 
            do
                sed -i "s/${oldip}/pod${index}/g" /data/redis/nodes.conf
                let index++
            done

            index=0
            cat /data/redis/cluster-new.ip | while read newip 
            do
                sed -i "s/pod${index}/${newip}/g" /data/redis/nodes.conf
                let index++
            done
        else
            log_error "[ERROR] something wrong with presistent"
        fi
    fi

    log_info "Starting cluster ..."
    if test -f "/config/redis/cluster.conf" ; then
        cp /config/redis/cluster.conf /data/redis/cluster.conf
    else
        log_error "can not find file -> /config/redis/cluster.conf"
    fi

    {
        echo "port ${REDIS_PORT}" 
        echo "bind ${MY_POD_IP} 127.0.0.1 " 
        echo "daemonize yes" 

        echo "slave-announce-ip ${MY_POD_IP}" 
        echo "slave-announce-port ${REDIS_PORT}" 

        echo "cluster-announce-ip ${MY_POD_IP}" 
        echo "cluster-announce-port ${REDIS_PORT}" 

        echo "logfile /data/redis/redis.log" 
    } >> /data/redis/cluster.conf

    redis-server /data/redis/cluster.conf --protected-mode no

    while true ; do 
        CLUSTER_CHECK_RESULT=$(ruby /code/redis/redis-trib.rb check --health ${MY_POD_IP}:$REDIS_PORT | jq ".code")
        RESULT_LENGTH=$(echo $CLUSTER_CHECK_RESULT | wc -L)
        if test $RESULT_LENGTH != "1" ; then
            sleep 10
            continue
        fi

        log_debug ">>> Health Result: ${CLUSTER_CHECK_RESULT}"
        if test $CLUSTER_CHECK_RESULT == "0" ; then 
            log_info ">>> Back up nodes.conf"
            save_relation "old"
        fi
        sleep 10
    done
}

if test $# -ne 0 ; then
    case $1 in
        "health")
            # --health 命令不是原生的,对 redis-trib.rb 做过修改
            ruby /code/redis/redis-trib.rb check --health svc-redis-cluster:$REDIS_PORT
            ;;
        "fix")
            ruby /code/redis/redis-trib.rb fix svc-redis-cluster:$REDIS_PORT
            ;;
        *)
            log_error "wrong arguments!"
            ;;
    esac
    exit 0
fi


time=$(date "+%Y-%m-%d")
echo_info "+--------------------------------------------------------------------+"
echo_info "|                                                                    |"
echo_info "|\t\t\t Redis-in-Kubernetes"
echo_info "|\t\t\t Author: caiqyxyx"
echo_info "|\t\t\t Start Date: $time"
echo_info "|                                                                    |"
echo_info "+--------------------------------------------------------------------+"

mkdir -p /data/redis

if [[ $CLUSTER == "true" ]] ; then
    cluster_launcher
    exit 0
fi

if [[ $CLUSTER_CTRL == "true" ]] ; then
    cluster_ctrl_launcher
    exit 0
fi

echo "hello wolrd "

while true;do
 echo "sleeping"
 sleep 5
done