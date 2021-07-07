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
source ./common.sh
args "$@"
prereq
REGION=$(grep "region:" "${CONF}" | cut -d " " -f 4)
CLUSTER_NAME=$(grep -e "^  name:" "${CONF}" | cut -d " " -f 4)
NODEPOOL_NAME=$(grep -e "- name:" "${CONF}" | cut -d " " -f 5)
echo "REGION = ${REGION}"
echo "CLUSTER_NAME = ${CLUSTER_NAME}"
echo "NODEPOOL_NAME = ${NODEPOOL_NAME}"
export AWS_DEFAULT_REGION="${REGION}"

eksctl utils write-kubeconfig -c "${CLUSTER_NAME}" -r "${REGION}" --auto-kubeconfig
exit_code="$?"
if [[ ${exit_code} != 0 ]]; then
    echo "ERROR ${prg}: Error in writing kubeconfig for cluster"
    exit 1
fi
kubeconfig="--kubeconfig=${HOME}/.kube/eksctl/clusters/${CLUSTER_NAME}"

# Delete tuner Daemonset for nodepool.
conffile_base_name=$(basename "${CONF}" .yaml)
if [[ -r "reference/${conffile_base_name}_tuner.yaml" ]]; then
    K8S_GENESIS_TUNER_FILE="${K8S_GENESIS_CONF_DIR}/${conffile_base_name}_tuner.yaml"
    cp "reference/${conffile_base_name}_tuner.yaml" "${K8S_GENESIS_TUNER_FILE}"
    NODEPOOL_NAME=$(grep -e "- name:" "${CONF}" | cut -d " " -f 5)
    sed -i "s#__nodepool__#${NODEPOOL_NAME}#g" "${K8S_GENESIS_TUNER_FILE}"
    daemonset_name=$(grep -E "name: .*tuner-" "${K8S_GENESIS_TUNER_FILE}" | tr -d " " | cut -d ':' -f2)
    daemonset_present=$(kubectl "${kubeconfig}" get Daemonset "${daemonset_name}" -n=kube-system 2> /dev/null | grep -Ec "${daemonset_name}")
    if [[ "${daemonset_present}" == 1 ]]; then
        echo "Deleting daemonset ${daemonset_name} of nodepool ${NODEPOOL_NAME}"
        kubectl "${kubeconfig}" delete Daemonset "${daemonset_name}" -n=kube-system
    fi
fi

echo "INFO ${prg}: Nodegroup/Nodepool specified in the configuration file ${CONF} is going to be deleted."
grep -q -e "deploy-ca: 'true'" -e "'deploy-ca': 'true'" "${CONF}"
exit_code="$?"
if [[ "${exit_code}" == 0 ]]; then
    echo "WARN ${prg}: This nodepool has cluster-autoscaler configuration. If you delete cluster autoscaler, other nodegroups may not function properly"
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you really want to delete cluster autoscaler configuration? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        kubectl "${kubeconfig}" delete \
            -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
        stat="$?"
        if [[ $stat != 0 ]]; then
            echo "ERROR ${prg}: Error in deleting cluster autoscaler configuration"
            exit 1
        fi
    fi
fi

cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to delete nodepool? (y/n) : " cont
fi
if [[ $FORCE == "y" || $cont == "y" ]]; then
    set -x
    eksctl delete nodegroup -f "${CONF}" --wait --approve
    stat="$?"
    set +x
    if [[ "${stat}" != 0 ]]; then
        echo "ERROR ${prg}: Failure in deleting nodegroup/nodepool."
        exit 1
    fi
    echo "INFO ${prg}: Node group deleted successfully"
fi

grep -q "allow: true" "${CONF}"
exit_code="$?"
if [[ "${exit_code}" == 0 ]]; then
    echo "INFO ${prg}: Check for pre-existing SSH access keypair for nodepool"
    keypair_name=$(grep -o "publicKeyName: .*" "${CONF}")
    exit_code="$?"
    [[ "${exit_code}" != 0 ]] && keypair_name="${CLUSTER_NAME}-keypair" || keypair_name=$(echo "${keypair_name}" | cut -d' ' -f2 | tr -d '""' | tr -d "'")
    existing_kp=$(aws ec2 describe-key-pairs --filters Name=key-name,Values="${keypair_name}" --query 'KeyPairs[0].KeyName' --output text --region "${REGION}")
    if [[ "${existing_kp}" == "${keypair_name}" ]]; then
        echo "INFO ${prg}: Found keypair with name ${keypair_name}"
	echo "WARN ${prg}: We recommend you NOT to delete the key-pair if you are using it for other nodepools or it is required for future use"
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to delete keypair ${keypair_name} anyway? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            set -x
            aws ec2 delete-key-pair --key-name "${keypair_name}" --region "${REGION}"
            stat="$?"
            set +x
            if [[ "${stat}" != 0 ]]; then
                echo "ERROR ${prg}: Failure in deleting SSH access keypair ${keypair_name}"
                exit 1
            fi
            echo "INFO ${prg}: Deleted new keypair for cluster ssh access"
        fi
    elif [[ "${existing_kp}" == "None" ]]; then
        echo "Given keypair ${keypair_name} does not exist."
    fi
else
    echo "INFO ${prg}: No keypair information found"
fi
echo "INFO ${prg}: Completed nodepool deletion process for nodepool ${NODEPOOL_NAME}"
