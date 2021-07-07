#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

prg="${0}"
function usage {
    echo "usage: $prg -c|--config <config file> [-d|--directory <config directory>] [-f|--force] [-h|--help]"
    echo "  Description:"
    echo "    Creates NAT gateway and Internet gateway, route table, subnets, VPC and EKS cluster."
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

echo -e "\nDeployment details:"
echo -e "\tAKS cluster        : ${K8S_CLUSTER_NAME}"
echo -e "\tResource group     : ${RESOURCE_GROUP}"
echo -e "\tLocation           : ${LOCATION}"

# shellcheck disable=SC2153
sp_id="${SP_ID}"
# shellcheck disable=SC2153
sp_secret="${SP_SECRET}"
if [[ -n ${ENABLE_MANAGED_IDENTITY} ]] && [[ ${ENABLE_MANAGED_IDENTITY} == "true" ]]; then
    echo "INFO ${prg}: Using managed identities to create cluster"
else
    echo "INFO ${prg}: Using service principal to create cluster"
    new_sp="false"
    ## Create service principal
    if [[ -n ${sp_id} && -n ${sp_secret} ]]; then
        serv_prin_exist=$(az ad sp show --id "${sp_id}" --query "accountEnabled")
        exit_code="$?"
        if [ $exit_code == 0 ] && [ "$serv_prin_exist" == '"True"' ]; then
            echo "INFO ${prg}: Using azure service principal and secret from configuration file."
        else
            echo "INFO ${prg}: Provided azure service principal in configuration file is not enabled/present."
        fi
    else
        new_sp="true"
    fi
    if [[ ${new_sp} == "true" && -n ${SP} && -n ${SP_VALIDITY_YEARS} ]]; then
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to create Azure service principal ${SP}? (y/n) : " cont
            if [[ $cont == "n" ]]; then
                echo "INFO ${prg}: You have opted for NOT creating azure service principal"
            fi
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            echo "INFO ${prg}: Creating/patching azure service principal with name ${SP}"
            output=$(az ad sp create-for-rbac --name "${SP}" \
                --years "${SP_VALIDITY_YEARS}" \
                --output tsv \
                --query "[appId, password]" \
                --scopes "/subscriptions/${SUBSCRIPTION_ID}" 2> /dev/null | tr '\n' ' ')
            exit_code="$?"
            if [[ $exit_code == 0 ]]; then
                sp_id=$(echo "$output" | awk '{print $1}')
                sp_secret=$(echo "$output" | awk '{print $2}')
                echo "INFO ${prg}: Service principal created"
                echo "INFO ${prg}: SP_ID: $sp_id"
                echo "INFO ${prg}: SP_SECRET: $sp_secret"
                echo "INFO ${prg}: Azure service principal creation completed"
            else
                echo "ERROR ${prg}: Azure service principal creation failed, Exiting!" >&2
                exit 1
            fi
        fi
    else
        echo "WARN ${prg}: All or some of parameters for creating service principal(SP, SP_VALIDITY_YEARS) are not specified."
        echo "WARN ${prg}: Deployment will continue without azure service principal, but we recommend you to create cluster with managed identity or service principal"
    fi
fi

## Create resource group
if [[ ${RESOURCE_GROUP} == "" || -z ${RESOURCE_GROUP} ]]; then
    echo "ERROR ${prg}: Please provide required parameter RESOURCE_GROUP with non-empty value." >&2
    exit 1
fi
echo "INFO ${prg}: Checking for existing resource group ${RESOURCE_GROUP}."
res_grp_exist=$(az group exists --name "${RESOURCE_GROUP}")
exit_code="$?"
if [[ $exit_code == 0 ]] && [[ "$res_grp_exist" == "true" ]]; then
    echo "INFO ${prg}: Resource group ${RESOURCE_GROUP} already exists."
else
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to create resource group ${RESOURCE_GROUP}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Creating resource group ${RESOURCE_GROUP}."
        res_grp_out=$(az group create \
            --name "${RESOURCE_GROUP}" \
            --location "${LOCATION}" \
            --tags "${RESOURCE_GROUP_TAGS}" \
            --query "properties.provisioningState")
        exit_code="$?"
        if [[ $exit_code == 0 ]] && [[ "$res_grp_out" == '"Succeeded"' ]]; then
            echo "INFO ${prg}: Resource group created."
        else
            echo "ERROR ${prg}: Failed to create resource group." >&2
            exit 1
        fi
    fi
fi

## Create virtual network
if [[ ${VNET_NAME} == "" || -z ${VNET_NAME} ]]; then
    echo "ERROR ${prg}: Please provide required parameter VNET_NAME with non-empty value." >&2
    exit 1
fi
echo "INFO ${prg}: Checking for existing virtual network ${VNET_NAME}."
az network vnet show \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${VNET_NAME}" > /dev/null 2>&1
exit_code="$?"
if [[ $exit_code == 0 ]]; then
    echo "INFO ${prg}: Virtual network ${VNET_NAME} already exists."
else
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to create Azure virtual network ${VNET_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Creating azure virtual network ${VNET_NAME}."
        vnet_out=$(az network vnet create \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${VNET_NAME}" \
            --address-prefix "${VNET_CIDR}" \
            --location "${LOCATION}" \
            --tags "${VNET_TAGS}" \
            --vm-protection "${VNET_VM_PROTECTION}" \
            --query "newVNet.provisioningState")
        exit_code="$?"
        if [[ $exit_code == 0 ]] && [[ "$vnet_out" == '"Succeeded"' ]]; then
            echo "INFO ${prg}: Virtual network created."
        else
            echo "ERROR ${prg}: Failed to create virtual network." >&2
            exit 1
        fi
    fi
fi

## Create virtual subnet
if [[ ${SUBNET_NAME} == "" || -z ${SUBNET_NAME} ]]; then
    echo "ERROR ${prg}: Please provide required parameter SUBNET_NAME with non-empty value." >&2
    exit 1
fi
echo "INFO ${prg}: Checking for existing subnet ${SUBNET_NAME}."
subnet_id=$(az network vnet subnet show \
      --resource-group "${RESOURCE_GROUP}" \
      --vnet-name "${VNET_NAME}" \
      --name "${SUBNET_NAME}" \
      --query "id" 2> /dev/null | sed 's#^"##' | sed 's#"$##')
if [[ -n $subnet_id ]]; then
    echo "INFO ${prg}: Subnet ${SUBNET_NAME} already exists."
else
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to create subnet ${SUBNET_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Creating subnet ${SUBNET_NAME}."
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
fi

## Create AKS cluster
if [[ ${K8S_CLUSTER_NAME} == "" || -z ${K8S_CLUSTER_NAME} ]]; then
    echo "ERROR ${prg}: Please provide required parameter K8S_CLUSTER_NAME with non-empty value." >&2
    exit 1
fi
echo "INFO ${prg}: Checking for existing AKS cluster ${K8S_CLUSTER_NAME}."
az aks show \
    --name "${K8S_CLUSTER_NAME}" \
    --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1
exit_code="$?"
if [[ $exit_code == 0 ]]; then
    echo "INFO ${prg}: AKS cluster already exists."
    file_count=$(find "${K8S_GENESIS_CONF_DIR}/exec/" -type f -name "*.yaml" 2> /dev/null | wc -l)
    if [[ $file_count == 0 ]]; then
        echo "INFO ${prg}: No yaml files found in exec directory."
    else
        echo "INFO ${prg}: Kubectl applying files from exec directory."
        get_admin_context
        exec_files
        get_developer_context
    fi
else
    key_file=""
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to create AKS cluster ${K8S_CLUSTER_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Creating AKS cluster ${K8S_CLUSTER_NAME}."
        params=""
        if [[ -n ${ENABLE_CLUSTER_AUTOSCALER} ]] && [[ ${ENABLE_CLUSTER_AUTOSCALER} == "true" ]]; then
            if [[ -n ${MIN_NODES} ]] && [[ -n ${MAX_NODES} ]]; then
                params+="--enable-cluster-autoscaler --min-count ${MIN_NODES} --max-count ${MAX_NODES} "
            fi
            if [[ -n ${CLUSTER_AUTOSCALER_PROFILE} ]]; then
                params+="--cluster-autoscaler-profile ${CLUSTER_AUTOSCALER_PROFILE} "
            fi
        fi
        if [[ -n ${ATTACH_ACR} ]]; then
            params+="--attach-acr ${ATTACH_ACR} "
        fi
        if [[ -n ${AAD_CLIENT_APP_ID} ]] \
           && [[ -n ${AAD_SERVER_APP_ID} ]] \
           && [[ -n ${AAD_SERVER_APP_SECRET} ]] \
           && [[ -n ${AAD_TENANT_ID} ]]; then
             params+="--aad-client-app-id ${AAD_CLIENT_APP_ID} \
               --aad-server-app-id ${AAD_SERVER_APP_ID} \
               --aad-server-app-secret ${AAD_SERVER_APP_SECRET} \
               --aad-tenant-id ${AAD_TENANT_ID} "
        fi
        if [[ -n ${NETWORK_POLICY} ]]; then
            params+="--network-policy ${NETWORK_POLICY} "
        else
            params+="--network-policy azure "
        fi
        if [[ -n ${NETWORK_PLUGIN} ]]; then
            params+="--network-plugin ${NETWORK_PLUGIN} "
        else
            params+="--network-plugin azure "
        fi
        if [[ -n ${WINDOWS_ADMIN_PASSWORD} ]] && [[ -n ${WINDOWS_ADMIN_USERNAME} ]]; then
            params+="--windows-admin-password ${WINDOWS_ADMIN_PASSWORD} --windows-admin-username ${WINDOWS_ADMIN_USERNAME} "
        fi
        if [[ -n ${PRIVATE_CLUSTER} ]] && [[ ${PRIVATE_CLUSTER} == "true" ]]; then
            params+="--enable-private-cluster "
        fi
        if [[ -n ${ENABLE_MANAGED_IDENTITY} ]] && [[ ${ENABLE_MANAGED_IDENTITY} == "true" ]]; then
            params+="--enable-managed-identity "
        fi
        if [[ -n ${WORKSPACE_RESOURCE_ID} ]]; then
            params+="--workspace-resource-id ${WORKSPACE_RESOURCE_ID} "
        fi
        if [[ -n ${DNS_NAME_PREFIX} ]]; then
            params+="--dns-name-prefix ${DNS_NAME_PREFIX} "
        fi
        if [[ -n ${DISABLE_RBAC} ]] && [[ ${DISABLE_RBAC} == "true" ]]; then
            params+="--disable-rbac "
        fi
        if [[ -n ${SSH_PUB_KEY_VALUE} ]]; then
            key_file="${SSH_PUB_KEY_VALUE}"
            if [[ $SSH_PUB_KEY_VALUE == *" "* && $SSH_PUB_KEY_VALUE == ssh* ]]; then
                key_tmp_file=$(mktemp tmp.XXXXXX)
                echo "${SSH_PUB_KEY_VALUE}" > "${key_tmp_file}"
                key_file="${key_tmp_file}"
            fi
            params+="--ssh-key-value ${key_file} "
        else
            params+="--generate-ssh-keys "
        fi
        if [[ -n ${LB_MANAGED_OUTBOUND_IP_COUNT} ]] \
           && [[ -n ${LB_OUTBOUND_IP_PREFIXES} ]] \
           && [[ -n ${LB_OUTBOUND_IPS} ]]; then
             params+="--load-balancer-managed-outbound-ip-count ${LB_MANAGED_OUTBOUND_IP_COUNT} \
               --load-balancer-outbound-ip-prefixes ${LB_OUTBOUND_IP_PREFIXES} \
               --load-balancer-outbound-ips ${LB_OUTBOUND_IPS} "
        fi
        if [[ -n ${NODE_ZONES} ]]; then
            params+="--zones ${NODE_ZONES} "
        fi
        if [[ -n ${ENABLE_NODE_PUBLIC_IP} ]] && [[ ${ENABLE_NODE_PUBLIC_IP} == "true" ]]; then
            params+="--enable-node-public-ip "
            if [[ -n ${PUBLIC_IP_PREFIX} ]]; then
                pip_prefix_id=$(az network public-ip prefix show \
                    --name "${PUBLIC_IP_PREFIX}" \
                    --resource-group "${RESOURCE_GROUP}" \
                    --output json --query "id" 2> /dev/null)
                exit_code="$?"
                if [[ $exit_code != 0 ]]; then
                    echo "INFO ${prg}: public ip prefix does not exist, trying to create one"
                    pip_prefix_id=$(az network public-ip prefix create \
                        --length "${PUBLIC_IP_PREFIX_LENGTH}" \
                        --name "${PUBLIC_IP_PREFIX}" \
                        --resource-group "${RESOURCE_GROUP}" \
                        --output json --query "id" 2> /dev/null)
                    exit_code="$?"
                    pip_prefix_id=$(echo "${pip_prefix_id}" | sed 's#^"##' | sed 's#"$##')
                    if [[ ${exit_code} != 0 ]]; then
                        echo "ERROR ${prg}: Error in creating public ip prefix" >&2
                        exit 1
                    fi
                    echo "INFO ${prg}: public ip prefix with name ${PUBLIC_IP_PREFIX} created"
                else
                    echo "INFO ${prg}: using pre-existing public ip prefix with name ${PUBLIC_IP_PREFIX}"
                    pip_prefix_id=$(echo "${pip_prefix_id}" | sed 's#^"##' | sed 's#"$##')
                fi
                params+="--node-public-ip-prefix ${pip_prefix_id} "
            fi
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
        if [[ -n "${NODE_OSDISK_TYPE}" ]]; then
            params+="--node-osdisk-type ${NODE_OSDISK_TYPE} "
        fi
        if [[ -n "${POD_CIDR}" ]]; then
            params+="--pod-cidr ${POD_CIDR} "
        fi
        if [[ -n ${SKIP_SUBNET_ROLE_ASSIGNMENT} ]] && [[ ${SKIP_SUBNET_ROLE_ASSIGNMENT} == "true" ]]; then
            params+="--skip-subnet-role-assignment "
        fi
        if [[ -n ${API_SERVER_AUTHORIZED_IP_RANGES} ]]; then
            params+="--api-server-authorized-ip-ranges ${API_SERVER_AUTHORIZED_IP_RANGES} "
            if [[ -n ${ENABLE_NODE_PUBLIC_IP} ]] && [[ ${ENABLE_NODE_PUBLIC_IP} == "true" ]] && [[ -z ${PUBLIC_IP_PREFIX} ]]; then
                echo "ERROR ${prg}: API server authorized IP ranges requires public IP prefix to enable node public IP"
                echo "ERROR ${prg}: Please enable and use PUBLIC_IP_PREFIX and PUBLIC_IP_PREFIX_LENGTH parameters in configuration file and re-run the script"
                exit 1
            fi
        fi
        if [[ -n ${sp_id} ]] && [[ -n ${sp_secret} ]]; then
            params+="--service-principal ${sp_id} "
            params+="--client-secret ${sp_secret} "
        fi
        if [[ -n "${NODEPOOL_LABELS}" ]]; then
            params+="--nodepool-labels ${NODEPOOL_LABELS} "
        fi
        if [[ -n ${NODEPOOL_TAGS} ]]; then
            params+="--nodepool-tags ${NODEPOOL_TAGS} "
        fi
        if [[ -n ${UPTIME_LSA} ]] && [[ ${UPTIME_LSA} == "true" ]]; then
            params+="--uptime-sla "
        fi
        if [[ ${ENABLE_AAD} ]] && [[ ${ENABLE_AAD} == "true" ]]; then
            params+="--enable-aad "
            admin_aad_id=""
            if [[  ${AAD_ADMIN_GROUP_OBJECT_IDS} ]]; then
                admin_aad_id="${AAD_ADMIN_GROUP_OBJECT_IDS}"
            elif [[ -n ${AKS_ADMIN_GROUP} ]]; then
                admin_aad_id=$(az ad group show --group "${AKS_ADMIN_GROUP}" --query "objectId" 2> /dev/null)
                exit_code="$?"
                if [[ $exit_code != 0 ]]; then
                    echo "WARN ${prg}: Azure active directory admin group does not exist, trying to create one"
                    admin_aad_id=$(az ad group create --display-name "${AKS_ADMIN_GROUP}" --mail-nickname "${AKS_ADMIN_GROUP}" -o json --query "objectId" 2> /dev/null)
                    exit_code="$?"
                    if [[ ${exit_code} != 0 ]]; then
                        echo "ERROR ${prg}: Error in creating active directory admin group." >&2
                        exit 1
                    fi
                fi
                admin_aad_id=$(echo "${admin_aad_id}" | sed 's#^"##' | sed 's#"$##')
            fi
            params+="--aad-admin-group-object-ids ${admin_aad_id} "
        fi
        if [[ -n "${ACI_SUBNET_NAME}" ]]; then
            params+="--aci-subnet-name ${ACI_SUBNET_NAME} "
        fi
        if [[ -n "${OS_DISK_ENCRYPTIONSET_ID}" ]]; then
            params+="--node-osdisk-diskencryptionset-id ${OS_DISK_ENCRYPTIONSET_ID} "
        fi
        if [[ -n "${USER_ASSIGNED_IDENTITY_ID}" ]]; then
            params+="--assign-identity ${USER_ASSIGNED_IDENTITY_ID} "
        fi
        if [[ -n ${KUBERNETES_VERSION} ]]; then
            params+="--kubernetes-version ${KUBERNETES_VERSION} "
        fi
        # shellcheck disable=SC2086
        aks_out=$(az aks create \
            --name "${K8S_CLUSTER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --admin-username "${K8S_NODE_ADMIN_USER}" \
            --node-count "${K8S_CLUSTER_NODE_COUNT}" \
            --location "${LOCATION}" \
            --tags "${AKS_TAGS}" \
            --enable-addons "${AKS_ENABLE_ADDONS}" \
            --load-balancer-sku "${LOAD_BALANCER_SKU}" \
            --nodepool-name "${NODEPOOL_NAME}" \
            --node-vm-size "${MACHINE_TYPE}" \
            --node-osdisk-size "${DISK_SIZE}" \
            --max-pods "${MAX_PODS_PER_NODE}" \
            --vm-set-type "${VM_SET_TYPE}" \
            --vnet-subnet-id "${subnet_id}" \
            --docker-bridge-address "${DOCKER_BRIDGE_ADDRESS}" \
            --dns-service-ip "${DNS_SERVICE_IP}" \
            --service-cidr "${SERVICE_CIDR}" \
            --outbound-type "${OUTBOUND_TYPE}" \
            ${params} \
            --yes \
            --query 'provisioningState')
        exit_code="$?"
        [[ -f ${key_file} && ${key_file} == tmp.* ]] && rm "${key_file}"
        if [[ ${exit_code} == 0 ]] && [[ $aks_out == '"Succeeded"' ]]; then
            echo -ne "\nINFO ${prg}: AKS cluster created successfully.\n"
            file_count=$(find "${K8S_GENESIS_CONF_DIR}/exec/" -type f -name "*.yaml" 2> /dev/null | wc -l)
            if [[ $file_count == 0 ]]; then
                echo "INFO ${prg}: No yaml files found in exec directory."
            else
                echo "INFO ${prg}: Kubectl applying files from exec directory."
                get_admin_context
                exec_files
                get_developer_context
            fi
        else
            echo "ERROR ${prg}: Failed to successfully create AKS cluster." >&2
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
