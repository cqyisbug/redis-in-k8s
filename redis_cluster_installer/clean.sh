#!/bin/sh

mkdir -p 7000 7001 7002 7003 70004 7005 
for file in ./*
do
  if [[ -d $file && ${file##*/} != "redis" ]] ; then
    cd $file
    rm -rf *.aof
    rm -rf *.rdb
    rm -rf nodes.conf
    rm -rf nohup.out
    echo "port ${file##*/}" > redis.conf
    echo "cluster-enabled yes" >> redis.conf
    echo "cluster-config-file nodes.conf" >> redis.conf
    echo "cluster-node-timeout 5000" >> redis.conf
    echo "appendonly yes" >> redis.conf
    echo "daemonize yes" >> redis.conf
    echo "protected-mode no" >> redis.conf
    cd ..
  fi
done
