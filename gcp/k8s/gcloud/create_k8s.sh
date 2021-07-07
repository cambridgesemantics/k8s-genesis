#!/bin/bash

prg=$0
function usage {
    echo "usage: $prg -c|--config <config file> [-d|--directory <config directory>] [-f|--force] [-h|--help]"
    echo "  Description:"
    echo "    Create GCP network, GKE Cluster, Cloud router and NAT gateway."
    echo "    Values will be taken from <config directory>/<config file>."
    echo "    Provide <config file> file name with .conf extension."
    echo "  Parameters:"
    echo "    -d|--directory  <config directory> - Directory containing configuration file, Optional."
    echo "                        K8S_GENESIS_CONF_DIR env variable can be used optionally to set directory."
    echo "                        Option -d takes precedence, defaults to ./conf.d/"
    echo "    -c|--config     <config file>      - File having configuration parameters, Required parameter."
    echo "                        e.g. k8s_cluster.conf."
    echo "                        Final path will be formed as <config directory>/<config file>."
    echo "    -f|--force        - Do not ask for confirmation, Optional."
    echo "    -h|--help         - Display help, Optional."
    exit 1
}

# shellcheck disable=SC1091
source common.sh
args "$@"
prereq

# shellcheck disable=SC1091
source gcloud_cli_common.sh

echo -e "\nDeployment details:"
echo -e "\tProject            : ${GCLOUD_PROJECT_ID}"
echo -e "\tRegion             : ${GCLOUD_CLUSTER_REGION}"
echo -e "\tGKE Cluster        : ${K8S_CLUSTER_NAME}"
echo -e "\tGKE Master version : ${GKE_MASTER_VERSION}\n\n"

cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to create GCP network ${GCLOUD_NETWORK}? (y/n) : " cont
fi
if [[ $FORCE == "y" || $cont == "y" ]]; then
    set -x
    gcloud compute networks create "${GCLOUD_NETWORK}" \
        --bgp-routing-mode="${NETWORK_BGP_ROUTING}" \
        --subnet-mode="${NETWORK_SUBNET_MODE}" \
        --project="${GCLOUD_PROJECT_ID}"
    status=$?    
    set +x 
    if [[ "${status}" != 0 ]]; then
        echo "ERROR ${prg}: Failed to create GCP network ${GCLOUD_NETWORK}, Exiting"
        exit 1
    fi
    echo "INFO ${prg}: GCP network ${GCLOUD_NETWORK} created successfully"
fi
cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to create GKE cluster ${K8S_CLUSTER_NAME}? (y/n) : " cont
fi
if [[ $FORCE == "y" || $cont == "y" ]]; then
    cluster_params=()
    if [[ $GKE_PRIVATE_ACCESS == "true" ]]; then
       cluster_params+=(--enable-private-nodes)
       if [[ -z $K8S_API_CIDR ]]; then
           echo "ERROR ${prg}: Please make sure K8S_API_CIDR is not empty when GKE_PRIVATE_ACCESS is enabled"
           exit 1
       else
          cluster_params+=(--master-ipv4-cidr="${K8S_API_CIDR}")
       fi   
       if [[ $GKE_ENABLE_PRIVATE_ENDPOINT == "true" ]]; then
           cluster_params+=(--enable-private-endpoint)
           if [[ -z $GKE_MASTER_ACCESS_CIDRS ]]; then
              echo "ERROR ${prg}: Please make sure GKE_MASTER_ACCESS_CIDRS is not empty when GKE_ENABLE_PRIVATE_ENDPOINT is enabled"
              exit 1
           fi
       fi    
    fi
    if [[ -n $GKE_MASTER_ACCESS_CIDRS ]]; then
           cluster_params+=(--enable-master-authorized-networks --master-authorized-networks="${GKE_MASTER_ACCESS_CIDRS}")
    else
           cluster_params+=(--no-enable-master-authorized-networks)
    fi
    set -x
    gcloud beta container --project="${GCLOUD_PROJECT_ID}" clusters create "${K8S_CLUSTER_NAME}" \
        --addons="${K8S_CLUSTER_ADDONS}" \
        --allow-route-overlap \
        --cluster-version="${GKE_MASTER_VERSION}" \
        --create-subnetwork range="${GCLOUD_NODES_CIDR},name=${K8S_CLUSTER_NAME}-${GCLOUD_NODES_SUBNET_SUFFIX}" \
        --cluster-ipv4-cidr="${K8S_PRIVATE_CIDR}" \
        --services-ipv4-cidr="${K8S_SERVICES_CIDR}" \
        --default-max-pods-per-node="${K8S_CLUSTER_PODS_PER_NODE}" \
        --disk-size="${K8S_HOST_DISK_SIZE}" \
        --disk-type="${K8S_HOST_DISK_TYPE}" \
        --enable-autorepair  \
        --no-enable-autoupgrade \
        --enable-stackdriver-kubernetes \
        --enable-ip-alias \
        --no-enable-legacy-authorization \
        --enable-network-policy \
        --enable-pod-security-policy \
        --enable-stackdriver-kubernetes \
        --image-type="${GKE_IMAGE_TYPE}" \
        --issue-client-certificate \
        --labels="${GCLOUD_RESOURCE_LABELS}" \
        --local-ssd-count="${GCLOUD_VM_SSD_COUNT}" \
        --machine-type="${GCLOUD_VM_MACHINE_TYPE}" \
        --maintenance-window="${GKE_MAINTENANCE_WINDOW}" \
        --max-nodes-per-pool="${K8S_POOL_HOSTS_MAX}" \
        --metadata="${K8S_METADATA}" \
        --min-cpu-platform="${K8S_HOST_MIN_CPU_PLATFORM}" \
        --network="${GCLOUD_NETWORK}" \
        --node-labels="${GCLOUD_VM_LABELS}" \
        --node-locations="${GCLOUD_NODE_LOCATIONS}" \
        --node-taints="${GCLOUD_NODE_TAINTS}" \
        --node-version="${GKE_NODE_VERSION}" \
        --no-enable-basic-auth \
        --num-nodes="${GKE_MASTER_NODE_COUNT_PER_LOCATION}" \
        --enable-autoscaling \
        --min-nodes="${K8S_MIN_NODES}" \
        --max-nodes="${K8S_MAX_NODES}" \
        --tags="${GCLOUD_VM_TAGS}" \
        --scopes="${GCLOUD_NODE_SCOPE}" \
        --region="${GCLOUD_CLUSTER_REGION}" \
        "${cluster_params[@]}"
    status=$?    
    set +x 
    if [[ "${status}" != 0 ]]; then
        echo "ERROR ${prg}: Failed to create GKE cluster ${K8S_CLUSTER_NAME}, Exiting"
        exit 1
    fi
    echo "INFO ${prg}: GKE Cluster ${K8S_CLUSTER_NAME} created successfully"
fi

cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to add/update NAT gateway for cluster subnet's outbound connections? (y/n) : " cont
fi
if [[ $FORCE == "y" || $cont == "y" ]]; then
    echo "INFO ${prg}: Checking if there is pre-existing cloud router with name ${NETWORK_ROUTER_NAME}"
    check_router=$(check_existing_router "${NETWORK_ROUTER_NAME}" "${GCLOUD_CLUSTER_REGION}" "${GCLOUD_PROJECT_ID}")
    if [[ -z $check_router ]]; then
        echo "INFO ${prg}: Router ${NETWORK_ROUTER_NAME} does not exist"
        if [[ $FORCE == "n" ]]; then
            read -r -p "INFO ${prg}: Do you want to create new router? (y/n) : " create_router
        fi
        if [[ $create_router == "n" ]]; then
            echo "INFO ${prg}: NAT gateway configuration cannot be done without deploying cloud router, please re-run deployment by typing 'y' to router creation. Exiting now"
            exit 0
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            set -x
            gcloud compute routers create "${NETWORK_ROUTER_NAME}" \
                --project="${GCLOUD_PROJECT_ID}" \
                --network="${GCLOUD_NETWORK}" \
                --advertisement-mode="${NETWORK_ROUTER_MODE}" \
                --asn="${NETWORK_ROUTER_ASN}" \
                --description="${NETWORK_ROUTER_DESC}" \
                --region="${GCLOUD_CLUSTER_REGION}"
            status="$?"
            set +x
            if [[ "${status}" != 0 ]]; then
                echo "ERROR ${prg}: Failed to create cloud router ${NETWORK_ROUTER_NAME}, Exiting"
                exit 1
            fi
            echo "INFO ${prg}: cloud router ${NETWORK_ROUTER_NAME} created successfully"
        fi
    fi
    check_nat=$(check_existing_nat "${NETWORK_ROUTER_NAME}" "${GCLOUD_CLUSTER_REGION}" "${NETWORK_NAT_NAME}")
    if [[ -z $check_nat ]]; then
        echo "INFO ${prg}: NAT ${NETWORK_NAT_NAME} does not exist"
        if [[ $FORCE == "n" ]]; then
            read -r -p "INFO ${prg}: Do you want to create new nat gateway? (y/n) : " nat_create
        fi
        if [[ $nat_create == "n" ]]; then
            echo "INFO ${prg}: Not deploying NAT gateway, cluster will not have outbound internet connection from nodes"
            exit 0
        fi

        if [[ $FORCE == "y" || $cont == "y" ]]; then
            get_cluster_subnet_ip_ranges "${K8S_CLUSTER_NAME}-${GCLOUD_NODES_SUBNET_SUFFIX}" "${GCLOUD_CLUSTER_REGION}"
            set -x
            gcloud compute routers nats create "${NETWORK_NAT_NAME}" \
                --router="${NETWORK_ROUTER_NAME}" \
                --project="${GCLOUD_PROJECT_ID}" \
                --auto-allocate-nat-external-ips \
                --router-region="${GCLOUD_CLUSTER_REGION}" \
                --udp-idle-timeout="${NETWORK_NAT_UDP_IDLE_TIMEOUT}" \
                --icmp-idle-timeout="${NETWORK_NAT_ICMP_IDLE_TIMEOUT}" \
                --tcp-established-idle-timeout="${NETWORK_NAT_TCP_ESTABLISHED_IDLE_TIMEOUT}" \
                --tcp-transitory-idle-timeout="${NETWORK_NAT_TCP_TRANSITORY_IDLE_TIMEOUT}" \
                --nat-custom-subnet-ip-ranges="${params%\,}"
            status=$?
            set +x
            if [[ "${status}" != 0 ]]; then
                echo "ERROR ${prg}: Failed to create NAT gateway ${NETWORK_NAT_NAME}, Exiting"
                exit 1
            fi
            echo "INFO ${prg}: NAT gateway ${NETWORK_NAT_NAME} created successfully"
        fi
    else
        nat_mode=$(describe_nat "${NETWORK_NAT_NAME}" "${NETWORK_ROUTER_NAME}" \
            "${GCLOUD_CLUSTER_REGION}" "${GCLOUD_PROJECT_ID}" '' 'value(sourceSubnetworkIpRangesToNat)')
        if [[ "${nat_mode}" == "ALL_SUBNETWORKS_ALL_IP_RANGES" ]]; then
            echo "INFO ${prg}: Current subnets to NAT mapping already allows all subnets' primary and secondary IP ranges, no additional configuration is required"
            exit 0
        elif [[ $nat_mode == "ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES" ]]; then
            echo "INFO ${prg}: All subnets primary IP ranges are allowed to use NAT. Please configure manually if you want to allow secondary IP ranges."
            exit 0
        else
            get_cluster_subnet_ip_ranges "${K8S_CLUSTER_NAME}-${GCLOUD_NODES_SUBNET_SUFFIX}" "${GCLOUD_CLUSTER_REGION}"
            existing_nat_subnets=$(describe_nat "${NETWORK_NAT_NAME}" "${NETWORK_ROUTER_NAME}"  \
                "${GCLOUD_CLUSTER_REGION}" "${GCLOUD_PROJECT_ID}" "subnetworks[]" \
                "csv[no-heading](subnetworks.name.basename(),subnetworks.sourceIpRangesToNat,subnetworks.secondaryIpRangeNames)")

            params+=$(prep_subnet_cidrs_nat "${existing_nat_subnets}" "${GCLOUD_CLUSTER_REGION}" "${GCLOUD_PROJECT_ID}")
        fi
        set -x
        gcloud compute routers nats update "${NETWORK_NAT_NAME}" \
            --router="${NETWORK_ROUTER_NAME}" \
            --project="${GCLOUD_PROJECT_ID}" \
            --router-region="${GCLOUD_CLUSTER_REGION}" \
            --nat-custom-subnet-ip-ranges="${params%\,}"
        status=$?
        set +x
        if [[ "${status}" != 0 ]]; then
            echo "ERROR ${prg}: Failed to update NAT gateway ${NETWORK_NAT_NAME}, Exiting"
            exit 1
        fi
        echo "INFO ${prg}: NAT gateway ${NETWORK_NAT_NAME} updated successfully"
    fi

fi
