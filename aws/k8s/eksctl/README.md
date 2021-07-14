# EKS cluster and node pool creation using eksctl
AWS provides EKS service which offers kubernetes cluster creation and management to cloud users.
This file provides steps to deploy AWS EKS cluster and its node pools, i.e. kubernetes worker nodes represented by EC2 instances.

**NOTE:** Node pool is also referred as node group in AWS conventional terms.

## Installation Prerequisites
* python-pip
```sh
sudo yum install epel-release
sudo yum install python-pip
```
* awscli, version >= 2.1.30
```sh
pip install awscli --upgrade --user
```
**NOTE** It is recommended to use awscli version 2 which can be installed from https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
* eksctl, version >= 0.40.0
```sh
curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version
```
* kubectl
```sh
sudo bash -c "cat >/etc/yum.repos.d/kubernetes.repo" << 'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
```
```sh
sudo yum install -y kubectl-<version>
```


## Setting up prerequisites

* **awscli**: Once you install all packages mentioned in above list, use ```aws configure``` command to set AWS secret and access key as well as region for current IAM user who is responsible EKS cluster deployment and management.

## Scripts Structure Used
```sh
.
├── aws_cli_common.sh
├── common.sh
├── conf.d
│   ├── iam_serviceaccounts.yaml
│   ├── k8s_cluster.conf
│   ├── nodepool_anzograph.yaml
│   ├── nodepool_common.yaml
│   ├── nodepool_dynamic.yaml
│   ├── nodepool_operator.yaml
│   └── nodepool.yaml
├── create_k8s.sh
├── create_nodepools.sh
├── delete_k8s.sh
├── delete_nodepools.sh
├── README.md
├── reference
│   ├── ca_autodiscover-patch-file.yaml
│   ├── ca_autodiscover.yaml
│   ├── cluster-autoscaler-policy.json
│   ├── nodepool_anzograph_tuner.yaml
│   ├── nodepool_dynamic_tuner.yaml
│   ├── versions
│   └── warm_ip_target.yaml
└── sample_use_cases
    ├── 1_existing_vpc_private_cluster
    │   └── k8s_cluster.conf
    ├── 2_new_vpc_public_cluster
    │   └── k8s_cluster.conf
    └── 3_nat_ha_private_cluster
        └── k8s_cluster.conf
```


## Steps to Deploy EKS Cluster
```sh
cd <dir-containing-above-tree>
./create_k8s.sh -c k8s_cluster.conf -d ./conf.d/
./create_nodepools.sh -c nodepool.yaml -d ./conf.d/
where,
    -c (--config) can be used to provide config file name.
    -d (--directory) can be used to provide the directory/environment where config file is present.
                     Default it takes conf.d/ directory if not given.
```
* create_k8s.sh: This takes care of EKS cluster creation. There are 2 deployment modes.
    * In Existing VPC: You need to provide a valid VPC_ID from cluster configuration file.
    * In a dedicated, new VPC: Do not provide VPC ID, keep the field blank.

* create_nodepools.sh: This script is responsible for creating autoscaling group of EC2 instances which will serve as workers/nodes for EKS cluster.


## Steps to Delete EKS Cluster
```sh
cd <dir-containing-above-tree>
./delete_nodepools.sh -c nodepool.yaml -d ./conf.d/
./delete_k8s.sh -c k8s_cluster.conf -d ./conf.d/
where,
    -c (--config) can be used to provide config file name.
    -d (--directory) can be used to provide the directory/environment where config file is present.
                     Default it takes conf.d/ directory if not given.
```
* delete_nodepools.sh: This script is responsible for deleting auto scaling group of EC2 instances which serves as workers/nodes for EKS cluster. It also deletes ssh key pairs if they are specifically created for current node pool.

* delete_k8s.sh: This takes care of EKS cluster deletion along with subnets, route table and NAT gateway.

**NOTE** delete_k8s.sh script cleans up only resources those are created as a part of above creation flow. e.g. If deployment is done within an existing VPC, it will clean up only subnets/route tables/NAT gateway which are newly created in that VPC by creation scripts. It will not delete entire VPC and any pre-existing configuration.


## Configuration Parameters Used for Deployment
The creation and deletion flow explained above is dependent on certain configuration parameters.
These parameters are supplied by files located in ```conf.d/``` directory. e.g. k8s_cluster.conf is responsible for cluster-wide configurations such as cluster name, region, etc., while nodepool_*.yaml files are responsible for one or more node pool deployments.
### Parameters for k8s_cluster.conf

| Parameter | Description | Default |
|-----------|-------------|---------|
| `REGION` | AWS region of EKS deployment | us-east-1 |
| `AvailabilityZones` | Space separated string with names of Availability Zones |  |
| `Tags` | Comma separated list of tags to add to EKS cluster | |
| `VPC_ID` | ID of existing VPC to deploy EKS cluster in | "" |
| `VPC_CIDR` | CIDR to be used by VPC | |
| `NAT_SUBNET_CIDRS` | Subnet CIDRs for public subnets used by NAT gateways | |
| `PUBLIC_SUBNET_CIDRS` | Space separated CIDRs for public subnets | |
| `PRIVATE_SUBNET_CIDRS` | Space separated CIDRs for private subnets | |
| `VPC_NAT_MODE` | NAT mode for VPC, valid options: HighlyAvailable, Single, Disable | "Single" |
| `WARM_IP_TARGET` | Number of IPs to be held by a node | 8 |
| `PUBLIC_ACCESS_CIDRS` | CIDRs which are allowed to access K8s API server over public endpoint access | |
| `ALLOW_NETWORK_CIDRS` | Comma separated list of CIDRs to allow access to k8s API server over port 443 |  |
| `CLUSTER_NAME` | Name for EKS cluster | |
| `CLUSTER_VERSION` | Version of EKS cluster | "1.19" |
| `ENABLE_PRIVATE_ACCESS` | Enable private(VPC-only) access for EKS cluster endpoint | true |
| `ENABLE_PUBLIC_ACCESS` | Enable public access for EKS cluster endpoint | false |
| `CNI_VERSION` | Version of CNI plugin for cluster | 1.7.5 |
| `ENABLE_LOGGING_TYPES` | Comma separated list of logging types to be enabled for cluster | "api,audit" |
| `DISABLE_LOGGING_TYPES` | Comma separated list of logging types to be disabled for cluster | "controller" |
| `WAIT_DURATION` | Wait timeout in seconds for AWS resources creation | 1200 |
| `WAIT_INTERVAL` | Sleep time in seconds for polling resource state information | 10 |
| `STACK_CREATION_TIMEOUT` | Time to wait for EKS cluster in certain state(e.g. Updated) | 30m |
| `EKSCTL_VERSION` | Expected version of eksctl on workstation | "0.40.0" |
| `AWS_CLI_VERSION` | Expected version of aws-cli on workstation | "2.1.30" |

### Parameters for nodepool_*.yaml
Each nodepool_*.yaml file describes properties to deploy nodepool, i.e. autoscaling group of EKS cluster nodes/EC2 instances.

Schema is defined at:
```https://eksctl.io/usage/schema/```

Few important parameters are explained below:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `apiVersion` | eksctl API Version to deploy eks objects | `eksctl.io/v1alpha5` |
| `kind` | Type/Kind of object to be created | `ClusterConfig` |
| `metadata.name` | Name of EKS cluster | |
| `metadata.region` | Region in which EKS cluster is deployed | |
| `nodeGroups.*.name` | Name of nodepools/worker node sets to be deployed | |
| `nodeGroups.*.labels` | Labels to attach to k8s nodes in nodepool, viewed using `kubectl get node <node-name> -o yaml` | |
| `nodeGroups.*.instanceType` | Instance type for deploying nodes, i.e., Hardware configuration for EC2 | |
| `nodeGroups.*.desiredCapacity` | The number of Amazon EC2 instances that the Auto Scaling group attempts to maintain. | |
| `nodeGroups.*.availabilityZones.*` | List of Availability Zones to deploy Auto Scaling group instances | |
| `nodeGroups.*.minSize` | The minimum size/number of instances of the Auto scaling group | |
| `nodeGroups.*.maxSize` | The maxium size/number of instances of the Auto scaling group | |
| `nodeGroups.*.volumeSize` | For Amazon EBS volumes, the storage size | |
| `nodeGroups.*.maxPodsPerNode` | Number of pods to be hosted on each EC2 instance, i.e. K8S node | `8` |
| `nodeGroups.*.iam.withAddonPolicies.autoScaler` | Whether this nodepool should be part of cluster autoscaler | `true`    |
| `nodeGroups.*.iam.withAddonPolicies.imageBuilder` | Whether to allow full ECR(Elastic Container Registry to hold docker images) access from this nodepool | `true` |
| `nodeGroups.*.volumeType` | For Amazon EBS volumes, the volume type | `gp2` |
| `nodeGroups.*.privateNetworking` | Whether to isolate nodepool from public internet | `true` |
| `nodeGroups.*.securityGroups.withShared` | Create shared security group for this nodepool to allow communication with other nodepools, if any | `true` |
| `nodeGroups.*.securityGroups.withLocal` | Create separate security group for this nodepool | `true` |
| `nodeGroups.*.ssh.allow` | Whether to allow ssh for nodepool EC2 instances | `true` |
| `nodeGroups.*.ssh.publicKeyName` | Existing Key Pair name to use for SSH connection | |
| `nodeGroups.*.ssh.publicKey` | Specify public inline as a string | |
| `nodeGroups.*.taints` | Setting on EC2/K8S node to repel a pod from being scheduled | |
| `nodeGroups.*.tags` | Tags to attach to each EC2/K8S instance | |
| `nodeGroups.*.preBootstrapCommands` | List of commands to be executed on EC2 instance during its deployment | |


## Sample use cases
Sample use cases for AWS EKS deployment are present under directory sample_use_cases, below are the sub-directories where sample conf files are present.

| Use case | Description |
|-----------|-------------|
| `1_existing_vpc_private_cluster` | Explains a private cluster creation in an existing VPC. Here, EKS cluster will be deployed in the VPC with existing/new NAT gateway. Control plane security group is configured using CIDRs mentioned in AllOW_NETWORK_CIDRS parameter. Communication through VPN will be opened by ENABLE_ROUTE_PROPAGATION=True, it allows a virtual private gateway to automatically propagate routes to the route tables. |
| `2_new_vpc_public_cluster` | Creates a public EKS cluster along with new VPC to deploy cluster resources in. VPC_CIDR is specified in configuration file to create VPC with CIDR of your own choice. NAT will be created/used for outbound connectivity of cluster nodes. Public and private subnets will be created based on CIDRs mentioned in PUBLIC_SUBNET_CIDRS and PRIVATE_SUBNET_CIDRS parameters respectively. For restricting access to specific IP ranges, IPs to be allowed are mentioned in PUCLIC_ACCESS_CIDRS. |
| `3_nat_ha_private_cluster` | Creates a private cluster in the existing VPC with HighlyAvailable NAT gateways, i.e., NAT gateways are created in every Availability Zone(AZ) used in cluster creation. |


## References:
```https://docs.cambridgesemantics.com/```

```https://docs.google.com/document/d/1ydLaQ3N_dub4B1Y6eLtT-WjaulMzWlOwYY58Qd9_wPU/edit?usp=sharing```

```https://docs.cambridgesemantics.com/anzo/userdoc/amazon-eks.htm```
