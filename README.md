# Redis in Kubernetes(k8s)


<img src="https://github.com/marscqy/redis-in-k8s/blob/master/k8s-logo.png" width="100px" style="float:left" /><img src="https://github.com/marscqy/redis-in-k8s/blob/master/redis-logo.jpg" width="100px" style="margin-left:70px;float:left"/>


-----

   
这是一个帮助你在Kubernetes(K8S)环境中搭建redis集群和哨兵模式的样例。

>>> 看了Github上其他的k8s中redis的样例,要么根本没提集群模式,要么瞎写 

这里有三个文件夹目录和若干yaml配置文件，他们都是来帮助搭建redis环境的。(如果需要使用statefulset，请将你的k8s版本提升至1.5以上~,还需要有dns组件)

images 文件夹中包含了一个Dockerfile，你可以使用一下命令来创建镜像。语法请参考搜索Docker。redis环境启动规则在run_new.sh 脚本中。
```
docker build -t $YOUR_TAG .
```

k8s_installer 是一个在单节点上安装kubernetes的脚本。使用这个脚本你首先得能连网，因为我没有把其中的rpm包全部下载下来。


redis_cluster_installer 是一个在CentOS 7 下搭建redis集群的脚本，后续我会优化。

-----

### 对redis-trib.rb 的修改 2018-01-31

>> 为 add-node 添加一个auto 命令,使其能在添加完节点之后自动迁移节点
>> 为 info 添加一个 detail 命令,使其能够输出完整的集群信息

```
redis-trib.rb add-node --auto new_host:new_port existing_host:existing_port
```
<img src="https://github.com/marscqy/redis-in-k8s/blob/master/add-node.png" width="643px" height="511px" style="float:left" />
  
  
  

```
redis-trib.rb info --detail host:port
```  
<img src="https://github.com/marscqy/redis-in-k8s/blob/master/info.jpg" width="787px" height="234px" style="float:left" />


-----

### 目前我所遇到的问题
- kubernetes (k8s) 集群外如何访问 pod内的Redis？
    - 添加 NodePort Service ？这是不够的，因为当你使用redis集群模式的时候，你set 或者 get 或者其他操作，可能会重定向到其他pod，这时你可能会注意到，我用run_new.sh 搭建的集群使用的时headless service，它会重定向到一个集群内的ip，这时候怎么办？    解决办法1.尝试使用其他网络组件  解决办法2.让pod使用node借点的网络配置。给pod添加以下两个属性即可。
    ```
            hostNetwork: true
            dnsPolicy: ClusterFirstWithHostNet
    ``` 
- 当使用redis集群模式的时候，动态扩容问题？
    - 这个问题纯粹是我自己懒了，没有继续往下写，接下来的一段时间内我会补上去。

- 目前我在Dockerfile里面添加了ruby的环境
    - 打算用ruby干大事情啊....

-----

### 在K8S中的性能损耗

使用  redis-cli -h $ip -p port --latency 命令可以看到网络延时，性能损耗主要在网络和持久化策略上~  
这个需要靠各位同志自己优化了，如果我以后有好的方案，我会继续更新到这个地址的。

-----

#####  shell 脚本 ^M 错误?

记得在打镜像之前先格式化下shell脚本  
step1:vi or vim  
step2: set ff=unix  
step3: 保存   


#####  yaml 解释一波~

sf 表示statefulset
svc 表示service

- sentinel 所需: 
    - sf-redis-master.yaml
    - sf-redis-slave.yaml
    - sf-redis-sentinel.yaml
    - svc-redis-master.yaml
    - svc-redis-slave.yaml
    - svc-redis-sentinel.yaml

- cluster 所需:
    - sf-redis-cluster.yaml
    - sf-redis-cc.yaml
    - svc-redis-cluster.yaml
    - svc-redis-cc.yaml
    
------


如有疑问,请联系我:  
email:cqyisbug@163.com  
qq:377141708  
wechat:antscqy  
