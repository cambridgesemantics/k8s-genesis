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
REGION=$(grep "region:" "${CONF}" | cut -d " " -f 4)
CLUSTER_NAME=$(grep -e "^  name:" "${CONF}" | cut -d " " -f 4)
NODEPOOL_NAME=$(grep -e "- name:" "${CONF}" | cut -d " " -f 5)
echo "REGION = ${REGION}"
echo "CLUSTER_NAME = ${CLUSTER_NAME}"
echo "NODEPOOL_NAME = ${NODEPOOL_NAME}"
export AWS_DEFAULT_REGION="${REGION}"

grep -q "allow: true" "${CONF}"
exit_code="$?"
if [[ "${exit_code}" == 0 ]]; then
    echo "INFO ${prg}: Check for pre-existing SSH access keypair"
    keypair_name=$(grep -o "publicKeyName: .*" "${CONF}")
    exit_code="$?"
    [[ "${exit_code}" != 0 ]] && keypair_name="${CLUSTER_NAME}-keypair" || keypair_name=$(echo "${keypair_name}" | cut -d' ' -f2 | tr -d '""' | tr -d "'")
    existing_kp=$(aws ec2 describe-key-pairs --filters Name=key-name,Values="${keypair_name}" --query 'KeyPairs[0].KeyName' --output text --region "${REGION}")
    if [[ "${existing_kp}" == "${keypair_name}" ]]; then
        echo "INFO ${prg}: ${keypair_name} for cluster ssh access already exists."
    elif [[ "${existing_kp}" == "None" ]]; then
        echo "Given keypair ${keypair_name} does not exist."
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to create keypair with name ${keypair_name}? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            mkdir -pv "${HOME}/.ssh/"
            set -x
            aws ec2 create-key-pair --key-name "${keypair_name}" \
                --query 'KeyMaterial' --output text > "${HOME}/.ssh/${keypair_name}" \
                --region "${REGION}"
            stat="$?"
            set +x
            if [[ "${stat}" != 0 ]]; then
                echo "ERROR ${prg}: Failure in creating SSH access keypair ${keypair_name}"
                exit 1
            fi
            echo "INFO ${prg}: Created new keypair for cluster ssh access"
        fi
    fi
fi

cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to create nodepool (y/n) : " cont
fi
if [[ $FORCE == "y" || $cont == "y" ]]; then
    set -x
    eksctl create nodegroup --config-file "${CONF}"
    stat="$?"
    set +x
    if [[ "${stat}" != 0 ]]; then
        echo "ERROR ${prg}: Failure in creating node group"
        exit 1
    fi
    echo "INFO ${prg}: Node group created successfully"
    eksctl utils write-kubeconfig -c "${CLUSTER_NAME}" -r "${REGION}" --auto-kubeconfig
    exit_code="$?"
    if [[ ${exit_code} != 0 ]]; then
        echo "ERROR ${prg}: Error in writing kubeconfig for cluster"
        exit 1
    fi
    kubeconfig="--kubeconfig=${HOME}/.kube/eksctl/clusters/${CLUSTER_NAME}"
    grep -q -e "deploy-ca: 'true'" -e "'deploy-ca': 'true'" "${CONF}"
    exit_code="$?"
    if [[ "${exit_code}" == 0 ]]; then
        echo "INFO ${prg}: Deploying cluster autoscaler on nodegroup/nodepool"
	echo "INFO ${prg}: Creating IAM policy for cluster autoscaler"
	cp --preserve reference/cluster-autoscaler-policy.json "${K8S_GENESIS_CONF_DIR}/cluster-autoscaler-policy.json"
	aws_account_id=$(aws sts get-caller-identity --output text --query 'Account')
	policy_arn=$(aws iam get-policy \
            --policy-arn "arn:aws:iam::${aws_account_id}:policy/CSIAmazonEKSClusterAutoScalerPolicy" \
            --output text --query 'Policy.Arn')
	if [[ ${policy_arn} == "" ]]; then
            policy_arn=$(aws iam create-policy \
	        --policy-name CSIAmazonEKSClusterAutoScalerPolicy \
                --policy-document "file://${K8S_GENESIS_CONF_DIR}/cluster-autoscaler-policy.json" \
	        --output text --query 'Policy.Arn')
	fi
	eksctl utils associate-iam-oidc-provider --cluster "${CLUSTER_NAME}" -r "${REGION}" --approve
	exit_code="$?"
	if [[ "${exit_code}" != 0 ]]; then
            echo "Error in enabling IAM OpenID Connect Provider(OIDC)"
            exit 1
	fi
	eksctl create iamserviceaccount \
	    --cluster="${CLUSTER_NAME}" \
	    --region="${REGION}" \
            --namespace=kube-system \
            --name=cluster-autoscaler \
            --attach-policy-arn="${policy_arn}" \
            --override-existing-serviceaccounts \
            --approve
	exit_code="$?"
	if [[ $exit_code != 0 ]]; then
	    echo "ERROR ${prg}: Failed to create IAM role for cluster autoscaler"
	    exit 1
	fi
	kubectl "${kubeconfig}" apply \
            -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
        exit_code="$?"
        if [[ $exit_code != 0 ]]; then
                echo "ERROR ${prg}: Failed to deploy cluster autoscaler"
                exit 1
        fi
	echo "INFO ${prg}: Successfully applied cluster-autoscaler YAML"
	role_arn=$(eksctl get iamserviceaccount --cluster "${CLUSTER_NAME}" \
            --namespace kube-system -r "${REGION}" -o yaml | head -5 | tail -1 | tr -d '[:space:]' | cut -d':' -f2-)
	kubectl "${kubeconfig}" annotate serviceaccount cluster-autoscaler \
            -n kube-system eks.amazonaws.com/role-arn="${role_arn}" --overwrite=true
	exit_code="$?"
	if [[ $exit_code != 0 ]]; then
	    echo "ERROR ${prg}: Failed to annotate cluster-autoscaler service account with IAM role ARN"
	    exit 1
	fi
	echo "INFO ${prg}: Successfully annotated cluster-autoscaler service account with IAM role ARN"
	cp --preserve reference/ca_autodiscover-patch-file.yaml "${K8S_GENESIS_CONF_DIR}/ca_autodiscover-patch-file.yaml"
	sed -i "s/<YOUR CLUSTER NAME>/${CLUSTER_NAME}/g" "${K8S_GENESIS_CONF_DIR}/ca_autodiscover-patch-file.yaml"
	ca_version=$(grep -o -P "(?<=cluster-autoscaler-version: '|'cluster-autoscaler-version': ').*(?=')" "${CONF}")
	sed -i "s/<YOUR CLUSTER AUTOSCALER VERSION>/${ca_version}/g" "${K8S_GENESIS_CONF_DIR}/ca_autodiscover-patch-file.yaml"
        # shellcheck disable=SC2086
	kubectl "${kubeconfig}" patch deployment cluster-autoscaler \
            -n kube-system --patch "$(cat ${K8S_GENESIS_CONF_DIR}/ca_autodiscover-patch-file.yaml)"
	exit_code="$?"
	if [[ "${exit_code}" != 0 ]]; then
	    echo "ERROR: ${prg}: Error in patching cluster autoscaler deployment with correct cluster name"
	    exit 1
	fi
	echo "INFO ${prg}: Cluster autoscaler deployed successfully"
    else
        echo "INFO ${prg}: Skipping deploying Cluster Autoscaler on this nodegroup/nodepool"
    fi
fi
echo "INFO ${prg}: Node group created successfully"

# Apply tuner yaml for nodepool.
conffile_base_name=$(basename "${CONF}" .yaml)
if [[ -r "reference/${conffile_base_name}_tuner.yaml" ]]; then
    K8S_GENESIS_TUNER_FILE="${K8S_GENESIS_CONF_DIR}/${conffile_base_name}_tuner.yaml"
    cp "reference/${conffile_base_name}_tuner.yaml" "${K8S_GENESIS_TUNER_FILE}"
    for taint in $(grep -E "taints:" "${CONF}" -A200 | grep -E "tags:" -B200 | grep -Ev "taints:|tags:" | tr -d "'" | tr -d " "); do
        key=$(echo "${taint}" | cut -d":" -f1)
        val=$(echo "${taint}" | cut -d":" -f2)
        effect=$(echo "${taint}" | cut -d":" -f3)
        node_tolerations="${node_tolerations}{\"key\":\"${key}\",\"operator\":\"Equal\",\"value\":\"${val}\",\"effect\":\"${effect}\"},"
    done
    node_tolerations="[${node_tolerations}]"
    sed -i "s#__tolerations__#${node_tolerations}#g" "${K8S_GENESIS_TUNER_FILE}"
    sed -i "s#__nodepool__#${NODEPOOL_NAME}#g" "${K8S_GENESIS_TUNER_FILE}"
    echo "Applied desired tolerations to nodepool daemonset"
    kubectl "${kubeconfig}" apply -f "${K8S_GENESIS_TUNER_FILE}"
fi
