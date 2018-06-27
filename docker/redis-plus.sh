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
#      集群模式的说明:
#      集群普通节点的pod数量 必须 大于等于 (集群每个主节点的副本数*3 + 3)
#      如果想让集群外访问,只需要在yaml里面配置就可以了,不需要再来修改 shell 脚本
#
#
#==================================================================================================================



############################################   GLOBAL VARIABLES   ############################################
DATA_DIC="/home/redis/data/"
LOG_DIC="/home/redis/log/"
NODES_CONFIG_FILE="${data_dic}nodes.conf"
CLUSTER_STATEFULSET_NAME="redis-cluster-node"
CLUSTER_SERVICE_NAME="redis-cluster-svc"
CLUSTER_NAMESPACE=${MY_POD_NAMESPACE}
############################################################################################################### 




############################################     ENVIRONMENT      #############################################
# REDIS_CLUSTER_REPLICAS
# REDIS_STATEFULSET_REPLICAS
# API_SERVER_ADDR
# LOG_LEVEL
# REDIS_PORT
# MY_POD_IP
###############################################################################################################                  




##############################################   LOG FUNC   ###################################################

# 日志等级定义, 0:debug 1:info 2:warn 3:error

if test ! $LOG_LEVEL ; then
    LOG_LEVEL=0
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
        echo -e "\033[33m$time  - [WARN] $1\033[0m"
    fi 
}

function log_error(){
    if test $LOG_LEVEL -le 3 ; then
        time=$(date "+%Y-%m-%d %H:%M:%S")
        echo -e "\033[31m$time  - [ERR] $1\033[0m"
    fi 
}
###############################################################################################################



########################################     APIS     #########################################################
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
    hostnetwork=$(curl -s ${API_SERVER_ADDR}/apis/apps/v1/namespaces/${CLUSTER_NAMESPACE}/statefulsets/$1 | jq ".spec.template.spec.hostNetwork" )
    echo $hostnetwork
}

# 获取指定statefulset 下的副本数
function get_replicas(){
    replicas=$(curl -s ${API_SERVER_ADDR}/apis/apps/v1/namespaces/${CLUSTER_NAMESPACE}/statefulsets/$1 | jq ".spec.replicas")
    echo $replicas
}

# 等待指定的statefulset 下的所有的pod启动完毕
# $1 name of the statfulset
# $2 name of the statfulset's svc
function wait_all_pod_ready(){
    while true ; do
        ready_ip_length=$(ip_array_length $2) 
        replicas=$(get_replicas $1)   

        echo_debug ">>> IP_ARRAY_LENGTH : $ready_ip_length"
        echo_debug ">>> REDIS_STATEFULSET_REPLICAS : $replicas"

        if test $ready_ip_length == $replicas ; then
            log_info "[OK] All pods are ready !"
            break
        else
            sleep 10
        fi  
    done
}

# 保存ip和pod名字的对应关系
function save_relation(){
    file=$1
    REDIS_STATEFULSET_REPLICAS=$(get_replicas "${CLUSTER_STATEFULSET_NAME}")
    rm -f ${DATA_DIC}cluster-$file.ip
    index=0
    while test $index -lt $REDIS_STATEFULSET_REPLICAS ; do
        curl -s ${API_SERVER_ADDR}/api/v1/namespaces/${CLUSTER_NAMESPACE}/pods/${CLUSTER_STATEFULSET_NAME}-$index | jq ".status.podIP"  >> ${DATA_DIC}cluster-$file.ip 
        let index++
    done
    sed -i "s/\"//g" ${DATA_DIC}cluster-$file.ip
}

# 日志处理
function log_launcher(){
    {
        echo  "*       *       *       *       *       logrotate /etc/logrotate.conf "
    } >> /etc/crontabs/root

    touch /var/log/messages
	

# ${LOG_DIC}redis.log {
#     daily
#     su root root
#     rotate 7
#     create
#     nocompress
#     size 10MB
# }

    cat >> /etc/logrotate.conf <<EOF
${LOG_DIC}redis.log {
    daily
    su root root
    rotate 7
    create
    nocompress
}
EOF
    crond 
}
###############################################################################################################




#############################################  MASTER  ########################################################
# 哨兵模式 master节点启动流程代码
function master_launcher(){

    log_info ">>> Master Port : $MASTER_PORT     "
    log_info ">>> Sentinel HOST: $SENTINEL_HOST   "
    log_info ">>> Sentinel Port: $SENTINEL_PORT   "

    if test -f "/home/redis_config/slave.conf" ; then
        cp /home/redis_config/slave.conf ${DATA_DIC}slave.conf
    else
        log_error "Could not find file : /home/redis_config/slave.conf"
    fi

    if test -f "/home/redis_config/redis.conf" ; then
        cp /home/redis_config/redis.conf ${DATA_DIC}redis.conf
    else
        log_error "Could not find file : /home/redis_config/redis.conf"
    fi

    # 循环10次
    guard=0
    while test $guard -lt 10 ; do
        SENTINEL_IP=$(nslookup $SENTINEL_HOST 2>/dev/null | grep 'Address' | awk '{print $3}')
        MASTER_IP=$(redis-cli -h $SENTINEL_IP -p $SENTINEL_PORT --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
        if [[ -n $MASTER_IP && $MASTER_IP != "ERROR" ]] ; then
            MASTER_IP="${MASTER_IP//\"}"
            # 通过哨兵找到master，验证master是否正确
            redis-cli -h $MASTER_IP -p $MASTER_PORT INFO
            if test "$?" == "0" ; then
                {
                    sed -i "s/%master-ip%/$MASTER_IP/" ${DATA_DIC}slave.conf
                    sed -i "s/%master-port%/$MASTER_PORT/" ${DATA_DIC}slave.conf
                    PERSISTENT_PATH="/data/redis"
                    sed -i "s|%persistent_path%|${PERSISTENT_PATH}|" ${DATA_DIC}slave.conf
                    echo "slave-announce-ip ${MY_POD_IP}" 
                    echo "slave-announce-port $MASTER_PORT" 
                    echo "logfile ${DATA_DIC}redis.log"
                } >> ${DATA_DIC}slave.conf
                redis-server ${DATA_DIC}slave.conf --protected-mode no
                break
            else
                log_error "Can not connect to Master . Waiting...."
            fi
        fi
        let guard++
        # 如果循环了多次，都没有找到，那么就放弃啦，再来一轮寻找
        if test $guard -ge 10 ; then
            log_info "Starting master ...."
            redis-server ${DATA_DIC}redis.conf --protected-mode no
            break
        fi
        sleep 2
    done
}

###############################################################################################################


##############################################  SLAVE   #######################################################
# 哨兵模式 slave节点启动流程代码
function slave_launcher(){

    log_info ">>> Master Host : $MASTER_HOST "
    log_info ">>> Master Port : $MASTER_PORT "
    log_info ">>> Sentinel HOST: $SENTINEL_HOST  "
    log_info ">>> Sentinel Port: $SENTINEL_PORT "

    if test -f "/home/redis_config/slave.conf" ; then
        cp /home/redis_config/slave.conf ${DATA_DIC}slave.conf
    else
        log_error "Could not find file : /home/redis_config/slave.conf"
    fi


    while true; do
        SENTINEL_IP=$(nslookup ${SENTINEL_HOST} 2>/dev/null | grep 'Address' | awk '{print $3}')
        MASTER_IP=$(redis-cli -h ${SENTINEL_IP} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
        if [[ -n ${MASTER_IP} ]] && [[ ${MASTER_IP} != "ERROR" ]] ; then
            MASTER_IP="${MASTER_IP//\"}"
        else
            sleep 2
            continue
        fi

        # 先从sentinel节点查找主节点信息，如果实在没有就直接从master节点找
        redis-cli -h ${MASTER_IP} -p ${MASTER_PORT} INFO
        if [[ "$?" == "0" ]]; then
            break
        fi

        log_error "Can not connect to Master .  Waiting..."
        sleep 5
    done

    {
        sed -i "s/%master-ip%/${MASTER_IP}/" ${DATA_DIC}slave.conf
        sed -i "s/%master-port%/${MASTER_PORT}/" ${DATA_DIC}slave.conf
        PERSISTENT_PATH="${DATA_DIC}slave"
        sed -i "s|%persistent_path%|${PERSISTENT_PATH}|" ${DATA_DIC}slave.conf

        echo "slave-announce-ip ${MY_POD_IP}" 
        echo "slave-announce-port $MASTER_PORT" 
        echo "logfile ${DATA_DIC}redis.log" 
    } >> ${DATA_DIC}slave.conf

    redis-server  ${DATA_DIC}slave.conf --protected-mode no
}
###############################################################################################################


#############################################  SENTINEL  #####################################################
# 哨兵模式 哨兵节点启动流程代码
function sentinel_launcher(){

    log_info ">>> Master Host : $MASTER_HOST     "
    log_info ">>> Master Port : $MASTER_PORT     "
    log_info ">>> Sentinel SVC : $SENTINEL_SVC    "
    log_info ">>> Sentinel Port: $SENTINEL_PORT   "

    MASTER_IP=""
    while true; do
        index=0
        while true; do
            let index++
            IP_ARRAY=$(nslookup $SENTINEL_SVC 2>/dev/null | grep 'Address' |awk '{print $3}' )
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
                MASTER_IP=$(nslookup $MASTER_HOST 2>/dev/null | grep 'Address' | awk '{print $3}')
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

    {
        echo "port $SENTINEL_PORT"
        echo "sentinel monitor mymaster ${MASTER_IP} ${MASTER_PORT} 2"
        echo "sentinel down-after-milliseconds mymaster 30000"
        echo "sentinel failover-timeout mymaster 180000"
        echo "sentinel parallel-syncs mymaster 1"
        echo "bind ${MY_POD_IP} 127.0.0.1"
        echo "logfile ${DATA_DIC}redis.log"
    } >> ${DATA_DIC}redis.conf

    redis-sentinel ${sentinel_conf} --protected-mode no
}
###############################################################################################################


##############################################  CLUSTER  ######################################################
# 集群模式 普通集群节点启动流程代码
function cluster_launcher(){

    # 等待并保存ip和pod的关系
    if test -f ${DATA_DIC}cluster-old.ip ; then
        wait_all_pod_ready $CLUSTER_STATEFULSET_NAME $CLUSTER_SERVICE_NAME
    fi
    save_relation "new"

    # 如果有旧的关系文件,那么就对nodes.conf进行替换
    if test -f ${DATA_DIC}cluster-old.ip ; then
        if test -f "${DATA_DIC}nodes.conf" ; then 
            index=0
            echo_error "========old====="
            cat ${DATA_DIC}cluster-old.ip
            echo_error "========new====="
            cat ${DATA_DIC}cluster-new.ip
            echo_error "========old====="
            cat ${DATA_DIC}nodes.conf
           
            cat ${DATA_DIC}cluster-old.ip | while read oldip 
            do
                sed -i "s/${oldip}/pod${index}/g" ${DATA_DIC}nodes.conf
                let index++
            done

            echo_error "========mid====="
            cat ${DATA_DIC}nodes.conf

            index=0
            cat ${DATA_DIC}cluster-new.ip | while read newip 
            do
                sed -i "s/pod${index}/${newip}/g" ${DATA_DIC}nodes.conf
                let index++
            done

            echo_error "========new====="
            cat ${DATA_DIC}nodes.conf
        else
            log_error "[ERROR] Something wrong with presistent"
        fi
    fi

    log_info "Start Redis cluster server..."
    if test -f "/home/redis_config/redis.conf" ; then
        mv /home/redis_config/redis.conf ${DATA_DIC}redis.conf
    else
        log_error "Could not find file : /home/redis_config/redis.conf"
    fi

    sed -i "s/{port}/${REDIS_PORT}/g" ${DATA_DIC}redis.conf
    sed -i "s/{pod_ip}/${MY_POD_IP}/g" ${DATA_DIC}redis.conf
    sed -i "s/{cluster_enable}/yes/g" ${DATA_DIC}redis.conf
    sed -i "s/{appendonly}/yes/g" ${DATA_DIC}redis.conf

    redis-server ${DATA_DIC}redis.conf --protected-mode no

    # 如果已经有集群存在了就加入进去,没有集群,就不加入,这部分代码移动到了控制中心
    # if [[ $(redis-cli -h ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} -p ${REDIS_PORT} cluster nodes | wc -l) -gt 1 ]] && [[ ! -f ${DATA_DIC}cluster-old.ip ]] ; then
    #     redis-cli -p ${REDIS_PORT} cluster meet $(nslookup ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' | awk '{print $3}') ${REDIS_PORT}
    # fi 

    log_launcher

    sleep 5
    OLD_IP_LENGTH=$(ip_array_length ${CLUSTER_SERVICE_NAME}) 
    while true ; do 
        CLUSTER_CHECK_RESULT=$(ruby /redis-trib.rb check --health ${MY_POD_IP}:${REDIS_PORT} | jq ".code")
        log_debug ">>> Health Result: ${CLUSTER_CHECK_RESULT}"
        NEW_IP_LENGTH=$(ip_array_length ${CLUSTER_SERVICE_NAME})
        if test $NEW_IP_LENGTH -ge $OLD_IP_LENGTH ; then
        # 如果发现集群的replicas变少了,就不保存ip信息了,不允许缩容 
            OLD_IP_LENGTH=$NEW_IP_LENGTH
            if test ${#CLUSTER_CHECK_RESULT} == "0" ; then
                PING=$(redis-cli -p ${REDIS_PORT} ping)
                if test $? != "0" ; then
                    # exit 1
                    curl -X DELETE ${API_SERVER_ADDR}/api/v1/namespaces/${CLUSTER_NAMESPACE}/pods/${MY_POD_NAME}
                fi
            fi
            if test $CLUSTER_CHECK_RESULT == "0" ; then 
                log_debug ">>> Back up nodes.conf"
                save_relation "old"
            else
                log_error "Redis Cluster is not healthy!"
				sleep 2
            fi
        fi
        sleep 5
    done
}


###############################################################################################################




############################################### CLUSTER CTRL CENTER  ##########################################
# 集群模式 集群配置节点启动流程代码
function cluster_ctrl_launcher(){

    log_info ">>> API_SERVER_ADDR : $API_SERVER_ADDR   "
    log_info ">>> REDIS_CLUSTER_REPLICAS : $REDIS_CLUSTER_REPLICAS  "

    while true ; do
        Listener=$(curl -s ${API_SERVER_ADDR}/apis/apps/v1/namespaces/${CLUSTER_NAMESPACE}/statefulsets/${CLUSTER_STATEFULSET_NAME} | jq ".code")
        if [[ $Listener == "404" ]] ; then
            log_info ">>> Api server address: ${API_SERVER_ADDR}"
            log_info ">>> Waiting until the statefulset created: ${CLUSTER_STATEFULSET_NAME}"
            sleep 10
            continue
        else
            break
        fi
    done

    while true; do
        while true ; do 
            if test $(redis-cli -h ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} -p ${REDIS_PORT} ping 2>/dev/null | tr "a-z" "A-Z") == "PONG" ; then
                if test $(redis-cli -h ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} -p ${REDIS_PORT} cluster nodes | wc -l )  == "1" ; then
                    break
                else
                    break 2
                fi
            fi
            sleep 2            
        done
        
        log_info ">>> Performing Cluster Config Check"

        REDIS_STATEFULSET_REPLICAS=$(get_replicas "${CLUSTER_STATEFULSET_NAME}")
        NODES=$(get_nodes)
        HOST_NETWORK=$(use_hostnetwork "${CLUSTER_STATEFULSET_NAME}")

        log_info ">>> REDIS_STATEFULSET_REPLICAS: $REDIS_STATEFULSET_REPLICAS"
        log_info ">>> NODES: $NODES"
        log_info ">>> HOST_NETWORK: $HOST_NETWORK"

        let CLUSER_POD_QUANTUM=REDIS_CLUSTER_REPLICAS*3+3
        if test $REDIS_STATEFULSET_REPLICAS -lt $CLUSER_POD_QUANTUM ; then
            #这个情况下是因为组成不了集群,所以直接报错退出
            log_error " We Need More Pods "
            log_error "* pods >= (cluster_replicas + 1) * 3"
            sleep 5 
            continue
        elif [[ $REDIS_STATEFULSET_REPLICAS -gt $NODES ]] && [[ $HOST_NETWORK == "true"  ]]; then
            log_error "We Need More Nodes"
            sleep 5
            continue
        else
            log_info "[OK] Cluster Config OK!"
        fi

        log_info ">>> Performing Redis Cluster Pod Check..."

        IP_ARRAY=$(nslookup ${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' |awk '{print $3}')
        CLUSTER_CONFIG=""
        index=0
        for ip in $IP_ARRAY ;
        do
            redis-cli -h ${ip} -p ${REDIS_PORT} info 1>/dev/null 2>&1
            if test "$?" != "0" ; then
                log_debug "Could not connected to $ip , connection refused! "
                break
            fi
            CLUSTER_CONFIG=${ip}":${REDIS_PORT} "${CLUSTER_CONFIG}
            CLUSTER_NODE=${ip}
            let index++
        done

        if test $index -eq $REDIS_STATEFULSET_REPLICAS ; then
            NODES_IN_REDIS_CLUSTER=$(redis-cli -h ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} -p ${REDIS_PORT} cluster nodes | wc -l)
            if test $NODES_IN_REDIS_CLUSTER == "1" ; then

                log_info ">>> Performing Build Redis Cluster..."
                if test $REDIS_CLUSTER_REPLICAS -eq 0 ;then
                    yes yes | head -1 | ruby /redis-trib.rb create  $CLUSTER_CONFIG
                else
                    yes yes | head -1 | ruby /redis-trib.rb create --replicas $REDIS_CLUSTER_REPLICAS $CLUSTER_CONFIG
                fi
                log_info "[OK] Congratulations,Redis Cluster Completed!"
                break
            fi
        else
            log_info "Waiting POD ... "
            sleep 10
            continue
        fi
    done


    sleep 10
    while true ; do
        log_info ">>> Performing Check Redis Cluster Pod Replicas"
        
        NEW_REPLICAS=$(get_replicas "${CLUSTER_STATEFULSET_NAME}")
        NODES=$(get_nodes)
        HOST_NETWORK=$(use_hostnetwork "${CLUSTER_STATEFULSET_NAME}") 
        
        log_info ">>> Current Pod Replicas : $NEW_REPLICAS"
        log_info ">>> Current Nodes Quantum : $NODES"


        if [[ $NEW_REPLICAS -gt $NODES ]] && [[ $HOST_NETWORK == "true"  ]] ; then
            log_warn " When you use host network,make sure that the number of pod is less than node"
            sleep 10
            continue
        fi

        # 遍历ip列表,如果节点是独立的主节点,并且没有slot,就成为从节点
        POD_IPS=$(nslookup ${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' |awk '{print $3}')
        index=0
        for ip in $POD_IPS ;
        do
            count=$(redis-cli -h $ip -p ${REDIS_PORT} cluster nodes 2>/dev/null | wc -l)
            if test $count == "1" ; then 
                redis-cli -h $ip -p ${REDIS_PORT} cluster meet $(nslookup ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' | awk '{print $3}') ${REDIS_PORT}
                #如果集群内存在没有从节点的主节点,就成为其从节点
                masters=$(redis-cli -h ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} -p ${REDIS_PORT} cluster nodes | grep master | awk '{print $1}')
                tmp=""
                for master in $masters ; do
                    if test ${#master} != "0" ; then
                        slave_count=$(redis-cli -h ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} -p ${REDIS_PORT} cluster nodes | grep -v master | grep ${master} | wc -l)
                        REDIS_CLUSTER_REPLICAS_TMP=$REDIS_CLUSTER_REPLICAS
                        if test $REDIS_CLUSTER_REPLICAS  == "0" ; then
                            REDIS_CLUSTER_REPLICAS_TMP=1
                        fi
                        if test $slave_count -lt $REDIS_CLUSTER_REPLICAS_TMP; then
                            tmp="${slave_count}#${master} ${tmp}"
                        fi
                    fi
                done
                nodeid_with_least_slave=$(echo $tmp | tr " " "\n" | sort | head -1 | tr "#" " " | awk '{print $2}')  
                if test ${#nodeid_with_least_slave} != "0" ; then
                    sleep 1
                    redis-cli -h ${ip} -p ${REDIS_PORT} cluster replicate ${nodeid_with_least_slave}
                fi
            fi
        done   

        # check redis cluster and rebalance corn
        redis-trib.rb check  ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME}:${REDIS_PORT}
        
        #如果发现一个master上没有slot 就开始执行rebalance
        POD_IPS=$(nslookup ${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' |awk '{print $3}')
        for ip in $POD_IPS ; do
            nodeid=$(redis-cli -h $ip -p ${REDIS_PORT} cluster nodes | grep myself | awk '{print $1}')
            redis-cli -h ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} -p ${REDIS_PORT} cluster slots | grep $nodeid
            if test $? != "0" ; then
                 ruby /redis-trib.rb rebalance $(nslookup ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' | awk '{print $3}'):${REDIS_PORT} --auto-weights --use-empty-masters
            fi
        done


        sleep 10
    done
}


###############################################################################################################


############################################  CLUSTER CTRL EXTEND  ############################################
if test $# -ne 0 ; then

    case $1 in
        "health")
            # --health 命令不是原生的,对 redis-trib.rb 做过修改
            ruby /redis-trib.rb check --health ${CLUSTER_SERVICE_NAME}:$REDIS_PORT
            ;;
        "-h")
            # --health 命令不是原生的,对 redis-trib.rb 做过修改
            ruby /redis-trib.rb check --health ${CLUSTER_SERVICE_NAME}:$REDIS_PORT
            ;;
        "rebalance")
            ruby /redis-trib.rb rebalance $(nslookup ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' | awk '{print $3}'):${REDIS_PORT} --auto-weights --use-empty-masters
            ;;
        "-r")
            ruby /redis-trib.rb rebalance $(nslookup ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' | awk '{print $3}'):${REDIS_PORT} --auto-weights --use-empty-masters
            ;;
        *)
            echo "redis-plus helper~"
            echo "usage: sh redis-plus.sh [command]"
            echo "[command]:"
            echo "  health : get redis cluster health info"
            echo "  -h"
            echo "  rebalance : rebalance redis cluster slots"
            echo "  -r"
        ;;
    esac
    exit 0

    # if test $1 == "health" ; then
    #     ruby /redis-trib.rb check --health ${CLUSTER_SERVICE_NAME}:$REDIS_PORT
    #     exit 0 
    # fi

    # if test $1 == "rebalance" ; then
    #     ruby /redis-trib.rb rebalance $(nslookup ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' | awk '{print $3}'):${REDIS_PORT} --auto-weights --use-empty-masters
    #     exit 0 
    # fi

    # echo "redis-plus helper~"
    # echo "usage: sh redis-plus.sh [command]"
    # echo "[command]:"
    # echo "  health : get redis cluster health info"
    # echo "  rebalance : rebalance redis cluster slots"

    # exit 0
fi

###############################################################################################################


time=$(date "+%Y-%m-%d")

#############################################  LOGO  ########################################################
sed -i "s/{mode}/${MODE}/g" /logo.txt
sed -i "s/{redis_version}/${REDIS_VERSION}/g" /logo.txt
sed -i "s/{port}/${REDIS_PORT}/g" /logo.txt
sed -i "s/{date}/${time}/g" /logo.txt
cat /logo.txt
#############################################################################################################

# 安装 redis-trib.rb 的依赖
gem install --local /rdoc.gem 2>/dev/null 1>&2
gem install --local /redis.gem 2>/dev/null 1>&2
rm -f /rdoc.gem
rm -f /redis.gem

mkdir -p  /home/redis/data
mkdir -p  /home/redis/log

"$(echo ${MODE}_launcher | tr 'A-Z' 'a-z')"
if test $? == "127" : then
    echo_error "MODE must be Cluster_Ctrl | Cluster | Master | Sentinel | Slave  !"
    exit 1
fi