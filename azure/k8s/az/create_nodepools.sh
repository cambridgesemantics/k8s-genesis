#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

prg="${0}"
function usage {
    echo "usage: $prg -c|--config <config file> [-d|--directory <config directory>] [-f|--force] [-h|--help]"
    echo "  Description:"
    echo "    Creates cluster nodes in nodegroup/nodepool."
    echo "    Values will be taken from <config directory>/<config file>"
    echo "    Provide <config file> file name with .conf extension."
    echo "  Parameters:"
    echo "    -d|--directory  <config directory> - Directory containing configuration file, Optional."
    echo "                        K8S_GENESIS_CONF_DIR env variable can be used optionally to set directory."
    echo "                        Option -d takes precedence, defaults to ./conf.d/"
    echo "    -c|--config     <config file>      - File having configuration parameters, Required parameter."
    echo "                        e.g. nodepool.yaml"
    echo "                        Final path will be formed as <config directory>/<config file>."
    echo "    -f|--force        - Do not ask for confirmation, Optional."
    echo "    -h|--help         - Display help, Optional."
    exit 1
}

# shellcheck disable=SC1091
source common.sh

args "$@"
prereq

echo -e "\nDeployment details:"
echo -e "\tNodepool name      : ${NODEPOOL_NAME}"
echo -e "\tAKS cluster        : ${K8S_CLUSTER_NAME}"
echo -e "\tResource group     : ${RESOURCE_GROUP}"
echo -e "\tLocation           : ${LOCATION}"
echo -e "\tMachine type       : ${MACHINE_TYPE}\n\n"

echo "INFO ${prg}: Checking existing nodepool ${NODEPOOL_NAME}."
az aks nodepool show \
    --name "${NODEPOOL_NAME}" \
    --cluster-name "${K8S_CLUSTER_NAME}" \
    --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1
exit_code="$?"
if [[ $exit_code == 0 ]]; then
    echo "INFO ${prg}: Nodepool ${NODEPOOL_NAME} already exists."
else
    echo "INFO ${prg}: Nodepool ${NODEPOOL_NAME} does not exist, Creating..."
    ## Create virtual subnet for nodepool
    echo "INFO ${prg}: Checking existing subnet ${SUBNET_NAME} for nodepool."
    subnet_id=$(az network vnet subnet show \
        --resource-group "${RESOURCE_GROUP}" \
        --vnet-name "${VNET_NAME}" \
        --name "${SUBNET_NAME}" \
        --query "id" 2> /dev/null | sed 's#^"##' | sed 's#"$##')
    if [[ -n $subnet_id ]]; then
        echo "INFO ${prg}: Subnet ${SUBNET_NAME} already exists."
    else
        echo "INFO ${prg}: Creating subnet ${SUBNET_NAME} for nodepool."
        subnet_id=$(az network vnet subnet create \
            --resource-group "${RESOURCE_GROUP}" \
            --vnet-name "${VNET_NAME}" \
            --name "${SUBNET_NAME}" \
            --address-prefix "${SUBNET_CIDR}" \
            --query "id" | sed 's#^"##' | sed 's#"$##')
        exit_code="$?"
        if [[ $exit_code == 0 ]]; then
            echo "INFO ${prg}: Subnet created."
        else
            echo "ERROR ${prg}: Failed to create subnet." >&2
            exit 1
        fi
    fi

    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to create nodepool ${NODEPOOL_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Creating nodepool ${NODEPOOL_NAME}."
        params=""
        if [[ -n ${ENABLE_CLUSTER_AUTOSCALER} ]] && [[ ${ENABLE_CLUSTER_AUTOSCALER} == "true" ]]; then
            if [[ -n ${MIN_NODES} ]] && [[ -n ${MAX_NODES} ]]; then
                params+="--enable-cluster-autoscaler --min-count ${MIN_NODES} --max-count ${MAX_NODES} "
            fi
        fi
        if [[ -n ${KUBERNETES_VERSION} ]]; then
                params+="--kubernetes-version ${KUBERNETES_VERSION} "
        fi
        if [[ -n ${LABELS} ]]; then
                params+="--labels ${LABELS} "
        fi
        if [[ -n ${TAGS} ]]; then
                params+="--tags ${TAGS} "
        fi
        if [[ -n "${NODE_OSDISK_TYPE}" ]]; then
            params+="--node-osdisk-type ${NODE_OSDISK_TYPE} "
        fi
        if [[ -n ${PPG} ]]; then
            ppg_id=$(az ppg show --name "${PPG}" --resource-group "${RESOURCE_GROUP}" --output json --query 'id' 2> /dev/null)
            exit_code="$?"
            if [[ $exit_code != 0 ]]; then
                echo "WARN ${prg}: Proximity placement group does not exist, trying to create one"
                ppg_id=$(az ppg create -n "${PPG}" -g "${RESOURCE_GROUP}" -t "${PPG_TYPE}" \
                    --output json --query 'id' 2> /dev/null)
                exit_code="$?"
                if [[ ${exit_code} != 0 ]]; then
                    echo "ERROR ${prg}: Error in creating proximity placement group" >&2
                    exit 1
                fi
            fi
            ppg_id=$(echo "${ppg_id}" | sed 's#^"##' | sed 's#"$##')
            params+="--ppg ${ppg_id} "
        fi
        if [[ -n ${ENABLE_NODE_PUBLIC_IP} ]] && [[ ${ENABLE_NODE_PUBLIC_IP} == "true" ]]; then
            params+="--enable-node-public-ip "
        fi
        if [[ -n ${MAX_SURGE} ]]; then
            params+="--max-surge ${MAX_SURGE}"
        fi
        # shellcheck disable=SC2086
        nodepool_out=$(az aks nodepool add \
            --cluster-name "${K8S_CLUSTER_NAME}" \
            --name "${NODEPOOL_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --max-pods "${MAX_PODS_PER_NODE}" \
            --node-count "${NUM_NODES}" \
            --node-osdisk-size "${DISK_SIZE}" \
            --node-taints "${NODE_TAINTS}" \
            --node-vm-size "${MACHINE_TYPE}" \
            --os-type "${OS_TYPE}" \
            --vnet-subnet-id "${subnet_id}" \
            --mode "${MODE:-User}" \
            ${params} \
            --query "provisioningState"
        )
        exit_code="$?"
        if [[ $exit_code == 0 ]] && [[ $nodepool_out == '"Succeeded"' ]]; then
            echo "INFO ${prg}: Nodepool created successfully."
        else
            echo "ERROR ${prg}: Failed to create nodepool." >&2
            exit 1
        fi
    fi
fi

if [[ "${KIND}" == "anzograph" || "${KIND}" == "dynamic" ]]; then
    K8S_GENESIS_TUNER_FILE="${K8S_GENESIS_CONF_DIR}/nodepool_${KIND}_tuner.yaml"
    cp "reference/nodepool_${KIND}_tuner.yaml" "${K8S_GENESIS_TUNER_FILE}"
    echo "INFO ${prg}: Tuning nodepool."
    if [[ -n "${NODE_TAINTS}" ]]; then
        for taint in $(echo "$NODE_TAINTS" | tr "," "\n"); do
            key=$(echo "${taint}" | cut -d"=" -f1)
            val=$(echo "${taint}" | cut -d"=" -f2 | cut -d":" -f1)
            effect=$(echo "${taint}" | cut -d"=" -f2 | cut -d":" -f2)
            node_tolerations="${node_tolerations}{\"key\":\"${key}\",\"operator\":\"Equal\",\"value\":\"${val}\",\"effect\":\"${effect}\"},"
        done
    fi
    node_tolerations="[${node_tolerations}]"
    sed -i "s#__tolerations__#${node_tolerations}#g" "${K8S_GENESIS_TUNER_FILE}"
    sed -i "s#NODEPOOL_NAME#${NODEPOOL_NAME}#g" "${K8S_GENESIS_TUNER_FILE}"
    get_admin_context
    tune_nodepool "${K8S_GENESIS_TUNER_FILE}"
    get_developer_context
fi
