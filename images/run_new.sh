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
#   2. 主从模式
#       1. CLUSTER = true
#           启动一个多节点的redis服务,各个节点之间没有联系
#       2. CLUSTER_CTRL = true
#           将之前的节点拼接成一个集群
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
	echo_info "***********************                                   "
	echo_info "***********************   Master Port  : $MASTER_PORT     "
	echo_info "***********************   Sentinel HOST: $SENTINEL_HOST   "
	echo_info "***********************   Sentinel Port: $SENTINEL_PORT   "
	echo_info "***********************                                   "
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
		if test $guard -eq 10 ; then
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
	echo_info "***********************                                   "
	echo_info "***********************   Master Host  : $MASTER_HOST     "
	echo_info "***********************   Master Port  : $MASTER_PORT     "
	echo_info "***********************   Sentinel HOST: $SENTINEL_HOST   "
	echo_info "***********************   Sentinel Port: $SENTINEL_PORT   "
	echo_info "***********************                                   "
	echo_info "************************************************************************************"

	while true; do
		SENTINEL_IP=$(nslookup ${SENTINEL_HOST} | grep 'Address' | awk '{print $3}')
		MASTER_IP=$(redis-cli -h ${SENTINEL_IP} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
		if [[ -n ${MASTER_IP} ]] && [[ ${MASTER_IP} != "ERROR" ]] ; then
			MASTER_IP="${MASTER_IP//\"}"
		else
		    sleep 2
		    continue
#			echo_info "Could not find sentinel nodes. direct to master node"
#			MASTER_IP=$(nslookup $MASTER_HOST | grep 'Address' | awk '{print $3}')
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
	echo_info "***********************                                   "
	echo_info "***********************   Master Host  : $MASTER_HOST     "
	echo_info "***********************   Master Port  : $MASTER_PORT     "
	echo_info "***********************   Sentinel SVC : $SENTINEL_SVC    "
	echo_info "***********************   Sentinel Port: $SENTINEL_PORT   "
	echo_info "***********************                                   "
	echo_info "************************************************************************************"

#  	while true; do
#    	SENTINEL_IP=$(nslookup ${SENTINEL_HOST} | grep 'Address' | awk '{print $3}')
#		# 不断根据哨兵节点的dns地址解析到ip地址，然后进行查询
#		MASTER_IP=$(redis-cli -h ${SENTINEL_IP} -p ${SENTINEL_PORT} --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
#		if [[ -n ${MASTER_IP} &&  ${MASTER_IP} != "ERROR" ]] ; then
#			MASTER_IP="${MASTER_IP//\"}"
#		else
#			echo_info "Could not find sentinel nodes. direct to master node..."
#			MASTER_IP=$(nslookup $MASTER_HOST | grep 'Address' | awk '{print $3}')
#		fi
#
#		redis-cli -h ${MASTER_IP} -p ${MASTER_PORT} INFO
#		if test "$?" == "0" ; then
#			break
#		fi
#		echo_warn "Connecting to master failed.  Waiting..."
#		sleep 10
#	done

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
            if test $index -eq 10 ; then
                MASTER_IP=$(nslookup $MASTER_HOST | grep 'Address' | awk '{print $3}')
                redis-cli -h ${MASTER_IP} -p ${MASTER_PORT} INFO
                if test "$?" == "0" ; then
                    break 2
                fi
                log_error "Sentinel IP:${IP}  Connecting to master failed.  Waiting..."
            fi
        done
    done

	sentinel_conf=/config/redis/sentinel.conf
 
	echo "port 26379" >> ${sentinel_conf}
	echo "sentinel monitor mymaster ${MASTER_IP} ${MASTER_PORT} 2" >> ${sentinel_conf}
	echo "sentinel down-after-milliseconds mymaster 30000" >> ${sentinel_conf}
	echo "sentinel failover-timeout mymaster 180000" >> ${sentinel_conf}
	echo "sentinel parallel-syncs mymaster 1" >> ${sentinel_conf}
	echo "bind 0.0.0.0" >> ${sentinel_conf}

  	redis-sentinel ${sentinel_conf} --protected-mode no
}

function cluster_launcher(){
	log_info "Starting cluster ..."
	echo -e "\n\n"
	redis-server /config/redis/cluster.conf --protected-mode no
}

function cluster_ctrl_launcher(){
	echo_info "************************************************************************************"
	echo_info "***********************                                   "
	echo_info "***********************   CLUSTER SVC  : $CLUSTER_SVC     "
	echo_info "***********************                                   "
	echo_info "************************************************************************************"


	log_info "Config the cluster node..."

    # 安装redis的ruby环境
    gem install rdoc
    gem install redis

    while true; do

        IP_ARRAY=$(nslookup $CLUSTER_SVC | grep 'Address' |awk '{print $3}')
        CLUSTER_CONFIG=""
        index=0
        for ip in $IP_ARRAY ;
        do
            CLUSTER_CONFIG=${ip}":6379 "${CLUSTER_CONFIG}
            let index++
        done

        if test $index -eq 6 ; then
            log_info "Cluster controller start working...."
            yes yes | head -1 | /code/redis/redis-trib.rb create --replicas 1 $CLUSTER_CONFIG
            break
        else
            sleep 1
            continue
        fi
    done

    while true ; do
        sleep 60
    done
}

echo_info "************************************************************************************"
echo_info "***********************                                   **************************"
echo_info "***********************          RedisDocker start        **************************"
echo_info "***********************          Author: Caiqyxyx         **************************"
echo_info "***********************          Date: 2017-12-17         **************************"
echo_info "***********************                                   **************************"
echo_info "************************************************************************************"

echo -e "\n\n\n\n"


if test ! -e /data/redis/master ; then
	mkdir -p /data/redis/master
fi

if test ! -e /data/redis/slave ; then
	mkdir -p /data/redis/slave
fi

if test ! -e /data/redis/cluster ; then
	mkdir -p /data/redis/cluster
fi

#if test -n $1 ; then
#    echo $1
#    exit 0
#fi

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
echo_info "***********************                                   **************************"
echo_info "***********************          RedisDocker end          **************************"
echo_info "***********************                                   **************************"
echo_info "************************************************************************************"