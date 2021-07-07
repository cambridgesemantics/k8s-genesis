#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

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
        printf "%bCould not find configuration file %s%b\n" "${RED}" "${CONF}" "${NC}" >&2
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
        os_name=$(grep "^NAME=" $file | awk -F '=' '{print $2}' | sed -r 's#"##g')
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os_name="MacOS"
    else
        printf "%bOperating system $OSTYPE is not supported,  Exiting.%b\n" "${RED}" "${NC}" >&2
        exit 1        
    fi
    echo -e "Operating System   : ${os_name}"

    ## Check gcloud is installed.
    gcloud version --format list
    gcloud_status=$?
    if [ $gcloud_status -ne 0 ];then
        printf '%bGcloud not installed, Exiting.%b\n' "${RED}" "${NC}" >&2
        exit 1
    fi

    ## Check kubectl is installed.
    echo -ne "Checking kubectl cli version:\n"
    kubectl_version=$(kubectl version --client=true --short=true | cut -d " " -f 3 | cut -d "v" -f 2)
    kubectl_status=$?
    if [ $kubectl_status -ne 0 ];then
        printf '%bkubectl cli not installed, Exiting.%b\n' "${RED}" "${NC}" >&2
        exit 1
    fi
    printf "Installed kubectl client version is: %s\n" "${kubectl_version}"
    printf '%bvalid%b\n' "${GREEN}" "${NC}"
}
