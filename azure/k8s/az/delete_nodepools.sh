#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

prg="${0}"
function usage {
    echo "usage: $prg -c|--config <config file> [-d|--directory <config directory>] [-f|--force] [-h|--help]"
    echo "  Description:"
    echo "    Deletes cluster nodes in nodegroup/nodepool."
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

## Delete nodepool
echo "INFO ${prg}: Checking for existing Nodepool ${NODEPOOL_NAME}."
az aks nodepool show --name "${NODEPOOL_NAME}" \
      --cluster-name "${K8S_CLUSTER_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query provisioningState > /dev/null 2>&1
exit_code="$?"
if [[ $exit_code == 0 ]]; then
    conffile_base_name=$(basename "${CONF}" .conf)
    if [[ -r "reference/${conffile_base_name}_tuner.yaml" ]]; then
        K8S_GENESIS_TUNER_FILE="${K8S_GENESIS_CONF_DIR}/${conffile_base_name}_tuner.yaml"
        cp "reference/${conffile_base_name}_tuner.yaml" "${K8S_GENESIS_TUNER_FILE}"

        echo "INFO ${prg}: Delete nodepool tuning."
        sed -i "s#NODEPOOL_NAME#${NODEPOOL_NAME}#g" "${K8S_GENESIS_TUNER_FILE}"
        get_admin_context
        delete_tune_nodepool "${K8S_GENESIS_TUNER_FILE}"
        get_developer_context
    fi
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to delete Nodepool ${NODEPOOL_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        az aks nodepool delete \
            --cluster-name "${K8S_CLUSTER_NAME}" \
            --name "${NODEPOOL_NAME}" \
            --resource-group "${RESOURCE_GROUP}"
        exit_code="$?"
        if [[ $exit_code == 0 ]]; then
            echo "INFO ${prg}: Nodepool ${NODEPOOL_NAME} deleted successfully."
        else
            echo "ERROR ${prg}: Failed to delete Nodepool ${NODEPOOL_NAME}." >&2
            exit 1
        fi
    fi
else
    echo "INFO ${prg}: Nodepool ${NODEPOOL_NAME} does not exist."
fi
