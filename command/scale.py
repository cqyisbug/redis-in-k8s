# -*- conding:UTF-8 -*-

import subprocess
import os
import json


class ResultInfo(object):
    def __init__(self, code=0, message=""):
        self.all = {}
        self.all.setdefault("code", code)
        self.all.setdefault("message", message)

    def tostring(self):
        return json.dumps(self.all)


def scale(replicas, json_format=False):
    cmd = "kubectl scale statefulset sts-redis-cluster --replicas={}"
    result = os.system(cmd.format(str(replicas)))
    if result == 0:
        return ResultInfo(code=0, message="redis集群扩容操作执行成功,集群正在扩容,请稍后再检查集群状态.").tostring()
    else:
        return ResultInfo(code=6, message="redis集群扩容失败,请联系管理员").tostring()


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
    except Exception:
        if bool_result:
            return False
        else:
            return 0
