#!/bin/bash
#
echo "-------------------------キャラコ・ネットワークの導入------------------------------"
sysctl -w net.ipv4.conf.all.rp_filter=1 #
cd /opt/k8s/work
curl https://docs.projectcalico.org/manifests/calico.yaml -O

sed -i 's/# - name: CALICO_IPV4POOL_CIDR/- name: CALICO_IPV4POOL_CIDR/' calico.yaml 
sed -i 's/#   value: "192.168.0.0\/16"/  value: "172.30.0.0\/16"/' calico.yaml 
sed -i 's/path: \/opt\/cni\/bin/path: \/opt\/k8s\/bin/' calico.yaml

kubectl apply -f  calico.yaml

