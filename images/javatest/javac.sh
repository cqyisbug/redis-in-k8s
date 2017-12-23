#!/bin/sh

echo "starting compiling java code"


cd /java

javac -cp .:hutool-all-3.2.3.jar:jedis-2.9.0.jar:commons-pool2-2.4.2.jar -d . JedisTest.java

java -cp .:hutool-all-3.2.3.jar:jedis-2.9.0.jar:commons-pool2-2.4.2.jar cn.test.JedisTest


while true; do
    sleep 60
done
