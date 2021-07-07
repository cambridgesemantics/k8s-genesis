# GKE cluster and node pool creation using gcloud commands
Google cloud(GCP) provides GKE service which offers kubernetes cluster creation and management to cloud users.
This file provides steps to deploy GKE cluster and its node pools, i.e. kubernetes worker nodes represented by google compute instances.

## Installation Prerequisites
* google cloud-sdk and kubectl
```sh
sudo tee -a /etc/yum.repos.d/google-cloud-sdk.repo << EOM
[google-cloud-sdk]
name=Google Cloud SDK
baseurl=https://packages.cloud.google.com/yum/repos/cloud-sdk-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
        https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
```

```sh
sudo yum install kubectl google-cloud-sdk google-cloud-sdk-app-engine-grpc google-cloud-sdk-pubsub-emulator google-cloud-sdk-app-engine-go google-cloud-sdk-cloud-build-local google-cloud-sdk-datastore-emulator google-cloud-sdk-app-engine-python google-cloud-sdk-cbt google-cloud-sdk-bigtable-emulator google-cloud-sdk-datalab google-cloud-sdk-app-engine-java
```


## Setting up prerequisites

* Once you install all packages mentioned in above list, use ```gcloud init``` command to set region and user details.
    * Set default google project ID
    ```sh
    gcloud config set project [PROJECT_ID]
    ```

    * If you are working with zonal clusters, set your default compute zone
    ```sh
    gcloud config set compute/zone [COMPUTE_ZONE]
    ```

    * If you are working with regional clusters, set your default compute region
    ```sh
    gcloud config set compute/region [COMPUTE_REGION]
    ```

    * Update gcloud to the latest version
    ```sh
    gcloud components update
    ```

## Scripts Structure Used
```sh
.
├── common.sh
├── conf.d
│   ├── k8s_cluster.conf
│   ├── nodepool_anzograph.conf
│   ├── nodepool_anzograph_tuner.yaml
│   ├── nodepool_common.conf
│   ├── nodepool.conf
│   ├── nodepool_dynamic.conf
│   ├── nodepool_dynamic_tuner.yaml
│   └── nodepool_operator.conf
├── create_k8s.sh
├── create_nodepools.sh
├── delete_k8s.sh
├── delete_nodepools.sh
├── gcloud_cli_common.sh
├── README.md
└── sample_use_cases
    ├── 1_usePrivateEndpoint_private_cluster
    │   └── k8s_cluster.conf
    ├── 2_public_cluster
    │   └── k8s_cluster.conf
    ├── 3_useAuthorizedNetworks
    │   └── k8s_cluster.conf
    └── 4_providePublicEndpointAccess
        └── k8s_cluster.conf

```

## Steps to Deploy GKE Cluster
```sh
cd <dir-containing-above-tree>
./create_k8s.sh -c k8s_cluster.conf -d ./conf.d/
./create_nodepools.sh -c nodepool.conf -d ./conf.d/
where,
    -c (--config) used to provide config file name.
    -d (--directory) can be used to provide the directory/environment where config file is present.
                     Default it takes conf.d/ directory if not given.
```
* create_k8s.sh: This takes care of GKE cluster creation.
* create_nodepools.sh: This script is responsible for creating compute instance which will serve as workers/nodes for GKE cluster.


## Steps to Delete GKE Cluster
```sh
cd <dir-containing-above-tree>
./delete_k8s.sh -c k8s_cluster.conf -d ./conf.d/
./delete_nodepools.sh -c nodepool.conf -d ./conf.d/

where,
    -c (--config) used to provide config file name.
    -d (--directory) can be used to provide the directory/environment where config file is present.
                     Default it takes conf.d/ directory if not given.
```
* delete_nodepools.sh: This script is responsible for deleting compute instance group/s which serves as workers/nodes for GKE cluster.

* delete_k8s.sh: This takes care of GKE cluster deletion.


## Configuration Parameters Used for Deployment
The creation and deletion flow explained above is dependent on certain configuration parameters.
These parameters are supplied by files located in ```conf.d/``` directory. e.g. k8s_cluster.conf is responsible for cluster-wide configurations such as cluster name, region, etc., while nodepool_*.conf files are responsible for one or more node pool deployments.
### Parameters for k8s_cluster.conf

| Parameter | Description | Default |
|-----------|-------------|---------|
| `NETWORK_BGP_ROUTING` | Mode to advertise BGP routes by cloud router, specified while creating network | regional |
| `NETWORK_SUBNET_MODE` | Specifies method to create subnets, e.g. automatically, manually | custom |
| `NETWORK_ROUTER_NAME` | Name of cloud router to create | |
| `NETWORK_ROUTER_MODE` | Route advertisement mode for cloud router | custom |
| `NETWORK_ROUTER_ASN` | BGP autonomous system number | |
| `NETWORK_ROUTER_DESC` | Description of cloud router | Cloud router for K8S NAT. |
| `NETWORK_NAT_NAME` | Name of NAT gateway to create/update | |
| `NETWORK_NAT_UDP_IDLE_TIMEOUT` | Timeout for UDP connections for NAT | 60s |
| `NETWORK_NAT_ICMP_IDLE_TIMEOUT` | Timeout for ICMP connections for NAT | 60s |
| `NETWORK_NAT_TCP_ESTABLISHED_IDLE_TIMEOUT` | Timeout for TCP established connections | 60s |
| `NETWORK_NAT_TCP_TRANSITORY_IDLE_TIMEOUT` | Timeout for TCP transitory connections | 60s |
| `NETWORK_NAT_ALLOW_SUBNET_SECONDARY_IPS` | If set to true, allows all secondary IP ranges of cluster subnetwork to use NAT. |
| `K8S_CLUSTER_NAME` | Name for GKE cluster to create | cloud-k8s-cluster |
| `K8S_CLUSTER_PODS_PER_NODE` | Number of pods to be hosted on each compute instance, i.e. K8S node | 10 |
| `K8S_CLUSTER_ADDONS` | Additional K8S components to be enabled, provide comma-separated list | HttpLoadBalancing,HorizontalPodAutoscaling |
| `GKE_MASTER_VERSION` | Kubernetes version to use to deploy master | 1.19.9-gke.1900 |
| `GKE_PRIVATE_ACCESS` | Set it to true to deploy private cluster with nodes having no external IPs | true |
| `GKE_MASTER_NODE_COUNT_PER_LOCATION` | The number of nodes to be created in each of the cluster's zones. | 1 |
| `GKE_NODE_VERSION` | Kubernetes version to use to deploy nodes | 1.19.9-gke.1900 |
| `GKE_IMAGE_TYPE` | Specifies the base OS that the nodes in the cluster will run on | COS |
| `GKE_MAINTENANCE_WINDOW` | Set a time of day when you prefer maintenance to start on this cluster | 06:00 |
| `GKE_ENABLE_PRIVATE_ENDPOINT` | Set to true to have private IP address for the master API endpoint | true |
| `GKE_MASTER_ACCESS_CIDRS` | The list of CIDR blocks (up to 50) that are allowed to connect to Kubernetes master through HTTPS | |
| `K8S_PRIVATE_CIDR` | The IP address range for the pods in this cluster in CIDR notation | |
| `K8S_SERVICES_CIDR` | Set the IP range for the services IPs | |
| `GCLOUD_NODES_CIDR` | CIDR for new subnetwork to be created to be used in K8S cluster | |
| `K8S_API_CIDR` | IPv4 CIDR range to use for the master network. This should have a netmask of size /28 and should be used in conjunction with the --enable-private-nodes flag | |
| `K8S_HOST_DISK_SIZE` | Size for node VM boot disks | |
| `K8S_HOST_DISK_TYPE` | Type of the node VM boot disk | pd-standard |
| `K8S_HOST_MIN_CPU_PLATFORM` | Specify when to schedule the nodes for the new cluster's default node pool on host with specified CPU architecture or a newer one. | "" |
| `K8S_POOL_HOSTS_MAX` | The maximum number of nodes to allocate per default initial node pool | 1000 |
| `K8S_METADATA` | Compute Engine metadata to be made available to the guest operating system running on nodes within the node pool(key=val,key=val) | "disable-legacy-endpoints=true" |
| `K8S_MIN_NODES` | Minimum number of nodes in the node pool. | 1 |
| `K8S_MAX_NODES` | Maximum number of nodes in the node pool | 3 |
| `GCLOUD_RESOURCE_LABELS` | Labels to apply to the Google Cloud resources in use by the Kubernetes Engine cluster, unrelated to Kubernetes labels | |
| `GCLOUD_VM_LABELS` | Applies the given kubernetes labels on all nodes in the new node pool | |
| `GCLOUD_VM_TAGS` | Applies the given Compute Engine tags (comma separated) on all nodes in the new node-pool | |
| `GCLOUD_VM_MACHINE_TYPE` | The type of machine to use for nodes | n1-standard-1 |
| `GCLOUD_VM_SSD_COUNT` | The number of local SSD disks to provision on each node | 0 |
| `GCLOUD_PROJECT_ID` | Google cloud project ID for deployment and management of K8S cluster | |
| `GCLOUD_NETWORK` | The Compute Engine Network that the cluster will connect to |  |
| `GCLOUD_NODES_SUBNET_SUFFIX` | Suffix to use for subnetworks in NAT | nodes |
| `GCLOUD_CLUSTER_REGION` | Region in which to deploy K8S cluster | |
| `GCLOUD_NODE_LOCATIONS` | The set of zones in which the specified node should be replicated | |
| `GCLOUD_NODE_TAINTS` | Setting on EC2/K8S node to repel a pod from being scheduled, key=val:<Schedule> | |
| `GCLOUD_NODE_SCOPE` | Permissions/Access scopes the node should have | gke-default |


### Parameters for nodepool_<type>.conf
Each nodepool_<type>.conf file describes properties to deploy nodepool, i.e. instance groups containing one or more google compute instances.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `DOMAIN` | Name of domain for hosting K8S nodepool | acme |
| `KIND` | Specifies which type of pods will be hosted on this nodepool  | |
| `GCLOUD_CLUSTER_REGION` | Region in which GKE cluster is deployed | |
| `GCLOUD_NODE_TAINTS` | Setting on K8S node to repel a pod from being scheduled | |
| `GCLOUD_PROJECT_ID` | ID of project to host GKE resources like master and nodepools | |
| `GKE_IMAGE_TYPE` | Base OS that the nodes in the node pool will run on | cos_containerd |
| `K8S_CLUSTER_NAME` | Name of GKE cluster to add nodepool to | |
| `NODE_LABELS` | Applies the given kubernetes labels on all nodes in the new node pool | |
| `MACHINE_TYPES` | Space separated list of the types of machines to use for nodes | |
| `TAGS` | Applies the given Compute Engine tags (comma separated) on all nodes in the new node-pool | |
| `METADATA` | Compute Engine metadata to be made available to the guest operating system running on nodes within the node pool(key=val,key=val) | |
| `MAX_PODS_PER_NODE` | The max number of pods per node for this node pool | 8 |
| `MAX_NODES` | Maximum number of nodes/instances to which node pool can scale(scale up) | |
| `MIN_NODES` | Minimum number of nodes/instances to which node pool can scale(scale down) | |
| `NUM_NODES` | The number of nodes in the node pool in each of the cluster's zones | |
| `DISK_SIZE` | Size for node VM boot disks | |
| `DISK_TYPE` | Type of the node VM boot disk | pd-standard |

### K8S node/pod tuning
For products like AnzoGraph, Spark and Elasticsearch, we need to do certain system settings like disabling transparent huge page, sysctl parameter value changes, etc. To achieve this, we have conf.d/nodepool_<nodepool_type>_tuner.yaml files defined.
Each file corresponds to a dedicated nodepool.
This file contains K8S resources to be deployed on GKE cluster to tune GKE nodes.
Below resources are created.
* `ServiceAccount` : Used to provide an identity to pods, when processes inside pod containers contact K8S API Server.

* `Role`: The permissions user can have at namespace level.

* `RoleBinding`: Holds list of users/groups/service accounts and a role which is being granted to them.

* `PodSecurityPolicy`: Security restrictions imposed to pods to run successfully within cluster.

* `DaemonSet`: Ensure all nodes run copy of pod.

### Sample use cases
Sample use cases for GCP GKE deployment are present under directory sample_use_cases, below are the sub-directories where sample conf files are present.

| Use case | Description |
|:-----------|:-------------|
| `1_usePrivateEndpoint_private_cluster` | This use case explains the steps to deploy the private cluster with NAT using private endpoint enabled. Private cluster gets deployed with no client access to the public endpoint (GKE_ENABLE_PRIVATE_ENDPOINT=true). Secondary IP ranges are added in NAT mapping along with primary IP when NETWORK_NAT_ALLOW_SUBNET_SECONDARY_IPS is set to true. Outbound connectivity is allowed through NAT gateway. This creates new networking resources if not present already. Below parameters are expected from the user. NETWORK_NAT_ALLOW_SUBNET_SECONDARY_IPS=true, GKE_ENABLE_PRIVATE_ENDPOINT=true, GKE_PRIVATE_ACCESS=true, GKE_MASTER_ACCESS_CIDRS="111.0.0.0/8". |
| `2_public_cluster` | This use case explains the steps to deploy the public cluster. Below parameters is expected from the user. GKE_PRIVATE_ACCESS=false. |
| `3_useAuthorizedNetworks` | This use case explains how deploy the private cluster with master authorized networks. The GKE_MASTER_ACCESS_CIDRS parameter is used to limit the access to the public endpoint. Below parameters are expected from the user. GKE_ENABLE_PRIVATE_ENDPOINT=false, GKE_PRIVATE_ACCESS=true, GKE_MASTER_ACCESS_CIDRS="110.0.0.0/8,106.10.10.1/32"  |
| `4_providePublicEndpointAccess` | This use case explains how to deploy the private cluster with public endpoint access enabled (GKE_ENABLE_PRIVATE_ENDPOINT=false). Below parameters are expected from the user. GKE_ENABLE_PRIVATE_ENDPOINT=false, GKE_PRIVATE_ACCESS=true, GKE_MASTER_ACCESS_CIDRS="" |

## References:
```https://docs.cambridgesemantics.com/```

```https://docs.google.com/document/d/1ydLaQ3N_dub4B1Y6eLtT-WjaulMzWlOwYY58Qd9_wPU/edit?usp=sharing```

```https://docs.cambridgesemantics.com/anzo/v5.1/userdoc/google-gke.htm```