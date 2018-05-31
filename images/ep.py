#env /usr/bin/python
# -*- coding:UTF-8 -*-

import os
import time
import urllib
import urllib2
import json
import subprocess
import io
import signal


DATA_DIC = "home/redis/data/"
EXIST_FLAG_FILE = "{data_dic}existflag".format(data_dic=DATA_DIC)
NODES_CONFIG_FILE = "{data_dic}nodes.conf".format(data_dic=DATA_DIC)
IP_PODNAME_RELATION_JSON = "{data_dic}relation.json".format(data_dic=DATA_DIC)
CLUSTER_STATEFULSET_NAME = "sts-redis-cluster"
CLUSTER_SERVICE_NAME = "svc-redis-cluster"
CLUSTER_NAMESPACE = "default"
CLUSTER_REPLICAS = os.getenv("cluster_replicas".upper())
STATEFULSET_REPLICAS = os.getenv("statefulset_replicas".upper())
API_SERVER_ADDR = os.getenv("api_server_addr".upper())
WAIT_TIMEOUT = os.getenv("wait_timeout".upper())
REBALANCE_DELAY = os.getenv("rebalance_delay".upper())
TOLERANCE = os.getenv("tolerance".upper())
LOG_LEVEL = os.getenv("log_level".upper())
if not str(LOG_LEVEL):
    LOG_LEVEL = 0


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
        cmd = "redis-cli -h {statefulset}-0.{service} -p $REDIS_PORT  cluster nodes | wc -l".format(
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


def check_redis_cluster():
    cmd = "redis-cli --cluster check {statefulset}-0.{service}:$REDIS_PORT".format(
        statefulset=CLUSTER_STATEFULSET_NAME, service=CLUSTER_SERVICE_NAME)
    run = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
    result = run.stdout.read()
    if result.index("[ERR") <= 0 and result.index("[WARN") <= 0:
        return 0
    elif result.index("Nodes don't agree about configuration") > 0:
        return 1
    elif result.index("in migrating state") > 0:
        return 2
    elif result.index("in importing state") > 0:
        return 3
    elif result.index("covered by nodes") > 0:
        return 4
    elif result.index("Invalid arguments") > 0:
        return 5
    else:
        return 6


def create_redis_cluster(pods):
    hosts = ""
    for k, v in pods:
        hosts += v["ip"]+":$REDIS_PORT "
    os.system("redis-cli --cluster create --cluster-replicas $CLUSTER_REPLICAS")


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
    ok = available(res, "addresses")
    bad = available(res, "notReadyAddresses")
    return {"ok": ok, "bad": bad}


def fix_cluster_config_file(info):
    with io.open(NODES_CONFIG_FILE, 'r', encoding='utf-8') as config_stream:
        content = config_stream.read()
        endpoint_info = get_cluster_endpoint_info()
        with io.open(IP_PODNAME_RELATION_JSON, 'r', encoding='utf-8') as json_stream:
            old_endpoint_info = json.load(json_stream)
            for k, v in available(old_endpoint_info, 'ok'):
                content = content.replace(v["ip"], get_ip_by_podname(
                    endpoint_info, v["targetRef"]["name"]))
            for k, v in available(old_endpoint_info, 'bad'):
                content = content.replace(v["ip"], get_ip_by_podname(
                    endpoint_info, v["targetRef"]["name"]))
            write_file(content, NODES_CONFIG_FILE)


def get_ip_by_podname(obj, name):
    for k, v in available(obj, 'ok'):
        if v["targetRef"]["name"] == name:
            return v["ip"]
    for k, v in available(obj, 'bad'):
        if v["targetRef"]["name"] == name:
            return v["ip"]
    return False


def save_ip_podname_relation():
    write_file(json.dumps(get_cluster_endpoint_info()),
               IP_PODNAME_RELATION_JSON)


def available(o, k):
    if o[k]:
        return o[k]
    else:
        return {}


def set_timeout(num, callback):
    def wrap(func):
        def handle(signum, frame):
            raise RuntimeError

        def to_do(*args, **kwargs):
            try:
                signal.signal(signal.SIGALRM, handle)
                signal.alarm(num)
                # print('start alarm signal.')
                r = func(*args, **kwargs)
                # print('close alarm signal.')
                signal.alarm(0)
                return r
            except RuntimeError:
                return callback()
        return to_do
    return wrap


def wait_timeout_handler():
    print("Wait time out ,please check status of  kubernetes or check redis config files.")
    return False


@set_timeout(WAIT_TIMEOUT, wait_timeout_handler)
def wait_cluster_be_ready():
    ready_pods = get_redis_cluster_ready_pods(return_int=True)
    if (ready_pods + TOLERANCE) >= STATEFULSET_REPLICAS:
        return True
    else:
        time.sleep(2)


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
    if not cluster_exists():
        info("Loading cluster statefulset's info...")
        while not cluster_statefulset_exists():
            time.sleep(5)
            print("tick tock........")
        if wait_cluster_be_ready():
            create_redis_cluster(
                get_redis_cluster_ready_pods(return_int=False))
        else:
            exit(1)
    old_ready_pods = {}
    diff_ready_pods = {}
    old_redis_cluster_nodes = 0
    while True:
        ready_pods = get_redis_cluster_ready_pods(return_int=False)
        redis_cluster_nodes = get_redis_cluster_nodes()
        if ready_pods > redis_cluster_nodes:
            if wait_cluster_be_ready():
                pass
        elif ready_pods == redis_cluster_nodes:
            check_redis_cluster()
        else:
            warn("[WARN] Redis Cluster lost some nodes!")
            exit(1)


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
            "Environment of Redis Mode error! Mode must be \"ClusterNode\",\"ClusterCtrl\",\"SingleNode\" ")
