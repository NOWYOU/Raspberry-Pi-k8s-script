#!/bin/bash
#

echo ""
echo "-------------------------PATH 変数の更新-------------------------"
echo ""
echo 'PATH=/opt/k8s/bin:$PATH' >>/root/.bashrc
source /root/.bashrc


echo ""
echo "------------------依存パッケージのインストール-------------------"
echo ""
apt-get update
apt-get upgrade
apt-get install -y chrony conntrack ipvsadm ipset jq iptables curl sysstat libseccomp-dev wget socat git

echo ""
echo "---------------------ファイアウォールの設定----------------------"
echo ""
iptables -F && iptables -X && iptables -F -t nat && iptables -X -t nat
iptables -P FORWARD ACCEPT

echo ""
echo "---------------------swap をクローズする-------------------------"
echo ""
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab 

echo ""
echo "---------------------カーネルパラメータの最適化------------------"
echo ""
cat > kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
net.ipv4.ip_forward=1
net.ipv4.neigh.default.gc_thresh1=1024
net.ipv4.neigh.default.gc_thresh1=2048
net.ipv4.neigh.default.gc_thresh1=4096
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_instances=8192
fs.inotify.max_user_watches=1048576
fs.file-max=52706963
fs.nr_open=52706963
net.ipv6.conf.all.disable_ipv6=1
net.netfilter.nf_conntrack_max=2310720
EOF
cp kubernetes.conf  /etc/sysctl.d/kubernetes.conf
modprobe br_netfilter  
sysctl -p /etc/sysctl.d/kubernetes.conf

echo ""
echo "-------------------システムタイムゾーンの設定-------------------"
echo ""
timedatectl set-timezone Asia/Tokyo
timedatectl set-local-rtc 0
systemctl restart rsyslog 

echo ""
echo "-----------------関連するディレクトリを作成する-----------------"
echo ""
mkdir -p /opt/k8s/{bin,work} /etc/{kubernetes,etcd}/cert

echo ""
echo "-------------------Dockerをインストールする---------------------"
echo ""
sudo apt-get update && sudo apt-get upgrade
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
