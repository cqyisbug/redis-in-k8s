# redis 集群创建启动脚本,避免重复劳动

#!/bin/bash

ps -ef | grep redis | awk '{print $2}' | xargs kill -9
rpm -qa | grep -E "redis|jemalloc" | rpm -e
yum install -y gcc

REDIS_VERSION=5.0.3

command_exists(){
	command -v "$@" > /dev/null 2>&1
}

# Listener=$(redis-cli -v)
if ! command_exists redis-cli ; then 
	mkdir -p /tmp/redis
	cd /tmp/redis
	curl -O http://download.redis.io/releases/redis-$REDIS_VERSION.tar.gz
	curl -O https://www.rpmfind.net/linux/epel/7/x86_64/Packages/j/jemalloc-3.6.0-1.el7.x86_64.rpm
	tar -zxf redis-$REDIS_VERSION.tar.gz
	rpm -ivh *.rpm
	cd redis-$REDIS_VERSION
	cd deps
	make hiredis jemalloc linenoise lua
	cd ..
	make MALLOC=$(which jemalloc.sh)
	make install
	# cp src/redis-trib.rb /usr/bin/redis-trib.rb
	# chmod +x /usr/bin/redis-trib.rb
fi

Cluster_Config=""

for file in 7000 7001 7002 7003 7004 7005 ; do
	echo $file
	rm -rf /redis/$file
	mkdir -p /redis/$file
	cd /redis/$file
	echo "bind $(hostname -i) 127.0.0.1" > /redis/$file/redis.conf
	echo "port $file" >> /redis/$file/redis.conf
	echo "appendonly yes" >> /redis/$file/redis.conf
	echo "daemonize yes" >> /redis/$file/redis.conf
	echo "cluster-enabled yes" >> /redis/$file/redis.conf
	echo "cluster-config-file nodes.conf" >> /redis/$file/redis.conf
	echo "cluster-node-timeout 5000" >> /redis/$file/redis.conf
	redis-server redis.conf
	Cluster_Config=$Cluster_Config"$(hostname -i):$file "
done

echo yes | redis-cli --cluster create --cluster-replicas 1 $Cluster_Config
