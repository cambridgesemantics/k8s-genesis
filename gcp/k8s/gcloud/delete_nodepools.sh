#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

programname=$0
function usage {
    echo "usage: $programname -c|--config <config file> [-d|--directory <config directory>] [-f|--force] [-h|--help]"
    echo "  Description:"
    echo "    Deletes cluster nodes in nodegroup/nodepool."
    echo "    Values will be taken from <config directory>/<config file>"
    echo "    Provide <config file> file name with .conf extension."
    echo "  Parameters:"
    echo "    -d|--directory  <config directory> - Directory containing configuration file, Optional."
    echo "                        K8S_GENESIS_CONF_DIR env variable can be used optionally to set directory."
    echo "                        Option -d takes precedence, defaults to ./conf.d/"
    echo "    -c|--config     <config file>      - File having configuration parameters, Required parameter."
    echo "                        e.g. nodepool.conf"
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
echo -e "\tProject            : ${GCLOUD_PROJECT_ID}"
echo -e "\tRegion             : ${GCLOUD_CLUSTER_REGION}"
echo -e "\tGKE Cluster        : ${K8S_CLUSTER_NAME}\n\n"

for machine in ${MACHINE_TYPES}; do
    cont="n"
    NODEPOOL_NAME=${DOMAIN}-${KIND}-${machine}${PREEMTIVE:+-p}
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to delete Nodepool ${NODEPOOL_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        set -x
        gcloud container node-pools delete  "${NODEPOOL_NAME}" \
            --project="${GCLOUD_PROJECT_ID}" \
            --region="${GCLOUD_CLUSTER_REGION}"  \
            --cluster="${K8S_CLUSTER_NAME}" \
            --quiet
        status=$?
        set +x
        if [[ "${status}" != 0 ]]; then
            echo "ERROR ${programname}: Failed to delete nodepool ${NODEPOOL_NAME}, Exiting" 
            exit 1
        fi
        echo "INFO ${programname}: Nodepool ${NODEPOOL_NAME} deleted successfully"    
    else
       echo " skip ${NODEPOOL_NAME}" 1>&2 
    fi
done

# Authenticate with GKE cluster API endpoint for doing further settings
gcloud container clusters get-credentials "${K8S_CLUSTER_NAME}" --region "${GCLOUD_CLUSTER_REGION}" --project="${GCLOUD_PROJECT_ID}"
exit_code=$?
if [[ "${exit_code}" != 0 ]]; then
    echo "ERROR ${programname}: Failed to login to cluster, Exiting" 
    exit 1
fi

# Deleting tuner daemonset
config_base=$(basename "${CONF}" | cut -f 1 -d '.' )
if [[ -r "${K8S_GENESIS_CONF_DIR}/${config_base}_tuner.yaml" ]]; then
    cont="n"
    NODEPOOL_NAME=${DOMAIN}-${KIND}-${machine}${PREEMTIVE:+-p}
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to delete nodepool tune settings? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        if [[ -n ${GCLOUD_NODE_TAINTS} ]]; then
            for taint in $(echo "$GCLOUD_NODE_TAINTS" | tr "," "\n"); do
                key=$(echo "${taint}" | cut -d"=" -f1)
                val=$(echo "${taint}" | cut -d"=" -f2 | cut -d":" -f1)
                effect=$(echo "${taint}" | cut -d"=" -f2 | cut -d":" -f2)
                node_tolerations="${node_tolerations}{\"key\":\"${key}\",\"operator\":\"Equal\",\"value\":\"${val}\",\"effect\":\"${effect}\"},"
            done
        fi
        node_tolerations="[${node_tolerations}]"
        sed -i "s#__tolerations__#${node_tolerations}#g" "${K8S_GENESIS_CONF_DIR}/${config_base}_tuner.yaml"
        sed -i "s#__nodepool__#${NODEPOOL_NAME}#g" "${K8S_GENESIS_CONF_DIR}/${config_base}_tuner.yaml"
        daemonset_name=$(grep -E "name: .*tuner-" "${K8S_GENESIS_CONF_DIR}/${config_base}_tuner.yaml" | tr -d " " | cut -d ':' -f2)
        daemonset_present=$(kubectl get Daemonset "${daemonset_name}" -n=kube-system 2> /dev/null | grep -c "${daemonset_name}")
        if [[ ${daemonset_present} == 1 ]]; then
            echo "Deleting daemonset ${daemonset_name} of nodepool ${NODEPOOL_NAME}"
            kubectl delete Daemonset "${daemonset_name}" -n=kube-system
        fi
    fi
fi
