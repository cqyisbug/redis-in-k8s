# -*- coding:UTF-8 -*-

import os
import json
import subprocess

__root_path__ = None


class ResultInfo(object):
    def __init__(self, code=0, message=""):
        self.all = {}
        self.all.setdefault("code", code)
        self.all.setdefault("message", message)

    def tostring(self):
        return json.dumps(self.all)


def root_path():
    return __root_path__


def install(rootpath, json_format=False, **config):
    __root_path__ = rootpath
    try:
        if config['hostnetwork']:
            nodes = exists_resource("node", "Ready", bool_result=False)
            if nodes < config['replicas']:
                return ResultInfo(code=3, message="k8s从节点数不能小于replicas").tostring()

        # 生成模板文件
        generateYaml(config)
        # 启动redis组件
        result = os.system("kubectl create -f #path#/yaml/sts-redis-cc.yaml ;"
                           "kubectl create -f #path#/yaml/sts-redis-cluster.yaml ;"
                           "kubectl create -f #path#/yaml/svc-redis-cc.yaml ;"
                           "kubectl create -f #path#/yaml/svc-redis-cluster.yaml ;"
                           "kubectl create -f #path#/yaml/svc-redis-cluster-np.yaml".replace(
            "#path#",
            root_path()))
        if result == 0:
            if json_format:
                return ResultInfo(code=0, message="redis集群创建成功").tostring()
            else:
                return True
        else:
            if json_format:
                return ResultInfo(code=1, message="redis集群创建失败").tostring()
            else:
                return False
    except Exception:
        if json_format:
            return ResultInfo(code=2, message="Something worng happened.").tostring()
        else:
            return False


def data_2_file(data, filePath):
    dir = os.path.dirname(filePath)
    if not os.path.exists(dir):
        os.makedirs(dir)
    file_stream = open(filePath, "w+b")
    file_stream.write(data)
    file_stream.close()


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


def generateYaml(config):
    '''
    根据配置
    从模板文件中
    生成yaml文件
    '''

    data_2_file(
        get_sts_cc()
            .replace("%REDIS_CLUSTER_SLAVE_QUANTUM%", str(config['slaves_pre_master']))
            .replace("%API_SERVER_ADDR%", config['api_server'])
            .replace("%IMAGE%", config["image"])
            .replace("%REDIS_PORT%", str(config["port"])),
        os.path.join(root_path(), "yaml", "sts-redis-cc.yaml")
    )

    if config['storageclass'] and config['hostnetwork']:
        data_2_file(
            get_sts_cluster()
                .replace("%REPLICAS%", str(config["replicas"]))
                .replace("%IMAGE%", config["image"])
                .replace("%REDIS_PORT%", str(config["port"]))
                .replace("%API_SERVER_ADDR%", str(config["api_server"]))
                .replace("%storageclass%", config['storageclass']),
            os.path.join(root_path(), "yaml", "sts-redis-cluster.yaml")
        )

    if config['storageclass'] and not config['hostnetwork']:
        data_2_file(
            get_sts_cluster_nohost()
                .replace("%REPLICAS%", str(config["replicas"]))
                .replace("%IMAGE%", config["image"])
                .replace("%REDIS_PORT%", str(config["port"]))
                .replace("%API_SERVER_ADDR%", str(config["api_server"]))
                .replace("%storageclass%", config['storageclass']),
            os.path.join(root_path(), "yaml", "sts-redis-cluster.yaml")
        )

    if not config['storageclass'] and config['hostnetwork']:
        data_2_file(
            get_sts_cluster_nohost()
                .replace("%REPLICAS%", str(config["replicas"]))
                .replace("%IMAGE%", config["image"])
                .replace("%REDIS_PORT%", str(config["port"]))
                .replace("%API_SERVER_ADDR%", str(config["api_server"])),
            os.path.join(root_path(), "yaml", "sts-redis-cluster.yaml")
        )

    if not config['storageclass'] and not config['hostnetwork']:
        data_2_file(
            get_sts_cluster_nohost()
                .replace("%REPLICAS%", str(config["replicas"]))
                .replace("%IMAGE%", config["image"])
                .replace("%REDIS_PORT%", str(config["port"]))
                .replace("%API_SERVER_ADDR%", str(config["api_server"])),
            os.path.join(root_path(), "yaml", "sts-redis-cluster.yaml")
        )

    data_2_file(
        get_svc_cc().replace("%REDIS_PORT%", str(config["port"])),
        os.path.join(root_path(), "yaml", "svc-redis-cc.yaml")
    )

    data_2_file(
        get_svc_cluster().replace(
            "%REDIS_PORT%", str(config["port"])),
        os.path.join(root_path(), "yaml", "svc-redis-cluster.yaml")
    )

    data_2_file(
        get_svc_cluster_np().replace(
            "%REDIS_PORT%", str(config["port"])),
        os.path.join(root_path(), "yaml", "svc-redis-cluster-np.yaml")
    )


def get_svc_cluster():
    return '''apiVersion: v1
kind: Service
metadata:
  name: svc-redis-cluster
  labels:
    name: svc-redis-cluster
spec:
  ports:
  - port: 6379
    targetPort: %REDIS_PORT%
  clusterIP: None
  selector:
    name: sts-redis-cluster
    '''


def get_svc_cluster_np():
    return '''apiVersion: v1
kind: Service
metadata:
  name: svc-redis-cluster-np
  labels:
    name: svc-redis-cluster-np
spec:
  ports:
  - port: 6379
    targetPort: %REDIS_PORT%
    nodePort: 6379
  type: NodePort
  selector:
    name: sts-redis-cluster
    '''


def get_svc_cc():
    return '''apiVersion: v1
kind: Service
metadata:
  name: svc-redis-cc
  labels:
    name: svc-redis-cc
spec:
  ports:
  - port: 6379
    targetPort: %REDIS_PORT%
  clusterIP: None
  selector:
    name: sts-redis-cc
    '''


def get_sts_cluster():
    return '''apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: sts-redis-cluster
spec:
  serviceName: "svc-redis-cluster"
  replicas: %REPLICAS%
  template:
    metadata:
      labels:
        name: sts-redis-cluster
        environment: test
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      terminationGracePeriodSeconds: 10
      containers:
      - name: cntr-redis-cluster
        image: %IMAGE%
        imagePullPolicy: Always
        env:
        - name: CLUSTER
          value: "true"
        - name: REDIS_PORT
          value: "%REDIS_PORT%"
        - name: CLUSTER_SVC
          value: "svc-redis-cluster"
        - name: API_SERVER_ADDR
          value: "%API_SERVER_ADDR%"
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        ports:
        - containerPort: %REDIS_PORT%
        volumeMounts:
        - name: rediscluster
          mountPath: /data/redis
        securityContext:
          capabilities: {}
          privileged: true
  volumeClaimTemplates:
  - metadata:
      name: rediscluster
      annotations:
        volume.beta.kubernetes.io/storage-class: "%storageclass%"
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
    '''


def get_sts_cluster_nohost():
    return '''apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: sts-redis-cluster
spec:
  serviceName: "svc-redis-cluster"
  replicas: %REPLICAS%
  template:
    metadata:
      labels:
        name: sts-redis-cluster
        environment: test
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: cntr-redis-cluster
        image: %IMAGE%
        imagePullPolicy: Always
        env:
        - name: CLUSTER
          value: "true"
        - name: REDIS_PORT
          value: "%REDIS_PORT%"
        - name: CLUSTER_SVC
          value: "svc-redis-cluster"
        - name: API_SERVER_ADDR
          value: "%API_SERVER_ADDR%"
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        ports:
        - containerPort: %REDIS_PORT%
        volumeMounts:
        - name: rediscluster
          mountPath: /data/redis
        securityContext:
          capabilities: {}
          privileged: true
  volumeClaimTemplates:
  - metadata:
      name: rediscluster
      annotations:
        volume.beta.kubernetes.io/storage-class: "%storageclass%"
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
    '''


def get_sts_cluster_nostorage():
    return '''apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: sts-redis-cluster
spec:
  serviceName: "svc-redis-cluster"
  replicas: %REPLICAS%
  template:
    metadata:
      labels:
        name: sts-redis-cluster
        environment: test
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      terminationGracePeriodSeconds: 10
      containers:
      - name: cntr-redis-cluster
        image: %IMAGE%
        imagePullPolicy: Always
        env:
        - name: CLUSTER
          value: "true"
        - name: REDIS_PORT
          value: "%REDIS_PORT%"
        - name: CLUSTER_SVC
          value: "svc-redis-cluster"
        - name: API_SERVER_ADDR
          value: "%API_SERVER_ADDR%"
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        ports:
        - containerPort: %REDIS_PORT%
    '''


def get_sts_cluster_nohostandstorage():
    return '''apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: sts-redis-cluster
spec:
  serviceName: "svc-redis-cluster"
  replicas: %REPLICAS%
  template:
    metadata:
      labels:
        name: sts-redis-cluster
        environment: test
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: cntr-redis-cluster
        image: %IMAGE%
        imagePullPolicy: Always
        env:
        - name: CLUSTER
          value: "true"
        - name: REDIS_PORT
          value: "%REDIS_PORT%"
        - name: CLUSTER_SVC
          value: "svc-redis-cluster"
        - name: API_SERVER_ADDR
          value: "%API_SERVER_ADDR%"
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        ports:
        - containerPort: %REDIS_PORT%
    '''


def get_sts_cc():
    return '''apiVersion: apps/v1beta1
kind: StatefulSet
metadata:
  name: sts-redis-cc
spec:
  serviceName: "svc-redis-cc"
  replicas: 1
  template:
    metadata:
      labels:
        name: sts-redis-cc
        environment: test
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: cntr-redis-cc
        image: %IMAGE%
        imagePullPolicy: Always
        env:
        - name: CLUSTER_CTRL
          value: "true"
        - name: CLUSTER_SVC
          value: "svc-redis-cluster"
        - name: REDIS_CLUSTER_SLAVE_QUANTUM
          value: "%REDIS_CLUSTER_SLAVE_QUANTUM%"
        - name: API_SERVER_ADDR
          value: "%API_SERVER_ADDR%"
        - name: REDIS_PORT
          value: "%REDIS_PORT%"
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP
        ports:
        - containerPort: %REDIS_PORT%
    '''
