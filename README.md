# Redis in Kubernetes(k8s)


<img src="https://github.com/marscqy/redis-in-k8s/blob/master/images/k8s-logo.png" width="100px" style="float:left" /><img src="https://github.com/marscqy/redis-in-k8s/blob/master/images/redis-logo.jpg" width="100px" style="margin-left:70px;float:left"/>


-----

   
这是一个帮助你在Kubernetes(K8S)环境中搭建redis集群和哨兵模式的样例。

> 相比于其他github上的项目，优势  1. 有集群和哨兵 2种模式  2.集群模式和哨兵模式都支持扩容  3.稳定性更强，本项目支持redis持久化,Pod重启之后集群无需手动干预,自动恢复成集群原先状态,这点在github其他项目中没有看到过类似的操作


docker 文件夹中包含了一个Dockerfile，你可以使用一下命令来创建镜像。
```
docker build -t $YOUR_TAG . && docker push $YOUR_TAG
```

k8s_installer 是github上的kubeasz项目,个人感觉写的很好,推荐一下.

redis_cluster_installer 是一个在CentOS 7 下搭建redis集群的脚本.

-----

### 使用说明

>假设你已安装k8s和docker,{} 表示变量,需要你自己填

- 1. 进入images文件夹下
```
docker build -t {yourtag} . && docker push {yourtag} 
```

- 2. yaml文件
    - 1. YourImage替换为{yourtag}
    - 2. API_SERVER_ADDR 环境变量的值修改为你的apiserver地址
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
