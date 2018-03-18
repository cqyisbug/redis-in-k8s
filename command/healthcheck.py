# -*- conding:UTF-8 -*-

import subprocess
import json

result_tuple = ("0 集群健康",
                "1 集群节点配置异常,可能有节点正在加入到节点中",
                "2 集群中有节点正在迁移数据",
                "3 集群中有节点正在导入数据",
                "4 集群中存在尚未分配到节点上的数据槽",
                "5 集群不存在")


def health_check():
    """
     0 集群健康  
     1 集群节点配置异常,可能有节点正在加入到节点中  
     2 集群中有节点正在迁移数据  
     3 集群中有节点正在导入数据  
     4 集群中存在尚未分配到节点上的数据槽  
     5 集群不存在
    """
    try:
        run = subprocess.Popen("kubectl exec -it sts-redis-cc-0 /code/redis/entrypoint.sh health",
                               shell=True,
                               stdout=subprocess.PIPE)
        result = run.stdout.read()
        dic = json.loads(result)
        return result_tuple[dic.get('code')]
    except Exception:
        return result_tuple[5]
