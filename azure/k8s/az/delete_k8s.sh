#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

prg="${0}"
function usage {
    echo "usage: $prg -c|--config <config file> [-d|--directory <config directory>] [-f|--force] [-h|--help]"
    echo "  Description:"
    echo "    Deletes NAT gateway, Internet gateway, route table, subnets, VPC and EKS cluster."
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
. ./common.sh

args "$@"
prereq

echo -e "\nDeployment details:"
echo -e "\tAKS cluster        : ${K8S_CLUSTER_NAME}"
echo -e "\tResource group     : ${RESOURCE_GROUP}"
echo -e "\tLocation           : ${LOCATION}"

## Delete AKS cluster
echo "INFO ${prg}: Checking for existing AKS cluster ${K8S_CLUSTER_NAME}."
az aks show --name "${K8S_CLUSTER_NAME}" \
      --resource-group "${RESOURCE_GROUP}" > /dev/null 2>&1
exit_code="$?"
if [[ $exit_code != 0 ]]; then
    echo "INFO ${prg}: AKS cluster ${K8S_CLUSTER_NAME} does not exist."
else
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to delete AKS cluster ${K8S_CLUSTER_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Deleting AKS cluster ${K8S_CLUSTER_NAME}."
        az aks delete \
            --name "${K8S_CLUSTER_NAME}" \
            --resource-group "${RESOURCE_GROUP}" \
            --yes
        exit_code="$?"
        if [[ $exit_code == 0 ]]; then
            echo "INFO ${prg}: AKS cluster ${K8S_CLUSTER_NAME} deleted successfully."
        else
            echo "ERROR ${prg}: Failed to delete AKS cluster ${K8S_CLUSTER_NAME}." >&2
            exit 1
        fi
    fi
fi

## Delete public ip prefix
if [[ -n ${PUBLIC_IP_PREFIX} ]]; then
    echo "INFO ${prg}: Checking for existing public ip prefix ${PUBLIC_IP_PREFIX}."
    pip_prefix_id=$(az network public-ip prefix show \
        --name "${PUBLIC_IP_PREFIX}" \
        --resource-group "${RESOURCE_GROUP}" \
        --output json --query "id" 2> /dev/null)
    exit_code="$?"
    pip_prefix_id=$(echo "${pip_prefix_id}" | sed 's#^"##' | sed 's#"$##')
    if [[ $exit_code != 0 ]]; then
        echo "INFO ${prg}: Public ip prefix ${PUBLIC_IP_PREFIX} does not exist."
    else
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to delete public ip prefix ${PUBLIC_IP_PREFIX}? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            echo "INFO ${prg}: Deleting public ip prefix ${PUBLIC_IP_PREFIX}."
            az network public-ip prefix delete \
                --resource-group "${RESOURCE_GROUP}" \
                --name "${PUBLIC_IP_PREFIX}"
            exit_code="$?"
            if [[ $exit_code == 0 ]]; then
                echo "INFO ${prg}: Public ip prefix deleted."
            else
                echo "ERROR ${prg}: Failed to delete public ip prefix." >&2
                exit 1
            fi
        fi
    fi
fi

## Delete virtual subnet
echo "INFO ${prg}: Checking for existing subnet ${SUBNET_NAME}."
az network vnet subnet show \
      --resource-group "${RESOURCE_GROUP}" \
      --vnet-name "${VNET_NAME}" \
      --name "${SUBNET_NAME}" > /dev/null 2>&1
exit_code="$?"
if [[ $exit_code != 0 ]]; then
    echo "INFO ${prg}: Subnet ${SUBNET_NAME} does not exist."
else
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to delete subnet ${SUBNET_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Deleting subnet ${SUBNET_NAME}."
        az network vnet subnet delete \
            --resource-group "${RESOURCE_GROUP}" \
            --vnet-name "${VNET_NAME}" \
            --name "${SUBNET_NAME}"
        exit_code="$?"
        if [[ $exit_code == 0 ]]; then
            echo "INFO ${prg}: Subnet deleted."
        else
            echo "ERROR ${prg}: Failed to delete subnet." >&2
            exit 1
        fi
    fi
fi

## Delete virtual network
echo "INFO ${prg}: Checking for existing virtual network ${VNET_NAME}."
az network vnet show \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${VNET_NAME}" > /dev/null 2>&1
exit_code="$?"
if [[ $exit_code != 0 ]]; then
    echo "INFO ${prg}: Virtual network ${VNET_NAME} does not exist."
else
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to delete Azure virtual network ${VNET_NAME}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Deleting azure virtual network ${VNET_NAME}."
        az network vnet delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${VNET_NAME}"
        exit_code="$?"
        if [[ $exit_code == 0 ]]; then
            echo "INFO ${prg}: Virtual network deleted."
        else
            echo "ERROR ${prg}: Failed to delete virtual network." >&2
            exit 1
        fi
    fi
fi

## Delete resource group
echo "INFO ${prg}: Checking for existing resource group ${RESOURCE_GROUP}."
res_grp_exist=$(az group exists --name "${RESOURCE_GROUP}")
if [[ $res_grp_exist == "false" ]]; then
    echo "INFO ${prg}: Resource group ${RESOURCE_GROUP} does not exist."
else
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to delete resource group ${RESOURCE_GROUP}? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Deleting resource group ${RESOURCE_GROUP}."
        az group delete --name "${RESOURCE_GROUP}" --yes
        exit_code="$?"
        if [[ $exit_code == 0 ]]; then
            echo "INFO ${prg}: Resource group deleted."
        else
            echo "ERROR ${prg}: Failed to delete resource group." >&2
            exit 1
        fi
    fi
fi
