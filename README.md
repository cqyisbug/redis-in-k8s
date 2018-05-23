# Redis in Kubernetes(k8s)


<img src="https://github.com/marscqy/redis-in-k8s/blob/master/images/k8s-logo.png" width="100px" style="float:left" /><img src="https://github.com/marscqy/redis-in-k8s/blob/master/images/redis-logo.jpg" width="100px" style="margin-left:70px;float:left"/>

-----

这是一个帮助你在Kubernetes(K8S)环境中搭建redis集群和哨兵模式的样例。

> 相比于其他github上的项目，优势有如下几点
> 1. 有集群和哨兵 2种模式  
> 2. 集群模式和哨兵模式都支持扩容  
> 3. 稳定性更强，本项目支持redis持久化,Pod重启之后集群无需手动干预,自动恢复。这点独一无二。

-----

### redis_cluster安装说明，sentinel的以后再补

>假设你已安装k8s和docker,{} 表示变量,需要你自己填

- 1. 进入docker文件夹下
```
docker build -t {yourtag} . && docker push {yourtag} 
```

- 2. 使用pip安装python依赖
```
pip install jinja2
```

- 3. 修改redis.json
```
{
  "api_server_addr":"172.27.25.35:8080",   apiserver的地址
  "redis_replicas": "3",                   sts-redis-cluster 的pod数量，也就是你redis的节点数，最小是3
  "redis_server_port": 6380,               redis服务占用的端口
  "redis_server_nodeport":6379,            nodeport的redis端口，和redis_server_port尽量不一样，一样的话你可以试试，你会吃亏的，这里不细讲了
  "redis_docker_image": "redis:local",     第一步你打完镜像的名字
  "persistent_flag": false,                是否开启持久化
  "redis_data_size": 2,                    持久化存储卷的大小，单位Gi
  "log_level":0,                           0:debug 1:info 2:warn 3:error
  "pre_master_replicas":0                  这个参数和redis_replicas有关，表示redis集群中每个主节点的从节点数量，和redis_replicas 满足关系式  redis_replicas >= (pre_master_replicas + 1)*3
}

```

- 4. 运行redis.py
```
python redis.py install （安装）
python redis.py uninstall （卸载）
python redis.py check (检查集群)
python redis.py scale [new_replicas] (集群扩容)

```


-----

- install
![install](images\install.png)

- check
![check](images\check.jpg)

- 控制节点输出
![installation_info](images\install_info.jpg)

- scale
![之前](images\pre_scale.jpg)
![之后](images\after_sacle.jpg)

-----
### 文件夹说明

docker 文件夹中包含了一个Dockerfile，你可以使用一下命令来创建镜像。
```
docker build -t $YOUR_TAG . && docker push $YOUR_TAG
```

k8s_installer 是github上的kubeasz项目,个人感觉写的很好,推荐一下.

redis_cluster_installer 是一个在CentOS 7 下搭建redis集群的脚本.


-----

### 目前我所遇到的问题

- 当statefulset的pod所在的node节点挂了之后,pod无法完成调度,pod的状态变为unknow,此时集群一般情况下能正常使用,但是扩容和卸载操作均会受到影响
- redis的集群扩容,有过redis运维经验的人一般都知道,redis的作者提供了一个redis-trib的工具,这个工具中的添加节点和迁移slot是两个分开的命令,至于为什么要分开,个人测试了下发现添加完节点之后,就算此时你检测到集群的状态是正常的,立马迁移slot也会出问题,需要等一段时间之后才能进行迁移slot操作

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
