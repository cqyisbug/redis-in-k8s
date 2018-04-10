# -*- conding:UTF-8 -*-

import os
import json
import time
import subprocess
import sys
sys.setdefaultencoding('utf-8')


def uninstall(json_format=False):
    try:
        os.system(
            "kubectl get statefulset | grep 'sts-redis-cc' | awk '{print $1}' | xargs kubectl delete statefulset ;"
            "kubectl get statefulset | grep 'sts-redis-cluster' | awk '{print $1}' | xargs kubectl delete statefulset ;"
            "kubectl get svc | grep 'svc-redis-cc' | awk '{print $1}' | xargs kubectl delete svc ;"
            "kubectl get svc | grep 'svc-redis-cluster-np' | awk '{print $1}' | xargs kubectl delete svc ;"
            "kubectl get svc | grep 'svc-redis-cluster' | awk '{print $1}' |xargs kubectl delete svc ;"
            "kubectl get pvc | grep 'rediscluster-sts-redis-cluster' | awk '{print $1}' | xargs kubectl delete pvc ;"
        )

        result = exists_resource("statefulset", "sts-redis-cc") and \
                 exists_resource("statefulset", "sts-redis-cluster") and \
                 exists_resource("svc", "svc-redis-cc") and \
                 exists_resource("svc", "svc-redis-cluster-np") and \
                 exists_resource("svc", "svc-redis-cluster") and \
                 exists_resource("pvc", "rediscluster-sts-redis-cluster") and \
                 exists_resource("svc", "rediscluster-sts-redis-cluster")

        if not result:
            while (exists_resource("endpoints", "rediscluster") or exists_resource("svc", "rediscluster")):
                time.sleep(2)
            if json_format:
                return ResultInfo(code=0, message="redis集群删除成功").tostring()
            else:
                return True
        else:
            if json_format:
                return ResultInfo(code=2, message="redis集群删除失败").tostring()
            else:
                return False
    except Exception:
        if json_format:
            return ResultInfo(code=1, message="redis集群删除失败:").tostring()
        else:
            return False


class ResultInfo(object):
    def __init__(self, code=0, message=""):
        self.all = {}
        self.all.setdefault("code", code)
        self.all.setdefault("message", message)

    def tostring(self):
        return json.dumps(self.all)


def exists_resource(resource, pattern, bool_result=True):
    """
    kubectl get {resource} | grep "{pattern}"
    if bool_result:
        return true or false
    else:
        return {the quantum of the resource}
    """
    try:
        if len(resource) == 0 or len(pattern) == 0:
            if bool_result:
                return False
            else:
                return 0
        cmd = "kubectl get " + \
              str(resource) + " | grep \"" + str(pattern) + "\" | wc -l"
        run = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
        quantum = int(run.stdout.read().replace('\n', ''))
        if bool_result:
            return quantum > 0
        else:
            return quantum
    except Exception as e:
        if bool_result:
            return False
        else:
            return 0
