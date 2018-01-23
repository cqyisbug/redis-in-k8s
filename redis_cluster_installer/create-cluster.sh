#!/bin/bash

mkdir -p /tmp/redis_install
cd /tmp/redis_install

REDIS_VERSION="4.0.6"

curl -O http://download.redis.io/releases/redis-$REDIS_VERSION.tar.gz && curl -O http://www.rpmfind.net/linux/epel/7/x86_64/Packages/j/jemalloc-3.6.0-1.el7.x86_64.rpm

rpm -ivh *.rpm
yum install -y gcc
tar -zxf redis-$REDIS_VERSION.tar.gz
cd redis-$REDIS_VERSION
make MALLOC=$(which jemalloc.sh)
make install 

cd tmp

DIR_ARR=(7000 7001 7002 7003 70004 7005)

CLUSTER_COFIG=" "

for f in $DIR_ARR ; do 
    mkdir $f
    cd $f
    rm -rf *
    echo "port ${file##*/}" > redis.conf
    echo "cluster-enabled yes" >> redis.conf
    echo "cluster-config-file nodes.conf" >> redis.conf
    echo "cluster-node-timeout 5000" >> redis.conf
    echo "appendonly yes" >> redis.conf
    echo "daemonize yes" >> redis.conf
    echo "protected-mode no" >> redis.conf
    CLUSTER_COFIG=$CLUSTER_COFIG"127.0.0.1:"$f" "
    redis-server redis.conf   
    cd ..
done 

cd /tmp/redis_install/redis-$REDIS_VERSION/src
yes yes |head -1 |./redis-trib.rb create --replicas 1 $CLUSTER_COFIG