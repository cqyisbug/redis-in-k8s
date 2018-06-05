# env /usr/bin/python
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
EXIST_FLAG_FILE = "/existflag"
NODES_CONFIG_FILE = "{data_dic}nodes.conf".format(data_dic=DATA_DIC)
IP_PODNAME_RELATION_JSON = "{data_dic}relation.json".format(data_dic=DATA_DIC)
CLUSTER_STATEFULSET_NAME = "redis-cluster-node"
CLUSTER_SERVICE_NAME = "redis-cluster-svc"
CLUSTER_NAMESPACE = "default"
REDIS_CLUSTER_REPLICAS = int(os.getenv("redis_cluster_replicas".upper()))

# REDIS_STATEFULSET_REPLICAS = int(os.getenv("redis_statefulset_replicas".upper()))
API_SERVER_ADDR = os.getenv("api_server_addr".upper())
WAIT_TIMEOUT = int(os.getenv("wait_timeout".upper()))
REBALANCE_DELAY = int(os.getenv("rebalance_delay".upper()))
TOLERANCE = int(os.getenv("tolerance".upper()))
LOG_LEVEL = os.getenv("log_level".upper())
REDIS_PORT = os.getenv("redis_port".upper())
MY_POD_IP = os.getenv("my_pod_ip".upper())
if not str(LOG_LEVEL):
    LOG_LEVEL = 0


def info(out):
    if str(LOG_LEVEL).upper() == "INFO" or str(LOG_LEVEL) == "0":
        print(str(time.strftime("%Y-%m-%d %H:%M:%S - ", time.localtime())) +
              "\033[34m" + str(out) + "\033[0m")


def warn(out):
    if str(LOG_LEVEL).upper() == "WARN" or str(LOG_LEVEL) == "1" or str(LOG_LEVEL).upper() == "INFO" or str(
            LOG_LEVEL) == "0":
        print(str(time.strftime("%Y-%m-%d %H:%M:%S - ", time.localtime())) +
              "\033[33m" + str(out) + "\033[0m")


def error(out):
    print(str(time.strftime("%Y-%m-%d %H:%M:%S - ", time.localtime())) +
          "\033[31m" + str(out) + "\033[0m")


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
        res = json.loads(http_get(API_SERVER_ADDR + str(suffix)))
        return res
    except Exception:
        return {}


def is_use_hostnetwork():
    try:
        return int(api("/apis/apps/v1/namespaces/{namespace}/statefulsets/{sts}".format(namespace=CLUSTER_NAMESPACE,
                                                                                        sts=CLUSTER_STATEFULSET_NAME))
                   ["items"]["spec"]["template"]["spec"]["hostNetwork"])
    except Exception:
        return False


def get_redis_cluster_statefulset_replicas():
    try:
        return int(api("/apis/apps/v1/namespaces/{namespace}/statefulsets/{sts}".
                       format(namespace=CLUSTER_NAMESPACE, sts=CLUSTER_STATEFULSET_NAME))["spec"]["replicas"])
    except Exception:
        return 0


def get_k8s_node_replicas():
    try:
        return len(api("/api/v1/nodes")["items"])
    except Exception:
        return 0


REDIS_STATEFULSET_REPLICAS = get_redis_cluster_statefulset_replicas()
HOSTNETWORK = is_use_hostnetwork()
K8S_NODE_REPLICAS = get_k8s_node_replicas()


def cluster_exists():
    if check_redis_cluster() != 5 and check_redis_cluster() != 6:
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
        if len(res["items"]) > 0:
            for k in res["items"]:
                if k["metadata"]["name"] == CLUSTER_STATEFULSET_NAME:
                    return True
        return False
    except Exception:
        return False


def check_redis_cluster():
    cmd = "redis-trib.rb check {statefulset}-0.{service}:$REDIS_PORT".format(
        statefulset=CLUSTER_STATEFULSET_NAME, service=CLUSTER_SERVICE_NAME)
    run = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
    result = run.stdout.read()
    if result.find("[ERR") <= 0 and result.find("[WARN") <= 0:
        return 0
    elif result.find("Nodes don't agree about configuration") > 0:
        return 1
    elif result.find("in migrating state") > 0:
        return 2
    elif result.find("in importing state") > 0:
        return 3
    elif result.find("covered by nodes") > 0:
        return 4
    elif result.find("Invalid arguments") > 0:
        return 5
    else:
        return 6


def create_redis_cluster(pods):
    hosts = ""
    if len(pods) > 0:
        print(len(pods))
        for v in pods:
            # print("forget pod ...")
            # os.system("redis-cli -h {statefulset}-0.{service} -p $REDIS_PORT cluster forget {nodeid}".format(
            #           statefulset=CLUSTER_STATEFULSET_NAME,
            #           service=CLUSTER_SERVICE_NAME,
            #           nodeid=get_node_id_by_ip(v["ip"])))
            hosts += v["ip"] + ":$REDIS_PORT "
    print (hosts)
    os.system("echo yes|redis-trib.rb create --replicas $REDIS_CLUSTER_REPLICAS {hosts}".format(hosts=hosts))


def get_node_id_by_ip(ip):
    try:
        cmd = "redis-cli -h {ip} -p $REDIS_PORT  cluster nodes | grep myself ".format(
            ip=ip)
        run = subprocess.Popen(cmd+"|awk '{print $1}'", shell=True, stdout=subprocess.PIPE)
        return run.stdout.read().replace('\n', '')
    except Exception:
        return ""


def is_new_pod():
    return not os.path.isfile(EXIST_FLAG_FILE)


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
    res = api("/api/v1/namespaces/{namespace}/endpoints/{svcname}".format(
        namespace=CLUSTER_NAMESPACE, svcname=CLUSTER_SERVICE_NAME))
    ok = available(res["subsets"][0], "addresses")
    bad = available(res["subsets"][0], "notReadyAddresses")
    return {"ok": ok, "bad": bad}


def fix_cluster_config_file():
    info("Start fixing old cluster config file...")
    if os.path.exists(NODES_CONFIG_FILE):
        with io.open(NODES_CONFIG_FILE, 'r', encoding='utf-8') as config_stream:
            content = config_stream.read()
            endpoint_info = get_cluster_endpoint_info()
            with io.open(IP_PODNAME_RELATION_JSON, 'r', encoding='utf-8') as json_stream:
                old_endpoint_info = json.load(json_stream)
                if len(available(old_endpoint_info, 'ok')) > 0:
                    for k, v in available(old_endpoint_info, 'ok'):
                        content = content.replace(v["ip"], get_ip_by_podname(
                            endpoint_info, v["targetRef"]["name"]))
                if len(available(old_endpoint_info, 'bad')) > 0:
                    for k, v in available(old_endpoint_info, 'bad'):
                        content = content.replace(v["ip"], get_ip_by_podname(
                            endpoint_info, v["targetRef"]["name"]))
                write_file(content, NODES_CONFIG_FILE)


def get_ip_by_podname(obj, name):
    if len(available(obj, 'ok')) > 0:
        for v in available(obj, 'ok'):
            if v["targetRef"]["name"] == name:
                return v["ip"]
    if len(available(obj, 'bad')) > 0:
        for v in available(obj, 'bad'):
            if v["targetRef"]["name"] == name:
                return v["ip"]
    return False


def save_ip_podname_relation():
    write_file(json.dumps(get_cluster_endpoint_info()),
               IP_PODNAME_RELATION_JSON)


def available(o, k):
    try:
        return o[k]
    except Exception:
        return {}


def timeout(num, callback):
    def wrap(func):
        def handle(signum, frame):
            raise RuntimeError

        def to_do(*args, **kwargs):
            try:
                signal.signal(signal.SIGALRM, handle)
                signal.alarm(num)
                r = func(*args, **kwargs)
                signal.alarm(0)
                return r
            except RuntimeError:
                return callback()

        return to_do

    return wrap


def ready_wait_timeout_handler():
    ready_pods = get_redis_cluster_ready_pods(return_int=True)
    if (ready_pods + TOLERANCE) >= REDIS_STATEFULSET_REPLICAS and ready_pods >= (REDIS_CLUSTER_REPLICAS + 1) * 3:
        bads = REDIS_STATEFULSET_REPLICAS - len(ready_pods)
        if bads != 0:
            warn("{bads} pod(s) is(are) not ready!".format(bads=bads))
        return True
    else:
        print("Wait time out , Please check status of  Kubernetes(K8S) or check Redis config files.")
        return False


@timeout(WAIT_TIMEOUT, ready_wait_timeout_handler)
def wait_cluster_node_be_ready():
    while True:
        ready_pods = get_redis_cluster_ready_pods(return_int=True)
        if (ready_pods + TOLERANCE) >= REDIS_STATEFULSET_REPLICAS and ready_pods >= (REDIS_CLUSTER_REPLICAS + 1) * 3:
            if ready_pods == REDIS_STATEFULSET_REPLICAS:
                return True
        time.sleep(2)


def check_cluster_timeout_handler():
    if get_redis_cluster_nodes() == 1:
        return False
    else:
        return True


@timeout(WAIT_TIMEOUT, check_cluster_timeout_handler)
def checking_cluster():
    while True:
        if get_redis_cluster_nodes(return_int=True) > 1:
            return True
        time.sleep(2)


def get_master_without_slave():
    try:
        cmd = "redis-cli -h {statefulset}-0.{service} -p $REDIS_PORT  cluster nodes | grep master".format(
            statefulset=CLUSTER_STATEFULSET_NAME, service=CLUSTER_SERVICE_NAME)
        run = subprocess.Popen(cmd + "|awk '{print $1}'", shell=True, stdout=subprocess.PIPE)
        out = run.stdout.read().split("\n")

        cmd = "redis-cli -h {statefulset}-0.{service} -p $REDIS_PORT  cluster nodes | grep slave | grep {nodeid}|wc -l"
        for o in out:
            error(o)
            if len(o) != 0:
                run = subprocess.Popen(
                    cmd.format(statefulset=CLUSTER_STATEFULSET_NAME, service=CLUSTER_SERVICE_NAME, nodeid=o),
                    shell=True, stdout=subprocess.PIPE)
                if int(run.stdout.read().replace('\n', '')) == 0:
                    return o

        return ""
    except Exception:
        return ""


def cluster_launcher():
    endpoint_info = get_cluster_endpoint_info()
    if is_new_pod():
        with io.open("/home/redis/data/redis.conf", 'r', encoding='utf-8') as config_stream:
            config = config_stream.read()
            config = config.replace("{port}", REDIS_PORT)
            config = config.replace("{pod_ip}", MY_POD_IP)
            config = config.replace("{cluster_enable}", "yes")
            write_file(config, "/home/redis/data/redis.conf")
        info("Start redis server ....")
        os.system(" redis-server /home/redis/data/redis.conf  &&"
                  " sleep 1")
        print(get_ip_by_podname(endpoint_info, CLUSTER_STATEFULSET_NAME + "-0"))
        if get_redis_cluster_nodes() != 1:
            info("I found the cluster , join it~")
            result = os.system(" sleep 2 && "
                               " redis-cli -p $REDIS_PORT cluster meet {ip}  $REDIS_PORT".format(
                ip=get_ip_by_podname(endpoint_info, CLUSTER_STATEFULSET_NAME + "-0")))
            master_without_slave = get_master_without_slave()
            if len(master_without_slave) != 0:
                info("Replicate node -> {nodeid}".format(nodeid=master_without_slave))
                replicate_res = os.system(" sleep 2 && "
                                          " redis-cli -p $REDIS_PORT cluster replicate {nodeid}"
                                          .format(nodeid=master_without_slave))
                if replicate_res != 0:
                    error("Something wrong happened in cluster replicate ! Please check your redis config file.")
                    exit(1)
            if result != 0:
                error("Something wrong happened in cluster meet ! Please check your redis config file.")
                exit(1)
        write_file("1", EXIST_FLAG_FILE)
    else:
        fix_cluster_config_file()
        info("Start redis server ....")
        result = os.system(
            "redis-server /home/redis/data/redis.conf ")
        if not result == 0:
            error("Something wrong happened! Please check your redis config file.")
            exit(1)
    os.system("while [[ ! -f \"/home/redis/log/redis.log\" ]] ; do "
              "    sleep 2 ;"
              "done ; "
              "tail -F /home/redis/log/redis.log")


def ctrl_launcher():
    if not checking_cluster():
        info("Could not find the Redis Cluster,start creating it.")
        info("Loading redis cluster statefulset's info...")
        while not cluster_statefulset_exists():
            time.sleep(5)
            info("tick tock........")
        if wait_cluster_node_be_ready():
            create_redis_cluster(
                get_redis_cluster_ready_pods(return_int=False))
        else:
            error("Wait Timeout! Please check the redis cluster node pod!")
            time.sleep(10)
            exit(1)
    old_redis_cluster_nodes = 0
    while True:
        redis_cluster_nodes = get_redis_cluster_nodes()
        if old_redis_cluster_nodes == 0:
            time.sleep(5)
            old_redis_cluster_nodes = redis_cluster_nodes
        elif old_redis_cluster_nodes < redis_cluster_nodes:
            print("After {delay} seconds, Redis Controller will send rebalance command ".format(delay=REBALANCE_DELAY))
            time.sleep(REBALANCE_DELAY)
            os.system(
                "echo yes | redis-trib.rb --rebalance $(nslookup {statefulset}-0.{service}:$REDIS_PORT 2>/dev/null | grep Address ".format(
                    statefulset=CLUSTER_STATEFULSET_NAME, service=CLUSTER_SERVICE_NAME) + "| awk '{print $3}') ")
        elif old_redis_cluster_nodes == redis_cluster_nodes:
            check_redis_cluster()
            time.sleep(10)
        else:
            print("Something error happened!")


def single_launcher():
    pass


if __name__ == "__main__":
    time.sleep(5)
    if str(os.getenv("MODE")).lower() == "clusternode":
        cluster_launcher()
    elif str(os.getenv("MODE")).lower() == "clusterctrl":
        ctrl_launcher()
    elif str(os.getenv("MODE")).lower() == "singlenode":
        single_launcher()
    else:
        error(
            "Environment of Redis Mode error! Mode must be \"ClusterNode\"|\"ClusterCtrl\"|\"SingleNode\" ")
