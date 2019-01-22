#!/bin/bash

# ==================================================================================
#                                  Redis in K8s
#      集群模式的说明:
#      集群普通节点的pod数量 必须 大于等于 (集群每个主节点的副本数*3 + 3)
#      如果想让集群外访问,只需要在yaml里面配置就可以了,不需要再来修改 shell 脚本
#
#
#                          yaml中的环境变量
# REDIS_CLUSTER_REPLICAS            主节点副本数
# REDIS_STATEFULSET_REPLICAS        所有redis sts的个数
# API_SERVER_ADDR                   api server地址
# LOG_LEVEL                         日志等级定义, 0:debug 1:info 2:warn 3:error
# REDIS_PORT                        redis运行端口
# MY_POD_IP                         自身的pod的IP地址
#
#                          全局变量
# 数据目录
DATA_DIC="/home/redis/data/"
# 日志目录
LOG_DIC="/home/redis/log/"
# 配置文件地址
NODES_CONFIG_FILE="${data_dic}nodes.conf"
# sts的名字
CLUSTER_STATEFULSET_NAME="redis-cluster-node"
# svc的名字
CLUSTER_SERVICE_NAME="redis-cluster-svc"
# 指定的命名空间
CLUSTER_NAMESPACE=${MY_POD_NAMESPACE}
# ==================================================================================



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

# 获取指定statefulset 下是否使用hostnetwork
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
        CLUSTER_CHECK_RESULT=$(ruby redis-cli --cluster check --health ${MY_POD_IP}:${REDIS_PORT} | jq ".code")
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
                    yes yes | head -1 | redis-cli --cluster create  $CLUSTER_CONFIG
                else
                    yes yes | head -1 | redis-cli --cluster create --replicas $REDIS_CLUSTER_REPLICAS $CLUSTER_CONFIG
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
                 redis-cli --cluster rebalance $(nslookup ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' | awk '{print $3}'):${REDIS_PORT} --auto-weights --use-empty-masters
            fi
        done


        sleep 10
    done
}

if test $# -ne 0 ; then
    case $1 in
        "health")
            # --health 命令不是原生的,对 redis-trib.rb 做过修改
            redis-cli --cluster check --health ${CLUSTER_SERVICE_NAME}:$REDIS_PORT
            ;;
        "-h")
            # --health 命令不是原生的,对 redis-trib.rb 做过修改
            redis-cli --cluster check --health ${CLUSTER_SERVICE_NAME}:$REDIS_PORT
            ;;
        "rebalance")
            redis-cli --cluster rebalance $(nslookup ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' | awk '{print $3}'):${REDIS_PORT} --auto-weights --use-empty-masters
            ;;
        "-r")
            redis-cli --cluster rebalance $(nslookup ${CLUSTER_STATEFULSET_NAME}-0.${CLUSTER_SERVICE_NAME} 2>/dev/null | grep 'Address' | awk '{print $3}'):${REDIS_PORT} --auto-weights --use-empty-masters
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
fi

time=$(date "+%Y-%m-%d")

sed -i "s/{mode}/${MODE}/g" /logo.txt
sed -i "s/{redis_version}/${REDIS_VERSION}/g" /logo.txt
sed -i "s/{port}/${REDIS_PORT}/g" /logo.txt
sed -i "s/{date}/${time}/g" /logo.txt
cat /logo.txt

mkdir -p  /home/redis/data
mkdir -p  /home/redis/log

"$(echo ${MODE}_launcher | tr 'A-Z' 'a-z')"
if test $? == "127" : then
    echo_error "MODE must be Cluster_Ctrl | Cluster | Master | Sentinel | Slave  !"
    exit 1
fi