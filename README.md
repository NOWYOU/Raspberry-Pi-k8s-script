# Raspberry-Pi-k8s-script
This document refers to open source document [opsnull/follow-me-install-kubernetes-cluster](https://github.com/opsnull/follow-me-install-kubernetes-cluster), which aims to use shell scripts on the Raspberry Pi, semi-automatically Build a highly available cluster.

### Experimental equipment
Raspberry Pi 4 model B

### Operating system environment
Ubuntu Server 20.04.2 LTS

### Cluster node address planning:
- k8s-01: 192.168.11.30
- k8s-02: 192.168.11.31
- k8s-03: 192.168.11.32

Topology 

![image](https://user-images.githubusercontent.com/43359644/128690433-228ed7dd-d04b-4c4f-b429-7004102a06b1.png)

### Version 1 usage 
The three devices are both Master nodes and Worker nodes. The following operations are performed on each node.
#### Set hostname

``` bash
hostnamectl set-hostname k8s-01 # The host names of different nodes are different, take k8s-01 as an example
```

If DNS does not support host name resolution, you also need to add the correspondence between host name and IP in the `/etc/hosts` file of each machine:

``` bash
cat >> /etc/hosts <<EOF
192.168.11.30 k8s-01
192.168.11.31 k8s-02
192.168.11.32 k8s-03
EOF
```

Log out and log in to the root account again, and you can see that the host name takes effect.

#### Add node trust relationship

This operation only needs to be performed on the k8s01 node, and the root account can be set to log in **all nodes** without a password:

``` bash
ssh-keygen -t rsa
ssh-copy-id root@k8s-01
ssh-copy-id root@k8s-02
ssh-copy-id root@k8s-03
```

After performing the above operations, please perform the following operations.

Step 1: Execute the script [1.system_environment.sh](https://github.com/NOWYOU/Raspberry-Pi-k8s-script/blob/bash/1.system_environment.sh) on all nodes 

Step 2: Execute the following 4 scripts on the k8s-01 node
- [2.basic_setting.sh](https://github.com/NOWYOU/Raspberry-Pi-k8s-script/blob/bash/2.basic_setting.sh)
- [3.master.sh](https://github.com/NOWYOU/Raspberry-Pi-k8s-script/blob/bash/3.master.sh)
- [4.worker.sh](https://github.com/NOWYOU/Raspberry-Pi-k8s-script/blob/bash/4.worker.sh)
- [5.calico.sh](https://github.com/NOWYOU/Raspberry-Pi-k8s-script/blob/bash/5.calico.sh)

**Note: Before executing these scripts, you need to change the cluster node IP in the script to the actual node IP**
