# AKS cluster and node pool creation using az cli commands
Microsoft Azure provides AKS service which offers kubernetes cluster creation and management for cloud users.
This file provides steps to deploy AKS cluster and its node pools, i.e. kubernetes worker nodes represented by Azure virtual machine scale sets.

## Installation Prerequisites
* azure-cli
```sh
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

sudo sh -c 'echo -e "[azure-cli]
name=Azure CLI
baseurl=https://packages.microsoft.com/yumrepos/azure-cli
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc" > /etc/yum.repos.d/azure-cli.repo'

sudo yum install azure-cli

```


## Setting up prerequisites

* Once you install all packages mentioned in above list, use ```az login``` command to configure AD user details to be used to deploy cluster.
If the CLI can open your default browser, it will do so and load an Azure sign-in page.
Otherwise, open a browser page at https://aka.ms/devicelogin and enter the authorization code displayed in your terminal.


## Scripts Structure Used
```sh
.
├── common.sh
├── conf.d
│   ├── exec
│   ├── k8s_cluster.conf
│   ├── nodepool_anzograph.conf
│   ├── nodepool_common.conf
│   ├── nodepool.conf
│   ├── nodepool_dynamic.conf
│   └── nodepool_operator.conf
├── create_k8s.sh
├── create_nodepools.sh
├── delete_k8s.sh
├── delete_nodepools.sh
├── exec_samples
│   ├── rbac_aad_group.yaml
│   └── rbac_aad_user.yaml
├── permissions
│   ├── aks_admin_role.json
│   └── cluster_developer_role.json
├── README.md
├── reference
│   ├── nodepool_anzograph_tuner.yaml
│   └── nodepool_dynamic_tuner.yaml
└── sample_use_cases
    ├── 10_useExistingResources
    │   └── k8s_cluster.conf
    ├── 11_useProximityPlacementGroups
    │   └── k8s_cluster.conf
    ├── 1_azureManagedIdentity_private_cluster
    │   └── k8s_cluster.conf
    ├── 2_createServicePrincipal_public_cluster
    │   └── k8s_cluster.conf
    ├── 3_useServicePrincipal
    │   └── k8s_cluster.conf
    ├── 4_userManagedAAD
    │   └── k8s_cluster.conf
    ├── 5_azureManagedAAD
    │   └── k8s_cluster.conf
    ├── 6_attachACR
    │   └── k8s_cluster.conf
    ├── 7_clusterAutoscalerSupport
    │   └── k8s_cluster.conf
    ├── 8_MonitoringEnabled
    │   └── k8s_cluster.conf
    └── 9_RBACSupport
        └── k8s_cluster.conf
```

## Steps to Deploy AKS Cluster
```sh
cd <dir-containing-above-tree>
./create_k8s.sh -c k8s_cluster.conf -d conf.d
./create_nodepools.sh -c nodepool.conf -d conf.d
where,
    -c (--config) can be used to provide config file name.
    -d (--directory) can be used to provide the directory/environment where config file is present.
                     Default it takes conf.d/ directory if not given.
```
* create_k8s.sh: This takes care of AKS cluster creation and its default node pool.
* create_nodepools.sh: This script is responsible for creating workers/nodes of AKS cluster.


## Steps to Delete AKS Cluster
```sh
cd <dir-containing-above-tree>
./delete_nodepools.sh -c nodepool.conf -d conf.d
./delete_k8s.sh -c k8s_cluster.conf -d conf.d
where,
    -c (--config) can be used to provide config file name.
    -d (--directory) can be used to provide the directory/environment where config file is present.
                     Default it takes conf.d/ directory if not given.
```
* delete_nodepools.sh: This script is responsible for deleting workers/nodes of AKS cluster.
* delete_k8s.sh: This takes care of AKS cluster deletion.


## Configuration Parameters Used for Deployment
The creation and deletion flow explained above is dependent on certain configuration parameters.
These parameters are supplied by files located in ```conf.d/``` directory by default. e.g. k8s_cluster.conf is responsible for cluster-wide configurations such as cluster name, region, etc., while nodepool_*.conf files are responsible for one or more node pool deployments.
### Parameters for k8s_cluster.conf

| Parameter | Description | Default |
|-----------|-------------|---------|
| `SP` | Name of Azure service principal to access/manage resources | |
| `SP_VALIDITY_YEARS` | Number of years for which the service principal credentials will be valid | 2 |
| `SP_ID` | Valid service principal ID, if present | |
| `SP_SECRET` | Valid service principal secret, if present | |
| `RESOURCE_GROUP` | Name of azure resource group, i.e. parent entity that holds related azure resources together | |
| `RESOURCE_GROUP_TAGS` | Space-separated tags for resource group in 'key[=value]' format | |
| `LOCATION` | Geographical location where Azure datacenter for region is located | |
| `SUBSCRIPTION_ID` | ID of existing Azure subscription | |
| `VNET_NAME` | Name of azure virtual network | |
| `VNET_CIDR` | IP address prefix used to create virtual network | |
| `VNET_TAGS` | Space-separated tags in 'key[=value]' format for virtual network | |
| `VNET_VM_PROTECTION` | Enable VM protection for all subnets in the VNet, to protect from viruses and malware | true |
| `SUBNET_NAME` | Name of subnetwork to create | |
| `SUBNET_CIDR` | IP address prefix used to create subnetwork | |
| `NODEPOOL_NAME` | Name of default nodepool to be created with this cluster | |
| `MACHINE_TYPE` | Size of Virtual Machines to create as K8S nodes | |
| `K8S_CLUSTER_NAME` | Name of AKS cluster to create | |
| `K8S_CLUSTER_NODE_COUNT` | Number of nodes in the Kubernetes node pool | |
| `K8S_NODE_ADMIN_USER` | Used to access K8S nodes over SSH | |
| `AKS_TAGS` | Space-separated tags in 'key[=value]' format | |
| `AKS_ENABLE_ADDONS` | Enable the Kubernetes addons in a comma-separated list | monitoring |
| `PRIVATE_CLUSTER` | Whether AKS cluster should be accessible from within private network/s | false |
| `LOAD_BALANCER_SKU` | Azure Load Balancer SKU selection for your cluster, basic or standard | standard |
| `VM_SET_TYPE` | Group type to deploy AKS node pool, VirtualMachineScaleSets/AvailabilitySet | VirtualMachineScaleSets |
| `NETWORK_PLUGIN` | Name of network plugin which enables basic or advanced(CNI) networking on AKS. Allowed values are: kubenet(basic) or azure(CNI) | azure |
| `NETWORK_POLICY` | Name of network policy to be applied to pods which will allow/deny the traffic to/from them. Allowed values are: azure or calico | azure |
| `DOCKER_BRIDGE_ADDRESS` | IP address and netmask for the Docker bridge, using standard CIDR notation | |
| `DNS_SERVICE_IP` | IP Address assigned to DNS service of AKS cluster | |
| `SERVICE_CIDR` | Set the IP range for the services IPs | |
| `MIN_NODES` | Minimum number of nodes in the node pool | |
| `MAX_NODES` | Maximum number of nodes in the node pool | |
| `MAX_PODS_PER_NODE` | The maximum number of pods deployable to a node in the node pool | |
| `DISK_SIZE` | Size in GB of the OS disk for each node in the node pool | |
| `ENABLE_CLUSTER_AUTOSCALER` | Whether to enable cluster autoscaler for node pool, to control scale up/down activity | true |
| `ATTACH_ACR` | Name or resource ID of Azure Container Registry to which 'acrpull' role assignment is granted from AKS cluster nodes | |
| `AAD_CLIENT_APP_ID` | ID of an Azure Active Directory client application | |
| `AAD_SERVER_APP_ID` | ID of an Azure Active Directory server application | |
| `AAD_SERVER_APP_SECRET` | The secret of an Azure Active Directory server application | |
| `AAD_TENANT_ID` | Tenant ID associated with Azure Active Directory | |
| `ENABLE_POD_SECURITY_POLICY` | Enable pod security policy for AKS cluster | |
| `ENABLE_MANAGED_IDENTITY` | Whether to use system assigned managed identity for cluster resource group management, used to create K8S resources on behalf of the user | true |
| `DISABLE_RBAC` | Whether to Disable Kubernetes Role-Based Access Control | false |
| `SSH_PUB_KEY_VALUE` | Public key path or key contents to install on node VMs for SSH access | |
| `API_SERVER_AUTHORIZED_IP_RANGES` | List of CIDRs, used to authorize and restrict access to AKS cluster by only them(not open to all) | |
| `NODEPOOL_TAGS` | Space-separated tags: key[=value] [key[=value] ...]. Use "" to clear existing tags. | |
| `LB_OUTBOUND_IP_PREFIXES` | Load balancer outbound IP prefix resource IDs. | |
| `LB_OUTBOUND_IPS` | Load balancer outbound IP resource IDs. | |
| `LB_OUTBOUND_PORTS` | Load balancer outbound allocated ports. | |
| `LB_MANAGED_OUTBOUND_IP_COUNT` | Load balancer managed outbound IP count. | |
| `DNS_NAME_PREFIX` | Prefix for hostnames that are created. If not specified, generate a hostname using the managed cluster and resource group names. | |
| `NODE_OSDISK_TYPE` | OS disk type to be used for machines in a given agent pool. Defaults to 'Managed'. May not be changed for this pool after creation. | |
| `CLUSTER_AUTOSCALER_PROFILE` | Space-separated list of key=value pairs for configuring cluster autoscaler. Pass an empty string to clear the profile. | |
| `ENABLE_AAD` | Enable managed AAD feature for cluster. | |
| `AAD_ADMIN_GROUP_OBJECT_IDS` | Comma seperated list of aad group object IDs that will be set as cluster admin. | |
| `ENABLE_NODE_PUBLIC_IP` | Enable VMSS node public IP. | |
| `NODEPOOL_LABELS` | Space-separated labels: key[=value] [key[=value] ...]. You can not change the node labels through CLI after creation. See https://aka.ms/node-labels for syntax of labels. | |
| `PPG` | The ID of a proximity placement groups. | |
| `PPG_TYPE` | The type of the proximity placement group. | |
| `UPTIME_SLA` | Enable a paid managed cluster service with a financially backed SLA. | |
| `OUTBOUND_TYPE` | How outbound traffic will be configured for a cluster. accepted values: loadBalancer, userDefinedRouting | |
| `KUBERNETES_VERSION` | Version of Kubernetes to use for creating the cluster, value from: az aks get-versions | |

### Parameters for nodepool_\<type>.conf
Each nodepool_\<type>.conf file describes properties to deploy nodepool, i.e. virtual machine scale set containing one or more K8S nodes.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `NODEPOOL_NAME` | Name of the node pool to create | |
| `DOMAIN` | Name of domain for hosting K8S nodepool | acme |
| `KIND` | Specifies which type of pods(product component) will be hosted on this nodepool  | |
| `MACHINE_TYPE` | Size of Virtual Machines to create as Kubernetes nodes | |
| `LOCATION` | Geographical location where Azure datacenter for region is located | |
| `RESOURCE_GROUP` | Name of azure resource group, i.e. parent entity that holds related azure resources together |
| `VNET_NAME` | Name of azure virtual network | |
| `SUBNET_NAME` | Name of subnetwork to create | |
| `SUBNET_CIDR` | IP address prefix used to create subnetwork | |
| `K8S_CLUSTER_NAME` | Name of AKS cluster to create | |
| `NODE_TAINTS` | Setting on EC2/K8S node to repel a pod from being scheduled, key=val:\<Schedule> | |
| `MAX_PODS_PER_NODE` | The max number of pods deployable to each node in node pool | |
| `MIN_NODES` | Minimum number of nodes in the node pool | |
| `MAX_NODES` | Maximum number of nodes in the node pool | |
| `NUM_NODES` | Number of nodes in the Kubernetes node pool | |
| `DISK_SIZE` | Size in GB of the OS disk for each node in the node pool | |
| `DISK_TYPE` | OS type for each node in node pool, Linux or Windows | Linux |
| `PRIORITY` | The priority of the node pool, Regular or Low | Regular |
| `ENABLE_CLUSTER_AUTOSCALER` | Whether to enable cluster autoscaler for node pool, to control scale up/down activity | true |
| `KUBERNETES_VERSION` | Version of Kubernetes to use for creating the cluster, value from: az aks get-versions | |
| `LABELS` | The node labels for the node pool. You can't change the node labels through CLI after the node pool is created. See https://aka.ms/node-labels for syntax of labels. | |
| `MODE` | The mode for a node pool which defines a node pool's primary function. If set as "System", AKS prefers system pods scheduling to node pools with mode System. Learn more at https://aka.ms/aks/nodepool/mode. accepted values: System, User | User |
| `NODE_OSDISK_TYPE` | OS disk type to be used for machines in a given agent pool. May not be changed for this pool after creation. | |
| `PPG` | The ID of a proximity placement groups. | |
| `PPG_TYPE` | The type of the proximity placement group. | |

### K8S node/pod tuning
For products like AnzoGraph, Spark and Elasticsearch, we need to do certain system settings like disabling transparent huge page, sysctl parameter value changes, etc. To achieve this, we have conf.d/nodepool_<nodepool_type>_tuner.yaml files defined.
Each file corresponds to a dedicated nodepool.
This file contains K8S resources to be deployed on AKS cluster to tune AKS nodes.
Below resources are created.
* `ServiceAccount`: Used to provide an identity to pods, when processes inside pod containers contact K8S API Server.

* `Role`: The permissions user can have at namespace level.

* `RoleBinding`: Holds list of users/groups/service accounts and a role which is being granted to them.

* `PodSecurityPolicy`: Security restrictions imposed to pods to run successfully within cluster.

* `DaemonSet`: Ensure all nodes run copy of pod.


### Sample use cases
Sample use cases for Azure AKS deployment are present under directory sample_use_cases, below are the sub-directories where sample conf files are present.

| Use case | Description |
|:-----------|:-------------|
| `1_azureManagedIdentity_private_cluster` | This use case explains using Azure managed identity (ENABLE_MANAGED_IDENTITY="true"), where azure handles the identity creation and management on user behalf. It is advised to use azure managed identity. Private AKS cluster (PRIVATE_CLUSTER="true") gets created with this use case which is only accessible from within the virtual network or connected network. |
| `2_createServicePrincipal_public_cluster` | This use case explains creating new service principal (SP=${SP:-"aks-service-principal"}) to deploy public cluster (PRIVATE_CLUSTER="false"), It is users responsibility to renew service principal to keep the cluster working. Managing service principals adds complexity hence it is advised to use azure managed identity. Parameter API_SERVER_AUTHORIZED_IP_RANGES can be given to limit the public access to the AKS cluster. |
| `3_useServicePrincipal` | This use case explains using existing service principal using SP_ID and SP_SECRET parameters provided in conf file. It is the user's responsibility to renew service principal to keep the cluster working. Managing service principals adds complexity hence it is advised to use azure managed identity. |
| `4_userManagedAAD` | This use case explains using user managed active directory. User has to create a client app, a server app, and requires the Azure AD tenant to grant Directory Read permissions. Below parameters are expected from the user. AAD_CLIENT_APP_ID="ValidAADClientAppId", AAD_SERVER_APP_ID="ValidAADServerAppId", AAD_SERVER_APP_SECRET="ValidAADServerAppSecret", AAD_TENANT_ID="ValidTenantId" |
| `5_azureManagedAAD` | This use case explains using azure managed active directory. In this case AKS resource provider manages the client and server apps for users. It is advised to use azure managed AAD. Below parameters are expected from the user. ENABLE_AAD="true", AAD_ADMIN_GROUP_OBJECT_IDS="CommaSeparatedListOfAdminGroupProjectIds" |
| `6_attachACR` | This use case explains attaching azure private ACR with the AKS cluster. This integration assigns the AcrPull role to the managed identity associated with the AKS Cluster. It enables AKS clusters to pull images from private ACR registry. If you need to pull an image from a private external registry, use an image pull secret. Below parameters are expected from the user. ATTACH_ACR="ContainerRegistry" |
| `7_clusterAutoscalerSupport` | This use case explains the use of cluster autoscaler. The cluster autoscaler component increases the nodes in the node pool as per demand and decreases the nodes as demand lowers. This ability to automatically scale up or down the number of nodes in your AKS cluster lets you run an efficient, cost-effective cluster. Below parameters are expected from the user. ENABLE_CLUSTER_AUTOSCALER="true", CLUSTER_AUTOSCALER_PROFILE="scan-interval=10s scale-down-delay-after-delete=10s" |
| `8_MonitoringEnabled` | This use case explains enabling the cluster monitoring, it turns on Log Analytics monitoring for the cluster. Below parameters are expected from the user. AKS_ENABLE_ADDONS="monitoring" |
| `9_RBACSupport` | This use case explains enabling RBAC. This feature frees users from having to separately manage user identities and credentials for Kubernetes. When enabled, this integration allows customers to use Azure AD users, groups, or service principals as subjects in Kubernetes RBAC. Below parameters are expected from the user. DISABLE_RBAC="false", By default RBAC is enabled, and can be overridden with DISABLE_RBAC. |
| `10_useExistingResources` | This use case explains using existing azure resources. When the user gives below mentioned parameters with pre-existing resource names, the AKS cluster deployment will not re-create the resources. If the resources are not present then it will create them. Below parameters are expected from the user. RESOURCE_GROUP=${RESOURCE_GROUP:-"aks-resource-group"}, VNET_NAME=${VNET_NAME:-"cloud-k8s-vnet1"}, SUBNET_NAME="cloud-k8s-subnet1" |
| `11_useProximityPlacementGroups` | This use case explains using proximity placement groups for reduced latency.Proximity placement group is a logical grouping used to make sure Azure compute resources are physically located close to each other. This helps low latency applications. Below parameters are expected from the user. PPG=${PPG:-"csippg"}, PPG_TYPE=${PPG_TYPE:-"standard"} |

## References:
```https://docs.cambridgesemantics.com/```

```https://docs.google.com/document/d/1ydLaQ3N_dub4B1Y6eLtT-WjaulMzWlOwYY58Qd9_wPU/edit?usp=sharing```

```https://docs.cambridgesemantics.com/anzo/userdoc/azure-aks.htm```
