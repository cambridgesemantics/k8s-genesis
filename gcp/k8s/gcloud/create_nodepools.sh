#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

programname=$0
function usage {
    echo "usage: $programname -c|--config <config file> [-d|--directory <config directory>] [-f|--force] [-h|--help]"
    echo "  Description:"
    echo "    Creates cluster nodes in nodegroup/nodepool."
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
        read -r -p "Do you want to create nodepool ${NODEPOOL_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        set -x
        gcloud container node-pools create "${NODEPOOL_NAME}" \
            --project="${GCLOUD_PROJECT_ID}" \
            --cluster="${K8S_CLUSTER_NAME}" \
            --region="${GCLOUD_CLUSTER_REGION}" \
            --machine-type="${machine}" \
            --tags="${TAGS}" \
            --image-type="${GKE_IMAGE_TYPE}" \
            ${GKE_NODE_VERSION:+--node-version=${GKE_NODE_VERSION}} \
            --enable-autoscaling \
              ${PREEMTIVE:+--preemptible} \
              ${GCLOUD_NODE_TAINTS:+--node-taints=${GCLOUD_NODE_TAINTS}} \
	          ${NODE_LABELS:+--node-labels=${NODE_LABELS}} \
            --metadata="${METADATA}" \
            --no-enable-autoupgrade \
            --max-pods-per-node="${MAX_PODS_PER_NODE}" \
            --max-nodes="${MAX_NODES}" \
            --min-nodes="${MIN_NODES}" \
            --num-nodes="${NUM_NODES}" \
            --disk-size="${DISK_SIZE}" \
            --disk-type="${DISK_TYPE}"
        status=$?
        set +x 
        if [[ "${status}" != 0 ]]; then
            echo "ERROR ${programname}: Error in creating nodepool ${NODEPOOL_NAME}, Exiting" 
            exit 1
        fi
        echo "INFO ${programname}: Nodepool ${NODEPOOL_NAME} created successfully"
    else
	echo "skipped  ${NODEPOOL_NAME}" 1>&2 
    fi
done

# Authenticate with GKE cluster API endpoint for doing further settings
gcloud container clusters get-credentials "${K8S_CLUSTER_NAME}" --region "${GCLOUD_CLUSTER_REGION}" --project="${GCLOUD_PROJECT_ID}"
exit_code=$?
if [[ "${exit_code}" != 0 ]]; then
    echo "ERROR ${programname}: Failed to login to cluster, Exiting" 
    exit 1
fi

# Configuring and creating tuner daemonset
config_base=$(basename "${CONF}" | cut -f 1 -d '.' )
if [[ -r "${K8S_GENESIS_CONF_DIR}/${config_base}_tuner.yaml" ]]; then
    cont="n"
    NODEPOOL_NAME=${DOMAIN}-${KIND}-${machine}${PREEMTIVE:+-p}
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to tune the nodepools? (y/n) : " cont
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
        echo "Applied desired tolerations to nodepool daemonset"
        kubectl apply -f "${K8S_GENESIS_CONF_DIR}/${config_base}_tuner.yaml"
    fi
fi
