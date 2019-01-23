# -*- coding:UTF-8 -*-
import jinja2
import os
import io
import json
import subprocess
import time
import sys

__author__ = "caiqy"

current_path = os.path.dirname(os.path.abspath(__file__))
template_path = os.path.join(current_path, "template")
yaml_path = os.path.join(current_path, "yaml")


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


def build_redis_yaml(config):
    """
    Build yaml files for redis component, making sure template files exist.
    :param config: type-dict
    :return: null
    """
    file_list = os.listdir(template_path)
    for i in range(0, len(file_list)):
        if os.path.isfile(os.path.join(template_path, file_list[i])):
            with io.open(os.path.join(template_path, file_list[i]), 'r', encoding='utf-8') as f:
                template = jinja2.Template(f.read())
                write_file(template.render(config),
                           os.path.join(yaml_path, file_list[i]))


def json_load(json_file):
    """
    Load json from file.
    :param json_file: json file path
    :return: dict
    """
    with open(os.path.join(current_path, json_file)) as jsonfile:
        return json.load(jsonfile)


def json_extend(c, d):
    """
    Merge the contents of two dicts together into the first dict.
    :param c: dict
    :param d: dict
    :return: dict
    """
    for k, v in d.iteritems():
        if json_value_available(c, k):
            c.setdefault(k, c[k])
        else:
            c.setdefault(k, d[k])
    return c


def json_value_available(o, k):
    """
    Check out o[k].
    :param o: object
    :param k: key
    :return: boolean
    """
    try:
        o[k]
        return True
    except KeyError:
        return False


def exists_resource(resource, pattern, namespace="default", bool_result=True):
    """
    kubectl get {resource} -n {namespace} | grep "{pattern}"
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
        cmd = "/root/local/bin/kubectl get " + \
              str(resource) + " -n " + namespace + " | grep \"" + \
            str(pattern) + "\" | wc -l 2>/dev/null"
        run = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE)
        quantum = int(run.stdout.read().replace('\n', ''))
        if bool_result:
            return quantum > 0
        else:
            return quantum
    except Exception:
        # print("[ERROR] {}".format(e.message))
        if bool_result:
            return False
        else:
            return 0


def check_config(config):
    try:
        # redis_statefulset_replicas >= (redis_cluster_replicas+1)*3
        if int(config["redis_statefulset_replicas"]) < (int(config["redis_cluster_replicas"])+1)*3 or int(config["redis_statefulset_replicas"]) < 0 or int(config["redis_cluster_replicas"]) < 0:
            print("make sure redis_statefulset_replicas >= (redis_cluster_replicas+1)*3 > 0")
            return False

        # 0<= log_level <= 3
        if int(config["log_level"]) < 0 or int(config["log_level"]) > 3 :
            print("make sure 0 <= log_level <= 3")
            return False

        # hostnetowrk
        if str(config["hostnetwork"]).lower() == "true":
            if exists_resource("node","Ready",bool_result=False) < int(config["redis_statefulset_replicas"]) :
                print("in hostnetowrk mode,make sure nodes >= redis_statefulset_replicas")
                return False

        # redis_data_size > 0 
        if int(config["redis_data_size"]) <= 0 and config["persistent_flag"]:
            print("make sure redis_data_size > 0")
            return False
                
        return True
    except Exception:
        print("Wrong arguments!")
        return False


def install_redis():
    """
    Install redis component in kubernetes.
    :return: boolean ,the installation result
    """
    try:
        # if any redis resources exist
        if not check_redis(return_code=True) == 5:
            print("Redis cluster already exists!")
            return False

        config = json_load('redis.json')

        if not check_config(config):
            return False

        build_redis_yaml(config)

        # install redis component
        result = os.system(
            "/root/local/bin/kubectl create -f #path#/yaml/"
            .replace("#path#", current_path)
        )

        if result != 0:
            return False

        # check redis status
        while check_redis(return_code=True) != 0:
            print("Redis is not Ready!")
            time.sleep(5)

        return True
    except Exception:
        print("redis config error!")
        return False


def uninstall_redis():
    """
    Uninstall redis component in kubernetes.
    :return: boolean ,the uninstallation result
    """
    config = json_load("redis.json")
    result = os.system(
        "/root/local/bin/kubectl get statefulset -l app=redis | grep -v NAME | awk '{print $1}' | xargs /root/local/bin/kubectl delete statefulset ;"
        "/root/local/bin/kubectl get deployment -l app=redis | grep -v NAME | awk '{print $1}' | xargs /root/local/bin/kubectl delete deployment ;"
        "/root/local/bin/kubectl get service -l app=redis | grep -v NAME | awk '{print $1}' | xargs /root/local/bin/kubectl delete service ;"
        "/root/local/bin/kubectl get serviceaccount -l app=redis | grep -v NAME | awk '{print $1}' | xargs /root/local/bin/kubectl delete serviceaccount ;"
        "/root/local/bin/kubectl get clusterrole -l app=redis | grep -v NAME | awk '{print $1}' | xargs /root/local/bin/kubectl delete clusterrole ;"
        "/root/local/bin/kubectl get clusterrolebinding -l app=redis | grep -v NAME | awk '{print $1}' | xargs /root/local/bin/kubectl delete clusterrolebinding ;"
    )

    if config["persistent_flag"]:
        result = os.system(
            "/root/local/bin/kubectl get pvc -l app=redis | grep -v NAME | awk '{print $1}' | xargs /root/local/bin/kubectl delete pvc")
        if result == 0:
            while True:
                if exists_resource("endpoints", "redisdata"):
                    time.sleep(2)
                else:
                    break
        else:
            return False
    return True


def scale_redis(new_replicas):
    """
    Scale redis statefulset's replicas
        :new_replicas: int , the new replcias of redis
    :return: boolean ,the scale result
    """
    try:
        # turn into integer
        new_replicas = int(new_replicas)

        # check out redis
        if not check_redis(return_code=False):
            print("making sure that your redis cluster is healthy.")
            return False

        # check kubernetes healthy
        nodes = exists_resource("node", "Ready", bool_result=False)
        if nodes == 0:
            print("Could not find kubernetes nodes.")
            return False

        # execute scale
        config = json_load("redis.json")
        old_replicas = int(config["redis_statefulset_replicas"])

        if old_replicas > new_replicas:
            print("could not delete pods of redis!")
            return False

        if old_replicas == new_replicas:
            print("nothing to do.")
            return False

        if old_replicas < new_replicas:
            result = os.system(
                "/root/local/bin/kubectl scale statefulset sts-redis-cluster --replicas={}".format(new_replicas))
            if result == 0:
                config["redis_statefulset_replicas"] = str(new_replicas)
                write_file(json.dumps(config, indent=1),
                           os.path.join(current_path, "redis.json"))
                return True
            else:
                return False
    except Exception:
        return False


def check_redis(return_code=False):
    """
+------+---------------------------------------+
| Code |                Explain                |
+------+---------------------------------------+
|  0   |                healthy                |
|  1   | Nodes don't agree about configuration |
|  2   |     Some slots in migrating state     |
|  3   |     Some slots in importing state     |
|  4   |   Not all slots are covered by nodes  |
|  5   |       Can not find redis cluster      |
+------+---------------------------------------+
    """
    try:
        run = subprocess.Popen("/root/local/bin/kubectl exec -it $(/root/local/bin/kubectl get po | grep redis-ctrl-center | awk '{print $1}')  /bin/sh /redis-plus.sh health 2>/dev/null",
                               shell=True,
                               stdout=subprocess.PIPE)
        result = run.stdout.read()
        print(result)
        
        if "Nodes don't agree about configuration" in result:
            return 1
        elif "Some slots in migrating state" in result:
            return 2
        elif "Some slots in importing state" in result:
            return 3
        elif "Not all slots are covered by nodes" in result:
            return 4
        elif "Could not connect" in result:
            return 5
        else:
            return 0
    except Exception:
        if return_code:
            return 5
        else:
            return False


output = []
output.append("|  0   |                healthy                |")
output.append("|  1   | Nodes don't agree about configuration |")
output.append("|  2   |     Some slots in migrating state     |")
output.append("|  3   |     Some slots in importing state     |")
output.append("|  4   |   Not all slots are covered by nodes  |")
output.append("|  5   |    Could not connect to redis cluster   |")


def print_chosen(line):
    out = "\033[1;31;40m"+str(line)+"   < Current State \033[0m"
    print(out)


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == "install":
        if install_redis():
            print("redis installed successfully!")
        else:
            print("redis installed failed!")
    elif len(sys.argv) == 2 and sys.argv[1] == "uninstall":
        if uninstall_redis():
            print("redis uninstalled successfully!")
        else:
            print("redis uninstalled failed!")
    elif len(sys.argv) == 2 and sys.argv[1] == "check":
        code = check_redis(return_code=True)
        print("+------+---------------------------------------+")
        print("| Code |                Explain                |")
        print("+------+---------------------------------------+")
        for i in range(0, 6):
            if code == i:
                print_chosen(output[i])
            else:
                print(output[i])
        print("+------+---------------------------------------+")

    elif len(sys.argv) == 3 and sys.argv[1] == "scale":
        try:
            if scale_redis(int(sys.argv[2])):
                print("redis scaled successfully!")
            else:
                print("redis scaled failed!")
        except Exception:
            print("redis scaled failed!")
    else:
        print(
            "install (install redis cluster) \n"
            "uninstall (remove redis cluster) \n"
            "check (inspect redis cluster) \n"
            "scale [replicas] (expand redis cluster)"
        )
