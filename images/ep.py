#env /usr/bin/python
# -*- coding:UTF-8 -*-

import os
import time
import urllib
import urllib2
import json
import subprocess

LOG_LEVEL = os.getenv("log_level".upper())
if not str(LOG_LEVEL):
    LOG_LEVEL = 0

EXIST_FLAG_FILE = "/home/redis/data/existflag"
CLUSTER_STATEFULSET_NAME = "sts-redis-cluster"
CLUSTER_SERVICE_NAME = "svc-redis-cluster"
CLUSTER_NAMESPACE = "default"
API_SERVER_ADDR = os.getenv("api_server_addr".upper())


def info(out):
    if str(LOG_LEVEL).upper() == "INFO" or str(LOG_LEVEL) == "0":
        print(str(time.strftime("%Y-%m-%d %H:%M:%S - ", time.localtime())) +
              "  \033[34m"+str(out)+"\033[0m")


def warn(out):
    if str(LOG_LEVEL).upper() == "WARN" or str(LOG_LEVEL) == "1":
        print(str(time.strftime("%Y-%m-%d %H:%M:%S - ", time.localtime())) +
              "  \033[33m"+str(out)+"\033[0m")


def error(out):
    if str(LOG_LEVEL).upper() == "ERROR" or str(LOG_LEVEL) == "2":
        print(str(time.strftime("%Y-%m-%d %H:%M:%S - ", time.localtime())) +
              "  \033[31m"+str(out)+"\033[0m")


def http_get(url):
    try:
        req = urllib2.Request(url)
        res_data = urllib2.urlopen(req)
        res = res_data.read()
    except Exception:
        return ""
    return res


def api(suffix):
    try:
        res = json.loads(http_get(API_SERVER_ADDR+str(suffix)))
        return res
    except Exception:
        return {}


def cluster_exists():
    if cluster_statefulset_exists() and check_redis_cluster():
        return True
    else:
        return False


def get_redis_cluster_nodes(return_int=True):
    try:
        cmd = "redis-cli -h {statefulset}-0.{service} -p ${REDIS_PORT}  cluster nodes | wc -l".format(
            statefulset=CLUSTER_STATEFULSET_NAME, service=CLUSTER_SERVICE_NAME)
        run = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
        quantum = int(run.stdout.read().replace('\n', ''))
        if return_int:
            return quantum
        else:
            return quantum > 0
    except Exception:
        if return_int:
            return 0
        else:
            return False


def get_redis_cluster_ready_pods(return_int=True):
    if return_int:
        return len(get_cluster_endpoint_info()["ok"])
    else:
        return get_cluster_endpoint_info()["ok"]


def cluster_statefulset_exists():
    try:
        res = api(
            "/apis/apps/v1/namespaces/{namespace}/statefulsets".format(namespace=CLUSTER_NAMESPACE))
        for k, v in res["items"]:
            if k["metadata"]["name"] == CLUSTER_STATEFULSET_NAME:
                return True
        return False
    except Exception:
        return False


def check_redis_cluster(verbose=True):
    pass


def create_redis_cluster(pods):
    pass


def is_new_pod():
    return os.path.exists(EXIST_FLAG_FILE)


def write_file(content, output_file):
    """
    Write content to output_file's path , making sure any parent directories exist.
    :param content: type-str
    :param output_file: type-str (full path of the file)
    :return: null
    """
    output_dir = os.path.dirname(output_file)
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
    with open(output_file, 'wb') as f:
        f.write(content)


def get_cluster_endpoint_info():
    res = api("/api/v1/namespaces/{namespace}/endpoints/{name}".format(
        namespace=CLUSTER_NAMESPACE, name=CLUSTER_SERVICE_NAME))
    ok = available(res,"addresses")
    bad = available(res,"notReadyAddresses")
    return {"ok":ok,"bad":bad}


def fix_cluster_config_file(info):
    pass


def available(o, k):
    if o[k]:
        return o[k]
    else:
        return {}


def cluster_launcher():
    if is_new_pod():
        result = os.system("redis-server /home/redis/data/redis.conf")
        if result == 0:
            write_file("1", EXIST_FLAG_FILE)
        else:
            error("Something wrong happened!please check your redis config file.")
            exit(1)
    else:
        info = get_cluster_endpoint_info()
        fix_cluster_config_file(info)
        result = os.system("redis-server /home/redis/data/redis.conf")
        if not result == 0:
            error("Something wrong happened!please check your redis config file.")
            exit(1)


def ctrl_launcher():
    if cluster_exists():
        ready_pods = get_redis_cluster_ready_pods()
        redis_cluster_nodes = get_redis_cluster_nodes()
        if ready_pods > redis_cluster_nodes:
            pass
        elif ready_pods == redis_cluster_nodes:
            check_redis_cluster()
        else:
            warn("[WARN] Redis Cluster lost some nodes!")
    else:
        info("Loading cluster statefulset's info...")
        while not cluster_statefulset_exists():
            time.sleep(5)
            print("tick tock........")
        pods = get_redis_cluster_ready_pods(return_int=False)
        create_redis_cluster(pods)


def single_launcher():
    pass


if __name__ == "__main__":
    if str(os.getenv("MODE")).lower() == "clusternode":
        cluster_launcher()
    elif str(os.getenv("MODE")).lower() == "clusterctrl":
        ctrl_launcher()
    elif str(os.getenv("MODE")).lower() == "singlenode":
        single_launcher()
    else:
        error(
            "Environment of Redis Mode error! Mode must be \"ClusterNode\",\"ClusterCtrl\" ")
