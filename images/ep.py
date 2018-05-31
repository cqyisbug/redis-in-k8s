#env /usr/bin/python
# -*- coding:UTF-8 -*-

import os
import time


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


def cluster_exists():
    pass


def get_redis_cluster_nodes(return_int=True):
    return 0


def get_redis_cluster_ready_pods(return_int=True):
    return 0


def cluster_statefulset_exists():
    pass


def check_redis_cluster(verbose=True):
    pass


def create_redis_cluster(pods):
    pass

def cluster_launcher():
    pass


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
