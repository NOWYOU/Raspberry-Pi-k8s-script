#!/bin/bash
#
echo ""
echo "-------------------------パラメータスクリプトの設定-------------------------"
echo ""
cat <<EOF >  environment.sh
#!/usr/bin/bash

# 生成 EncryptionConfig 所需的加密 key
export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

# 集群各机器 IP 数组
export NODE_IPS=(192.168.11.30 192.168.11.31)

# 集群各 IP 对应的主机名数组
export NODE_NAMES=(k8s-01 k8s-02)

# etcd 集群服务地址列表
export ETCD_ENDPOINTS="https://192.168.11.30:2379,https://192.168.11.31:2379"

# etcd 集群间通信的 IP 和端口
export ETCD_NODES="k8s-01=https://192.168.11.30:2380,k8s-02=https://192.168.11.31:2380"

# kube-apiserver 的反向代理(kube-nginx)地址端口
export KUBE_APISERVER="https://127.0.0.1:8443"

# 节点间互联网络接口名称
export IFACE="eth0"

# etcd 数据目录
export ETCD_DATA_DIR="/data/k8s/etcd/data"

# etcd WAL 目录，建议是 SSD 磁盘分区，或者和 ETCD_DATA_DIR 不同的磁盘分区
export ETCD_WAL_DIR="/data/k8s/etcd/wal"

# k8s 各组件数据目录
export K8S_DIR="/data/k8s/k8s"

# docker 数据目录
export DOCKER_DIR="/data/k8s/docker"

## 以下参数一般不需要修改

# TLS Bootstrapping 使用的 Token，可以使用命令 head -c 16 /dev/urandom | od -An -t x | tr -d ' ' 生成
BOOTSTRAP_TOKEN="4dffc0bf300850341efaa0c1c3b858ab"

# 最好使用 当前未用的网段 来定义服务网段和 Pod 网段

# 服务网段，部署前路由不可达，部署后集群内路由可达(kube-proxy 保证)
SERVICE_CIDR="10.254.0.0/16"

# Pod 网段，建议 /16 段地址，部署前路由不可达，部署后集群内路由可达(flanneld 保证)
CLUSTER_CIDR="172.30.0.0/16"

# 服务端口范围 (NodePort Range)
export NODE_PORT_RANGE="30000-33167"

# kubernetes 服务 IP (一般是 SERVICE_CIDR 中第一个IP)
export CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"

# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="10.254.0.2"

# 集群 DNS 域名（末尾不带点号）
export CLUSTER_DNS_DOMAIN="cluster.local"

# 将二进制目录 /opt/k8s/bin 加到 PATH 中
export PATH=/opt/k8s/bin:$PATH
EOF

echo ""
echo "-------------------------分发集群配置参数脚本-------------------------"
echo ""
source environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp environment.sh root@${node_ip}:/opt/k8s/bin/
    ssh root@${node_ip} "chmod +x /opt/k8s/bin/*"
  done

echo ""
echo "-------------------------CAルート証明書とキーの作成-------------------------"
echo ""
mkdir -p /opt/k8s/cert && cd /opt/k8s/work

echo ""
echo "-------------------------Goのインストール-------------------------"
echo ""
wget https://golang.org/dl/go1.16.6.linux-arm64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.16.6.linux-arm64.tar.gz
export PATH=$PATH:/usr/local/go/bin
go version

echo ""
echo "-------------------------CFSSLの構築-------------------------"
echo ""
git clone git@github.com:cloudflare/cfssl.git
cd cfssl
make
cd bin
mv cfssl /opt/k8s/bin/cfssl
mv cfssljson /opt/k8s/bin/cfssljson
mv cfssl-certinfo /opt/k8s/bin/cfssl-certinfo
chmod +x /opt/k8s/bin/*
export PATH=/opt/k8s/bin:$PATH

echo ""
echo "-------------------------CAプロファイルの作成-------------------------"
echo ""
# CAファイルを生成するためのJSON設定ファイルを生成する。
cd /opt/k8s/work
cat > ca-config.json <<EOF
{
 "signing": {
   "default": {
     "expiry": "87600h"
  },
   "profiles": {
     "Kubernetes": {
       "usages": [
           "signing",
           "key encipherment",
           "server auth",
           "client auth"
      ],
       "expiry": "876000h"
    }
  }
}
}
EOF

#CA証明書署名要求(CSR)用のJSON設定ファイルを生成する。
cd /opt/k8s/work
cat > ca-csr.json <<EOF
{
 "CN": "Kubernetes-ca",
 "key": {
   "algo": "rsa",
   "size": 2048
},
 "names": [
  {
     "C": "JP",
     "ST": "Kyoto",
     "L": "Kyoto",
     "O": "k8s",
     "OU": "KCGI"
  }
],
 "ca": {
   "expiry": "876000h"
}
}
EOF

#CA鍵(ca-key.pem)と証明書(ca.pem)を生成する
cd /opt/k8s/work
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
ls ca*

#証明書ファイルを配布する。
cd /opt/k8s/work
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh root@${node_ip} "mkdir -p /etc/kubernetes/cert"
    scp ca* root@${node_ip}:/etc/kubernetes/cert
  done

echo ""
echo "-------------------------kubectlのインストールと設定-------------------------"
echo ""
#kubectlのバイナリのダウンロードと配布
cd /opt/k8s/work
wget https://dl.k8s.io/v1.18.0/kubernetes-client-linux-arm64.tar.gz
tar -xzvf kubernetes-client-linux-arm64.tar.gz

cd /opt/k8s/work
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp kubernetes/client/bin/kubectl root@${node_ip}:/opt/k8s/bin/
    ssh root@${node_ip} "chmod +x /opt/k8s/bin/*"
  done

# admin 証明書と秘密鍵の作成
 cd /opt/k8s/work
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "JP",
      "ST": "Kyoto",
      "L": "Kyoto",
      "O": "system:masters",
      "OU": "KCGI"
    }
  ]
}
EOF

cd /opt/k8s/work
cfssl gencert -ca=/opt/k8s/work/ca.pem \
  -ca-key=/opt/k8s/work/ca-key.pem \
  -config=/opt/k8s/work/ca-config.json \
  -profile=kubernetes admin-csr.json | cfssljson -bare admin
ls admin*

#kubeconfig ファイルの作成
cd /opt/k8s/work
source /opt/k8s/bin/environment.sh

# クラスターパラメーターの設定
kubectl config set-cluster kubernetes \
  --certificate-authority=/opt/k8s/work/ca.pem \
  --embed-certs=true \
  --server=https://${NODE_IPS[0]}:6443 \
  --kubeconfig=kubectl.kubeconfig

# クライアント認証パラメータの設定
kubectl config set-credentials admin \
  --client-certificate=/opt/k8s/work/admin.pem \
  --client-key=/opt/k8s/work/admin-key.pem \
  --embed-certs=true \
  --kubeconfig=kubectl.kubeconfig

# コンテクストパラメータの設定
kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=kubectl.kubeconfig

# デフォルトコンテキストの設定
kubectl config use-context kubernetes --kubeconfig=kubectl.kubeconfig

cd /opt/k8s/work
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh root@${node_ip} "mkdir -p ~/.kube"
    scp kubectl.kubeconfig root@${node_ip}:~/.kube/config
  done

echo ""
echo "部署 etcd 集群"
echo ""
#etcdのバイナリのダウンロードと配布
cd /opt/k8s/work 
wget https://github.com/etcd-io/etcd/releases/download/v3.4.15/etcd-v3.4.15-linux-arm64.tar.gz
tar -xvf etcd-v3.4.15-linux-arm64.tar.gz

cd /opt/k8s/work
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp etcd-v3.4.15-linux-arm64/etcd* root@${node_ip}:/opt/k8s/bin
    ssh root@${node_ip} "chmod +x /opt/k8s/bin/*"
  done

#etcdの証明書と秘密鍵の作成
cd /opt/k8s/work
cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "192.168.11.30",
    "192.168.11.31"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "JP",
      "ST": "Kyoto",
      "L": "Kyoto",
      "O": "k8s",
      "OU": "KCGI"
    }
  ]
}
EOF

cd /opt/k8s/work
cfssl gencert -ca=/opt/k8s/work/ca.pem \
    -ca-key=/opt/k8s/work/ca-key.pem \
    -config=/opt/k8s/work/ca-config.json \
    -profile=kubernetes etcd-csr.json | cfssljson -bare etcd

cd /opt/k8s/work
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh root@${node_ip} "mkdir -p /etc/etcd/cert"
    scp etcd*.pem root@${node_ip}:/etc/etcd/cert/
  done

#etcd用のsystemdユニットテンプレートファイルの作成
 cd /opt/k8s/work
source /opt/k8s/bin/environment.sh
cat > etcd.service.template <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Environment="ETCD_UNSUPPORTED_ARCH=arm64"
Type=notify
WorkingDirectory=${ETCD_DATA_DIR}
ExecStart=/opt/k8s/bin/etcd \\
  --data-dir=${ETCD_DATA_DIR} \\
  --wal-dir=${ETCD_WAL_DIR} \\
  --name=##NODE_NAME## \\
  --cert-file=/etc/etcd/cert/etcd.pem \\
  --key-file=/etc/etcd/cert/etcd-key.pem \\
  --trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-cert-file=/etc/etcd/cert/etcd.pem \\
  --peer-key-file=/etc/etcd/cert/etcd-key.pem \\
  --peer-trusted-ca-file=/etc/kubernetes/cert/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --listen-peer-urls=https://##NODE_IP##:2380 \\
  --initial-advertise-peer-urls=https://##NODE_IP##:2380 \\
  --listen-client-urls=https://##NODE_IP##:2379,http://127.0.0.1:2379 \\
  --advertise-client-urls=https://##NODE_IP##:2379 \\
  --initial-cluster-token=etcd-cluster-0 \\
  --initial-cluster=${ETCD_NODES} \\
  --initial-cluster-state=new \\
  --auto-compaction-mode=periodic \\
  --auto-compaction-retention=1 \\
  --max-request-bytes=33554432 \\
  --quota-backend-bytes=6442450944 \\
  --heartbeat-interval=250 \\
  --election-timeout=2000
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
  
#各ノードのetd systemdユニットファイルの作成と配布
cd /opt/k8s/work
source /opt/k8s/bin/environment.sh
for (( i=0; i < 3; i++ ))
  do
    sed -e "s/##NODE_NAME##/${NODE_NAMES[i]}/" -e "s/##NODE_IP##/${NODE_IPS[i]}/" etcd.service.template > etcd-${NODE_IPS[i]}.service 
  done

cd /opt/k8s/work
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    scp etcd-${node_ip}.service root@${node_ip}:/etc/systemd/system/etcd.service
  done

# etcd サービスの開始
cd /opt/k8s/work
source /opt/k8s/bin/environment.sh
for node_ip in ${NODE_IPS[@]}
  do
    echo ">>> ${node_ip}"
    ssh root@${node_ip} "mkdir -p ${ETCD_DATA_DIR} ${ETCD_WAL_DIR}"
    ssh root@${node_ip} "systemctl daemon-reload && systemctl enable etcd && systemctl restart etcd " &
  done






