#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color
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
    # shellcheck disable=SC1091
    source "./reference/versions"
}

prereq () {
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        file="/etc/os-release"
        os_name=$(grep -E "^NAME=" $file | awk -F '=' '{print $2}' | sed -r 's#"##g')
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_name="MacOS"
    else
        printf "%bOperating system %s is not supported,  Exiting.%b\n" "${RED}" "${OSTYPE}" "${NC}" >&2
        exit 1
    fi
    echo -e "Operating System   : ${os_name}"
    ## Check eksctl is installed.
    local_eksctl_version=$(eksctl version |  cut -d " " -f 5 | sed -e 's/GitTag:"\(.*\)"}/\1/')
    eksctl_status="$?"
    if [ "${eksctl_status}" -ne 0 ];then
        printf "%beksctl not installed, Exiting.%b\n" "${RED}" "${NC}" >&2
        exit 1
    fi
    lower_version=$(echo "${local_eksctl_version}"; echo -e "${EKSCTL_VERSION}" | sort --version-sort | head --lines=1)
    if [[ "${lower_version}" == "${local_eksctl_version}" ]] && [[ "${lower_version}" != "${EKSCTL_VERSION}" ]]; then
        printf "%beksctl is installed, but expected minimum version is %s.%b\n" "${RED}" "${EKSCTL_VERSION}" "${NC}" >&2
        exit 1
    fi
    printf "eksctl version: %s\n" "${local_eksctl_version}"
    ## Check awscli is installed.
    local_aws_cli_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    aws_status="$?"
    if [ "${aws_status}" -ne 0 ];then
        printf "%baws cli not installed, Exiting.%b\n" "${RED}" "${NC}" >&2
        exit 1
    fi
    lower_version=$(echo -e "${local_aws_cli_version}\n${AWS_CLI_VERSION}" | sort --version-sort | head --lines=1)
    if [[ "${lower_version}" == "${local_aws_cli_version}" ]] && [[ "${lower_version}" != "${AWS_CLI_VERSION}" ]]; then
        printf "%bawscli is installed, but expected minimum version is %s.%b\n" "${RED}" "${AWS_CLI_VERSION}" "${NC}" >&2
        exit 1
    fi
    printf "aws cli version: %s\n" "${local_aws_cli_version}"
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
