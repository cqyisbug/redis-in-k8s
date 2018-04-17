#!/bin/sh

services=(etcd kube-apiserver kube-scheduler kube-controller-manager kubelet kube-proxy flanneld docker)

echo "Stoping Services..."

for svc in $services ; do 
	systemctl stop $svc
	systemctl disable $svc
done

echo "Removing Softwares..."

rpm -qa | grep -E "etcd|docker|flannel|kubernetes" | xargs rpm -e

echo "Removing docker0 Bridge ..."
yum install -y bridge-utils
ip link set dev docker0 down
brctl delbr docker0
rpm -qa | grep bridge-utils | xargs rpm -e

echo "Removing files..."
find / -name "*.rpmsave" | xargs rm -rf 

rm -rf /run/flannel
rm -rf /run/docker
rm -rf /var/lib/docker
rm -rf /data/docker
rm -rf /etc/docker
rm -rf /var/lib/etcd
rm -rf /etc/etcd
rm -rf /run/kubernetes
rm -rf /etc/kubernetes