# Redis in Kubernetes(k8s)
-----
> 2.1 更新摘要(2019年1月22日)
- 移除http支持,添加https支持
- 移除Ruby依赖,升级redis到5.0.3版本
- 删除多余功能,只做redis在k8s中的集群化安装配置

---
#### 配置项如下
```
{
  "api_server_addr": "",
  "redis_statefulset_replicas": "3",
  "redis_server_port": 6380,
  "redis_server_nodeport": 6379,
  "redis_docker_image": "",
  "persistent_flag": false,
  "redis_data_size": 2,
  "log_level": 0,
  "redis_cluster_replicas": 0,
  "hostnetwork": false
}
```