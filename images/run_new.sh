#!/bin/bash

#==================================================================================================================
#                                  Redis in K8s
#   1. 哨兵模式
#       1. MASTER = true
#           此节点可能会变成slave,但是其一开始是master,所以有一个循环,先循环一定次数来查找哨兵,如果没找到就启动自身
#       2. SLAVE = true
#           通过哨兵节点来查询主节点的信息,一旦找到就启动
#       3. SENTINEL = true
#           机制和slave一样
#
#
#   2. 集群(主从)模式
#       1. CLUSTER = true
#           启动一个多节点的redis服务,各个节点之间没有联系
#       2. CLUSTER_CTRL = true
#           将之前的节点拼接成一个集群
#      集群模式的说明:如果想要让redis在K8S内的集群能让K8S集群外的程序访问
#      你可能需要修改 cluster_ctrl_launcher 函数,同时需要修改sf-redis-cc.yaml 中的REDIS_CLUSTER_QUANTNUM 环境变量,改为你的nodes数量,这个数量必须要大于等于3
#      
#
#==================================================================================================================


function echo_warn(){
    echo -e "\033[33m$1\033[0m"
}

function echo_info(){
    echo -e "\033[36m$1\033[0m"
}

function echo_error(){
    echo -e "\033[31m$1\033[0m"
}

function log_info(){
    time=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "\033[36m$time  -  $1\033[0m"
}

function log_warn(){
    time=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "\033[33m$time  -  $1\033[0m"
}

function log_error(){
    time=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "\033[31m$time  -  $1\033[0m"
}

function master_launcher(){

    echo_info "************************************************************************************"
    echo_info "\t\t                                "
    echo_info "\t\tMaster Port  : $MASTER_PORT     "
    echo_info "\t\tSentinel HOST: $SENTINEL_HOST   "
    echo_info "\t\tSentinel Port: $SENTINEL_PORT   "
    echo_info "\t\t                                "
    echo_info "************************************************************************************"

    # 循环10次
    guard=0
    while test $guard -lt 10 ; do
        SENTINEL_IP=$(nslookup $SENTINEL_HOST | grep 'Address' | awk '{print $3}')
        MASTER_IP=$(redis-cli -h $SENTINEL_IP -p $SENTINEL_PORT --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
        if [[ -n $MASTER_IP && $MASTER_IP != "ERROR" ]] ; then
            MASTER_IP="${MASTER_IP//\"}"
            # 通过哨兵找到master，验证master是否正确
            redis-cli -h $MASTER_IP -p $MASTER_PORT INFO
            if test "$?" == "0" ; then
                sed -i "s/%master-ip%/$MASTER_IP/" /config/redis/slave.conf
                sed -i "s/%master-port%/$MASTER_PORT/" /config/redis/slave.conf
                PERSISTENT_PATH="/data/redis/master"
                sed -i "s|%persistent_path%|${PERSISTENT_PATH}|" /config/redis/slave.conf
                THIS_IP=$(hostname -i)
                echo "slave-announce-ip $THIS_IP" >> /config/redis/slave.conf
                echo "slave-announce-port 6379" >> /config/redis/slave.conf
                redis-server /config/redis/slave.conf --protected-mode no
                break
            else
                log_error "Connecting to master failed . Waiting...."
            fi
        fi
        let guard++
        # 如果循环了多次，都没有找到，那么就放弃啦，再来一轮寻找
        if test $guard -ge 10 ; then
            log_info "Starting master ...."
            redis-server /config/redis/master.conf --protected-mode no
            break
            # 新一轮开始啦。。。
            # guard=0
        fi
        sleep 2
    done
}

function slave_launcher(){

    echo_info "************************************************************************************"
    echo_info "\t\t                                "
    echo_info "\t\tMaster Host  : $MASTER_HOST     "
    echo_info "\t\tMaster Port  : $MASTER_PORT     "
    echo_info "\t\tSentinel HOST: $SENTINEL_HOST   "
    echo_info "\t\tSentinel Port: $SENTINEL_PORT   "
    echo_info "\t\t                                "
    echo_info "************************************************************************************"

    while true; do
        SENTINEL_IP=$(nslookup ${SENTINEL_HOST} | grep 'Address' | awk '{print $3}')
        MASTER_IP=$(redis-cli -h ${SENTINEL_IP} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
        if [[ -n ${MASTER_IP} ]] && [[ ${MASTER_IP} != "ERROR" ]] ; then
            MASTER_IP="${MASTER_IP//\"}"
        else
            sleep 2
            continue
#            echo_info "Could not find sentinel nodes. direct to master node"
#            MASTER_IP=$(nslookup $MASTER_HOST | grep 'Address' | awk '{print $3}')
        fi

        # 先从sentinel节点查找主节点信息，如果实在没有就直接从master节点找
        redis-cli -h ${MASTER_IP} -p ${MASTER_PORT} INFO
        if [[ "$?" == "0" ]]; then
            break
        fi

        log_error "Connecting to master failed.  Waiting..."
        sleep 5
    done

    THIS_IP=$(hostname -i)

    sed -i "s/%master-ip%/${MASTER_IP}/" /config/redis/slave.conf
    sed -i "s/%master-port%/${MASTER_PORT}/" /config/redis/slave.conf
    PERSISTENT_PATH="/data/redis/slave"
    sed -i "s|%persistent_path%|${PERSISTENT_PATH}|" /config/redis/slave.conf

    echo "slave-announce-ip ${THIS_IP}" >> /config/redis/slave.conf
    echo "slave-announce-port 6379" >> /config/redis/slave.conf

    redis-server  /config/redis/slave.conf --protected-mode no
}

function sentinel_launcher(){

    log_info "Starting sentinels..."
    echo -e "\n"

    echo_info "************************************************************************************"
    echo_info "\t\t                                "
    echo_info "\t\tMaster Host  : $MASTER_HOST     "
    echo_info "\t\tMaster Port  : $MASTER_PORT     "
    echo_info "\t\tSentinel SVC : $SENTINEL_SVC    "
    echo_info "\t\tSentinel Port: $SENTINEL_PORT   "
    echo_info "\t\t                                "
    echo_info "************************************************************************************"

    MASTER_IP=""
    while true; do
        index=0
        while true; do
            let index++
            IP_ARRAY=$(nslookup $SENTINEL_SVC | grep 'Address' |awk '{print $3}' )
            for IP in $IP_ARRAY ;
            do
                MASTER_IP=$(redis-cli -h ${IP} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
                if [[ -n ${MASTER_IP} &&  ${MASTER_IP} != "ERROR" ]] ; then
                    MASTER_IP="${MASTER_IP//\"}"
                fi
                redis-cli -h ${MASTER_IP} -p ${MASTER_PORT} INFO
                if test "$?" == "0" ; then
                    break 3
                fi
                log_error "Sentinel IP:${IP}  Connecting to master failed.  Waiting..."
            done
            if test $index -ge 10 ; then
                log_info "Could not find the Sentinel ,Try to connenct the master directly!..."
                MASTER_IP=$(nslookup $MASTER_HOST | grep 'Address' | awk '{print $3}')
                redis-cli -h ${MASTER_IP} -p ${MASTER_PORT} INFO
                if test "$?" == "0" ; then
                    break 2
                else
                    index=0
                fi
                log_error "Sentinel IP:${IP}  Master IP: ${MASTER_IP}  Connecting to master failed.  Waiting..."
            fi
        done
    done

    log_info "Master: $MASTER_IP"

    sentinel_conf=/config/redis/sentinel.conf

    echo "port 26379" >> ${sentinel_conf}
    echo "sentinel monitor mymaster ${MASTER_IP} ${MASTER_PORT} 2" >> ${sentinel_conf}
    echo "sentinel down-after-milliseconds mymaster 30000" >> ${sentinel_conf}
    echo "sentinel failover-timeout mymaster 180000" >> ${sentinel_conf}
    echo "sentinel parallel-syncs mymaster 1" >> ${sentinel_conf}
    echo "bind $(hostname -i) 127.0.0.1" >> ${sentinel_conf}

    redis-sentinel ${sentinel_conf} --protected-mode no
}

function cluster_launcher(){
    log_info "Starting cluster ..."

    THIS_IP=$(hostname -i)
    echo "port 6379" >> /config/redis/cluster.conf
    echo "bind $(hostname -i) 127.0.0.1 " >> /config/redis/cluster.conf

    echo "slave-announce-ip ${THIS_IP}" >> /config/redis/cluster.conf
    echo "slave-announce-port 6379" >> /config/redis/cluster.conf

    echo "cluster-announce-ip ${THIS_IP}" >> /config/redis/cluster.conf
    echo "cluster-announce-port 6379" >> /config/redis/cluster.conf

    redis-server /config/redis/cluster.conf --protected-mode no
}

function cluster_ctrl_launcher(){
    echo_info "************************************************************************************"
    echo_info "\t\t                                "
    echo_info "\t\tCLUSTER SVC  : $CLUSTER_SVC     "
    echo_info "\t\tREDIS_CLUSTER_QUANTNUM : $REDIS_CLUSTER_QUANTNUM     "
    echo_info "\t\tREDIS_CLUSTER_SLAVE_QUANTNUM  : $REDIS_CLUSTER_SLAVE_QUANTNUM     "
    echo_info "\t\t                                "
    echo_info "************************************************************************************"

    log_info "Config the cluster node..."

    # 安装redis的ruby环境
#    gem install rdoc
#    gem install redis --version=4.0.1
    gem install --local /rdoc-600.gem
    gem install --local /redis-401.gem


    while true; do
        IP_ARRAY=$(nslookup $CLUSTER_SVC | grep 'Address' |awk '{print $3}')
        log_info "IP_Array: $IP_ARRAY"
        CLUSTER_CONFIG=""
        index=0
        for ip in $IP_ARRAY ;
        do
            redis-cli -h ${ip} -p 6379 INFO > tempinfo.log
            if test "$?" != "0" ; then
                log_info "Connected to $ip failed ,executing break"
                break
            fi
            CLUSTER_CONFIG=${ip}":6379 "${CLUSTER_CONFIG}
            log_info "Cluster config : $CLUSTER_CONFIG"
            CLUSTER_NODE=${ip}
            let index++
        done

        log_info "index : $index "
        if test $index -ge $REDIS_CLUSTER_QUANTNUM ; then
            log_info "Cluster controller start building redis cluster...."
            yes yes | head -1 | /code/redis/redis-trib.rb create --replicas $REDIS_CLUSTER_SLAVE_QUANTNUM $CLUSTER_CONFIG
            # 集群外访问
            # yes yes | head -1 | /code/redis/redis-trib.rb create  $CLUSTER_CONFIG
            log_info "Congratulations,Redis Cluster Completed!"
            break
        else
            log_info "Waiting for the cluster node to start...Sleep 5 secs"
            sleep 5
            continue
        fi
    done

    while true ; do
        log_info "Redis Cluster State : "
        /code/redis/redis-trib.rb check $CLUSTER_NODE:6379
        sleep 300
    done
}


if test $# -ne 0 ; then
# 开始自定义命令脚本 根据参数来进行一些查询
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
                        break 2
                    fi
                done
            done
            redis-cli -h $CLUSTER_NODE_IP -P 6379 cluster nodes
           # /code/redis/redis-trib.rb check $CLUSTER_NODE_IP:6379 #| grep -E "S|M" | awk '{print $1"@"$2"@" $3}'
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
    exit 0
fi

time=$(date "+%Y-%m-%d")
echo_info "************************************************************************************"
echo_info "\t\t\t"
echo_info "\t\t\t Redis-in-Kubernetes"
echo_info "\t\t\t Author: caiqyxyx"
echo_info "\t\t\t Github: https://github.com/marscqy/redis-in-k8s"
echo_info "\t\t\t Start Date: $time"
echo_info "\t\t\t"
echo_info "************************************************************************************"


if test ! -e /data/redis/master ; then
    mkdir -p /data/redis/master
fi

if test ! -e /data/redis/slave ; then
    mkdir -p /data/redis/slave
fi

if test ! -e /data/redis/cluster ; then
    mkdir -p /data/redis/cluster
fi

if [[ $MASTER == "true" ]] ; then
    master_launcher
    exit 0
fi

if [[ $SLAVE == "true" ]] ; then
    slave_launcher
    exit 0
fi

if [[ $SENTINEL == "true" ]] ; then
    sentinel_launcher
    exit 0
fi

if [[ $CLUSTER == "true" ]] ; then
    cluster_launcher
    exit 0
fi

if [[ $CLUSTER_CTRL == "true" ]] ; then
    cluster_ctrl_launcher
    exit 0
fi

echo_info "************************************************************************************"
echo_info "\t\t"
echo_info "\t\t       RedisDocker"
echo_info "\t\t"
echo_info "************************************************************************************"
