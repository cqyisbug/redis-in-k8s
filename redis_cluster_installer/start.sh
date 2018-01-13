#!/bin/sh
for file in ./*
do
    if test -d $file ; then
        echo  start redis config in $file
	cd $file
	pwd
	redis-server "./redis.conf"	
	cd ..
    fi
done
