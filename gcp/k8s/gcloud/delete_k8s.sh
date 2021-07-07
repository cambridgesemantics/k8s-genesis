#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

prg=$0
function usage {
    echo "usage: $prg -c|--config <config file> [-d|--directory <config directory>] [-f|--force] [-h|--help]"
    echo "  Description:"
    echo "    Delete GCP network, GKE Cluster, Cloud router and NAT gateway."
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
echo -e "\tRegion             : ${GCLOUD_CLUSTER_REGION}\n\n"

delete_nat="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to delete NAT gateway ${NETWORK_NAT_NAME}? (y/n) : " delete_nat
fi
if [[ $FORCE == "y" || $delete_nat == "y" ]]; then
    set -x
    gcloud compute routers nats delete "${NETWORK_NAT_NAME}" \
        --router="${NETWORK_ROUTER_NAME}" \
        --region="${GCLOUD_CLUSTER_REGION}" \
        --project="${GCLOUD_PROJECT_ID}" \
        --quiet
    status=$?    
    set +x 
    if [[ "${status}" != 0 ]]; then
        echo "ERROR ${prg}: Failed to delete NAT gateway ${NETWORK_NAT_NAME}, Exiting"
        exit 1
    fi
    echo "INFO ${prg}: NAT gateway ${NETWORK_NAT_NAME} deleted successfully"
fi

if [[ $delete_nat == "n" ]]; then
    echo "INFO ${prg}: Attempting to remove outbound connectivity for k8s nodes subnet"
    check_nat=$(check_existing_nat "${NETWORK_ROUTER_NAME}" "${GCLOUD_CLUSTER_REGION}" "${NETWORK_NAT_NAME}")
    if [[ -z $check_nat ]]; then
        echo "INFO ${prg}: NAT ${NETWORK_NAT_NAME} does not exist, no need to update subnet to NAT connectivity"
    else
        nat_mode=$(describe_nat "${NETWORK_NAT_NAME}" "${NETWORK_ROUTER_NAME}" \
            "${GCLOUD_CLUSTER_REGION}" "${GCLOUD_PROJECT_ID}" '' 'value(sourceSubnetworkIpRangesToNat)')
        if [[ $nat_mode == "LIST_OF_SUBNETWORKS" ]]; then # nat mode is custom list of primary and/or secondary subnet ip ranges
            exclude_ranges=$(get_cluster_subnet_ip_ranges "${K8S_CLUSTER_NAME}-${GCLOUD_NODES_SUBNET_SUFFIX}" "${GCLOUD_CLUSTER_REGION}")

            existing_nat_subnets=$(describe_nat "${NETWORK_NAT_NAME}" "${NETWORK_ROUTER_NAME}"  \
                "${GCLOUD_CLUSTER_REGION}" "${GCLOUD_PROJECT_ID}" "subnetworks[]" \
                "csv[no-heading](subnetworks.name.basename(),subnetworks.sourceIpRangesToNat,subnetworks.secondaryIpRangeNames)")

            params=$(prep_subnet_cidrs_nat "${existing_nat_subnets}" "${GCLOUD_CLUSTER_REGION}" "${GCLOUD_PROJECT_ID}")
            params=${params/$exclude_ranges/}
            if [[ -n $params ]]; then
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
                else
                    echo "INFO ${prg}: NAT gateway ${NETWORK_NAT_NAME} updated successfully, excluded k8s nodes subnet"    
                fi
            else
                echo "INFO ${prg}: NAT gateway has only cluster subnets associated with it. This mapping cannot be removed. Please re-run the script by selecting 'y' to delete NAT gateway"
                exit 0
            fi
        fi    
    fi
fi

cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to delete cloud router ${NETWORK_ROUTER_NAME}? (y/n) : " cont
fi
if [[ $FORCE == "y" || $cont == "y" ]]; then
    set -x
    gcloud compute routers delete "${NETWORK_ROUTER_NAME}" \
        --region="${GCLOUD_CLUSTER_REGION}" \
        --project="${GCLOUD_PROJECT_ID}" \
        --quiet
    status=$?    
    set +x 
    if [[ "${status}" != 0 ]]; then
        echo "ERROR ${prg}: Failed to delete cloud router ${NETWORK_ROUTER_NAME}, Exiting"
        exit 1
    fi
    echo "INFO ${prg}: cloud router ${NETWORK_ROUTER_NAME} deleted successfully"
fi

cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to delete GKE cluster ${K8S_CLUSTER_NAME}? (y/n) : " delete_cluster
fi
if [[ $FORCE == "y" || $delete_cluster == "y" ]]; then
    set -x
    gcloud container clusters delete "${K8S_CLUSTER_NAME}" \
        --region="${GCLOUD_CLUSTER_REGION}" \
        --project="${GCLOUD_PROJECT_ID}" \
        --quiet
    status=$?    
    set +x 
    if [[ "${status}" != 0 ]]; then
        echo "ERROR ${prg}: Failed to delete GKE cluster ${K8S_CLUSTER_NAME}, Exiting"
        exit 1
    fi
    echo "INFO ${prg}: GKE Cluster ${K8S_CLUSTER_NAME} deleted successfully"
fi

if [[ $delete_cluster == "y" ]]; then
    cluster_subnet=$(gcloud compute networks subnets list --filter="name:( ${K8S_CLUSTER_NAME}-${GCLOUD_NODES_SUBNET_SUFFIX} )" \
        --format='value(name)')
    if [[ -n $cluster_subnet ]]; then
       echo "INFO ${prg}: Cleaning up cluster subnet"
       set -x
       gcloud compute networks subnets delete "${K8S_CLUSTER_NAME}-${GCLOUD_NODES_SUBNET_SUFFIX}" \
           --region "${GCLOUD_CLUSTER_REGION}" --quiet
       status=$?
       set +x
       if [[ "${status}" != 0 ]]; then
          echo "WARNING ${prg}: Failed to delete cluster subnetwork ${K8S_CLUSTER_NAME}-${GCLOUD_NODES_SUBNET_SUFFIX}"
       fi
    fi
fi

cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to delete GCP network ${GCLOUD_NETWORK}? (y/n) : " cont
fi
if [[ $FORCE == "y" || $cont == "y" ]]; then
    set -x
    gcloud compute networks delete "${GCLOUD_NETWORK}" \
        --project="${GCLOUD_PROJECT_ID}" \
        --quiet
    status=$?    
    set +x 
    if [[ "${status}" != 0 ]]; then
        echo "ERROR ${prg}: Failed to delete GCP network ${GCLOUD_NETWORK}, Exiting"
        exit 1
    fi
    echo "INFO ${prg}: GCP network ${GCLOUD_NETWORK} deleted successfully"
fi