#!/bin/bash

time=$(date "+%Y-%m-%d")

if [[ $MODE == "CLUSTERNODE" ]] ; then
    sed -i "s/{mode}/ClusterNode/g" /home/redis/data/logo
fi

if [[ $MODE == "CLUSTERCTRL" ]] ; then
    sed -i "s/{mode}/ClusterCtrl/g" /home/redis/data/logo
fi

sed -i "s/{redis_version}/${REDIS_VERSION}/g" /home/redis/data/logo
sed -i "s/{port}/${REDIS_PORT}/g" /home/redis/data/logo
sed -i "s/{date}/${time}/g" /home/redis/data/logo

cat /home/redis/data/logo

python /ep.py