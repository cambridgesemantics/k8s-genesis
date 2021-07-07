#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

old_context=""
new_context=""
CONF=""

## Check command line arguments.
args () {
    FORCE="n"
    K8S_GENESIS_CONF_DIR="${K8S_GENESIS_CONF_DIR-./conf.d}"
    while [[ $# -gt 0 ]]
    do
        param="$1"

        case "${param}" in
            -d|--directory)
            K8S_GENESIS_CONF_DIR="$2"
            shift
            shift
            ;;
            -c|--config)
            K8S_GENESIS_CONF_FILE="$2"
            shift
            shift
            ;;
            -f|--force)
            export FORCE="y"
            shift
            ;;
            -h|--help)
            usage
            shift
            ;;
            *)
            shift
            ;;
        esac
    done

    if [[ -z $K8S_GENESIS_CONF_FILE ]]; then
        usage
    fi
    CONF="${K8S_GENESIS_CONF_DIR}/${K8S_GENESIS_CONF_FILE}"
    if [[ ! -r "${CONF}" ]]; then
        printf "%bCould not find configuration in %s%b\n" "${RED}" "${CONF}" "${NC}" >&2
        exit 1
    fi
    if [[ "${CONF}" =~ \.conf$ ]]; then
        # shellcheck source=conf.d/k8s_cluster.conf
        # shellcheck disable=SC1091
        source "${CONF}"
    fi
}

prereq () {
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        file="/etc/os-release"
        os_name=$(cat < $file | grep -E "^NAME=" | awk -F '=' '{print $2}' | sed -r 's#"##g')
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_name="MacOS"
    else
        printf "%bOperating system $OSTYPE is not supported,  Exiting.%b\n" "${RED}" "${NC}" >&2
        exit 1
    fi
    echo -e "Operating System   : ${os_name}"

    ## Check az is installed.
    local_azure_cli_version=$(az --version | grep -E "azure-cli" | awk  '{print $NF}')
    azure_cli_status=$?
    if [ $azure_cli_status -ne 0 ]; then
        print "${RED}azure-cli not installed, Exiting.${NC}\n" >&2
        exit 1
    fi
    lower_version=$(echo -e "${local_azure_cli_version}\n${AZURE_CLI_VERSION}" | sort --version-sort | head --lines=1)
    if [[ ${lower_version} == "${local_azure_cli_version}" ]] && [[ ${lower_version} != "${AZURE_CLI_VERSION}" ]]; then
        printf "%bazure-cli is installed, but expected minimum version is %s.%b\n" "${RED}" "${AZURE_CLI_VERSION}" "${NC}" >&2
        exit 1
    fi
    echo "azure-cli version: ${local_azure_cli_version}"

    ## Check kubectl is installed.
    kubectl_version=$(kubectl version --client=true --short=true | cut -d " " -f 3 | cut -d "v" -f 2)
    kubectl_status="$?"
    if [ "${kubectl_status}" -ne 0 ];then
        printf "%bkubectl cli not installed, Exiting.%b\n" "${RED}" "${NC}" >&2
        exit 1
    fi
    lower_version=$(echo -e "${kubectl_version}\n${CLUSTER_VERSION}" | sort --version-sort | head --lines=1)
    if [[ "${lower_version}" == "${kubectl_version}" ]] && [[ "${lower_version}" != "${CLUSTER_VERSION}" ]]; then
        printf "%bkubectl is installed, but expected minimum version is %s.%b\n" "${RED}" "${CLUSTER_VERSION}" "${NC}" >&2
        exit 1
    fi
    printf "kubectl client version: %s\n" "${kubectl_version}"
    printf "%bPackage versions are as expected%b\n" "${GREEN}" "${NC}"
}

get_admin_context() {
    old_context=$(kubectl config current-context 2> /dev/null)
    if [[ -n ${old_context} ]]; then
        printf "Original kubectl config context --> %s.\n" "${old_context}"
    else
        printf "Original kubectl config context is not set."
    fi
    az aks get-credentials --admin \
            --name "${K8S_CLUSTER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --overwrite-existing > /dev/null
    new_context=$(kubectl config current-context)
    printf "New kubectl context with AKS cluster admin user set --> %s.\n" "${new_context}"
}

get_developer_context() {
    if [[ ${old_context} == "${new_context}" ]]; then
        printf "Original and new kubectl context are same, Not updating.\n"
    else
        printf "Deleting admin kubectl context from config."
        kubectl config delete-context "${K8S_CLUSTER_NAME}-admin" > /dev/null 2>&1
        if [[ -n "${old_context}" ]]; then
            printf "Setting original kubeconfig context."
            kubectl config use-context "${old_context}" > /dev/null
        else
            printf "Original kubeconfig context was not set previously."
        fi
    fi
}

exec_files () {
    for file in "${K8S_GENESIS_CONF_DIR}"/exec/*; do
        printf "Applying content from file: %s\n" "${file}"
        kubectl apply -f "${file}" > /dev/null;
    done
}

tune_nodepool() {
    # Apply tuner yaml for nodepool in to k8s
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to tune the nodepool? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        kubectl apply -f "${1}"
    fi
}

delete_tune_nodepool() {
    # Delete tuner Daemonset for nodepool.
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to delete the daemonset of nodepools? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        if [[ -n ${NODE_TAINTS} ]]; then
            for taint in $(echo "$NODE_TAINTS" | tr "," "\n"); do
                key=$(echo "${taint}" | cut -d"=" -f1)
                val=$(echo "${taint}" | cut -d"=" -f2 | cut -d":" -f1)
                effect=$(echo "${taint}" | cut -d"=" -f2 | cut -d":" -f2)
                node_tolerations="${node_tolerations}{\"key\":\"${key}\",\"operator\":\"Equal\",\"value\":\"${val}\",\"effect\":\"${effect}\"},"
            done
        fi
        node_tolerations="[${node_tolerations}]"
        K8S_GENESIS_TUNER_FILE="$1"
        sed -i "s#__tolerations__#${node_tolerations}#g" "${K8S_GENESIS_TUNER_FILE}"
        sed -i "s#NODEPOOL_NAME#${NODEPOOL_NAME}#g" "${K8S_GENESIS_TUNER_FILE}"
        daemonset_name=$(grep -E "name: .*tuner-" "${K8S_GENESIS_TUNER_FILE}" | tr -d " " | cut -d ':' -f2)
        daemonset_present=$(kubectl get Daemonset "${daemonset_name}" -n=kube-system 2> /dev/null | grep -c "${daemonset_name}")
        if [[ ${daemonset_present} == 1 ]]; then
            echo "Deleting daemonset ${daemonset_name} of nodepool ${NODEPOOL_NAME}"
            kubectl delete Daemonset "${daemonset_name}" -n=kube-system
        fi
    fi
}
