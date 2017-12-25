Redis in K8s
===
环境
---
k8s 高于 **1.5** 版本 因为要用statefulset 嘛

1.5 环境下删除
每个statefulset 下面的
```
        securityContext:
          capabilities: {}
          privileged: true
```
Dockfile 
---
基于alpine3.6  redis的版本为4.0.1 
修改时区为东八区

shell 脚本 ^M 错误?
---
在打镜像之前先格式化下shell脚本
step1:vi or vim
step2: set ff=unix
step3: 保存 


这么多yaml?
---
sf 表示statefulset
svc 表示service

- cluster 所需: 
    - sf-redis-master.yaml
    - sf-redis-slave.yaml
    - sf-redis-sentinel.yaml
    - svc-redis-master.yaml
    - svc-redis-slave.yaml
    - svc-redis-sentinel.yaml

- sentinel 所需:
    - sf-redis-cluster.yaml
    - sf-redis-cc.yaml
    - svc-redis-cluster.yaml
    - svc-redis-cc.yaml
    
    
如有疑问,请联系我:
email:cqyisbug@163.com
qq:377141708
wechat:antscqy