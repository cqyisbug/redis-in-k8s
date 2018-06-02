#!/bin/bash

mkdir -p /home/redis/log/

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

gem install --local /rdoc.gem 2>/dev/null 1>&2
gem install --local /redis.gem 2>/dev/null 1>&2
rm -f /rdoc.gem
rm -f /redis.gem

python /ep.py