# Redis in Kubernetes(k8s)


<img src="https://github.com/marscqy/redis-in-k8s/blob/master/images/k8s-logo.png" width="100px" style="float:left" /><img src="https://github.com/marscqy/redis-in-k8s/blob/master/images/redis-logo.jpg" width="100px" style="margin-left:70px;float:left"/>


-----

   
这是一个帮助你在Kubernetes(K8S)环境中搭建redis集群和哨兵模式的样例。

> 相比于其他github上的项目，优势  1. 有集群和哨兵 2种模式  2.集群模式和哨兵模式都支持扩容  3.稳定性更强，本项目支持redis持久化

这里有三个文件夹目录和若干yaml配置文件，他们都是来帮助搭建redis环境的。(如果需要使用statefulset，请将你的k8s版本提升至1.5以上~,还需要有dns组件)

images 文件夹中包含了一个Dockerfile，你可以使用一下命令来创建镜像。语法请参考搜索Docker。redis环境启动规则在run_new.sh 脚本中。
```
docker build -t $YOUR_TAG .
```

k8s_installer 是一个在单节点上安装kubernetes的脚本。使用这个脚本你首先得能连网，因为我没有把其中的rpm包全部下载下来。

redis_cluster_installer 是一个在CentOS 7 下搭建redis集群的脚本，后续我会优化。

https://github.com/marscqy/redisscript 这是一个python脚本,使用方法仅供参考,Redis.py 中包含了 三个重要函数,分别是install_redis  check_redis scale_redis,用来安装 检查 扩容redis集群

-----

### 使用说明

>假设你已安装k8s和docker,{} 表示变量,需要你自己填

- 1. 进入images文件夹下
```
docker build -t {yourtag} .
```

- 2. 修改sts 开头的yaml文件
    - 1. YourImage替换为{yourtag}
    - 2. sts-redis-cc.yaml 中的API_SERVER_ADDR 值修改为你的apiserver地址
    - 3. 各个yaml中的REDIS_PORT 环境变量表示 redis在pod内使用的端口号,可改可不改
    - 4. 需要持久化? 修改 volume.beta.kubernetes.io/storage-class: "fast" 中的fast 为你的sotrageclass 名字
    - 5. 不需要持久化?在每个yaml中删除如下内容
```
        volumeMounts:
        - name: rediscluster
          mountPath: /data/redis
        securityContext:
          capabilities: {}
          privileged: true
  volumeClaimTemplates:
  - metadata:
      name: rediscluster
      annotations:
        volume.beta.kubernetes.io/storage-class: "fast"
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
```

- 3. 启动集群
    - 1.kubectl create -f {yaml}


-----

### 对redis-trib.rb 的修改 2018-01-31 


> 为 add-node 添加一个auto 命令  
> 当目前集群中的master都有从节点时,添加的节点为master  
> 当目前集群中至少存在一个master没有从节点时,添加的节点为slave    
> 此修改方便redis集群在k8s集群中的扩容，只需要使用kubectl scale sts sts-redis-cluster --replicas new_replicas 命令来完成redis集群的扩容，其中new_replicas 的数值会影响redis集群是否扩容成功


```
redis-trib.rb add-node --auto new_host:new_port existing_host:existing_port
```
<img src="https://github.com/marscqy/redis-in-k8s/blob/master/add-node.png" width="643px" height="511px" style="float:left" />
  
  
> 为 info 添加一个 detail 命令,使其能够输出完整的集群信息  

```
redis-trib.rb info --detail host:port
```  
<img src="https://github.com/marscqy/redis-in-k8s/blob/master/info.jpg" width="787px" height="234px" style="float:left" />

> 为 check新增了一个health命令，能够返回进群状态,输出json形式的信息
```
reids-trib.rb check --health
```
- {"code":0,"message":"redis集群健康"}
- {"code":1,"message":"集群节点配置异常,可能有节点正在加入到节点中"}
- {"code":2,"message":"集群中有节点正在迁移数据"}
- {"code":3,"message":"集群中有节点正在导入数据"}
- {"code":4,"message":"集群中存在尚未分配到节点上的数据槽"}


-----

### 目前我所遇到的问题
> 目前所有问题都已经解决  

- kubernetes (k8s) 集群外如何访问pod内的Redis？
    - 添加 NodePort Service ？这是不够的，因为当使用redis集群模式的时候，set 或者 get 或者其他操作，可能会重定向到其他pod，这时你可能会注意到，我用run_new.sh 搭建的集群使用的时headless service，它会重定向到一个集群内的ip，这时候怎么办？    解决办法1.尝试使用其他网络组件  解决办法2.让pod使用node借点的网络配置。给pod添加以下两个属性即可。
    ```
            hostNetwork: true
            dnsPolicy: ClusterFirstWithHostNet
    ``` 
- 当使用redis集群模式的时候，动态扩容问题？
    -  这个问题已经在2018-02-02 解决,缩容不支持,只支持扩容
-----

#####  shell 脚本 ^M 错误?
这个一个在不同操作系统下会出现的一个问题,只要调整下文件内的换行符就行,推荐dos2unix工具


#####  yaml 解释一波~

启动时没有顺序影响,需要什么模式就使用对应的yaml进行kubectl create 就行  

- sentinel哨兵模式所需: 
    - redis-sentinel.yaml

- cluster集群模式所需:
    - redis-cluster.yaml


如有疑问,请联系我:  
- email: cqyisbug@163.com  
