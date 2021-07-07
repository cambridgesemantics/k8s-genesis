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
export AWS_DEFAULT_REGION="${REGION}"
# shellcheck disable=SC1091
source aws_cli_common.sh

echo "INFO ${prg}: Check for pre-existing EKS cluster"
eksctl get cluster --name "${CLUSTER_NAME}" --region "${REGION}" > /dev/null 2> /dev/null
exit_code="$?"
if [[ $exit_code == 0 ]]; then
    echo "INFO ${prg}: EKS cluster to be deleted: ${CLUSTER_NAME}"
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to delete EKS cluster? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        eksctl delete cluster --name "${CLUSTER_NAME}" --region "${REGION}"  -w
        exit_code="$?"
        if [[ "${exit_code}" != 0 ]]; then
            echo "INFO ${prg}: Error in deleting EKS cluster ${CLUSTER_NAME}"
            exit 1
        else
            echo "INFO ${prg} cluster ${CLUSTER_NAME} deleted successfully"
        fi
    fi
else
    echo "INFO ${prg}: No pre-existing EKS cluster found."
fi

if [[ -n "${VPC_ID}" ]]; then
    echo "INFO ${prg}: cluster deployment is done in existing VPC, deleting resources created for holding EKS cluster"

    # Delete Public subnets
    public_subnet_ids=$(aws ec2 describe-subnets --filter Name=vpc-id,Values="${VPC_ID}" \
        Name=tag:Name,Values="${CLUSTER_NAME}-PublicSubnet*" Name=tag:Cluster,Values="${CLUSTER_NAME}" \
        --query 'Subnets[*].SubnetId' --output text --region "${REGION}")
    echo "INFO ${prg}: Check for pre-existing public subnets"
    if [[ "${public_subnet_ids}" != "" ]]; then
        public_subnet_ids_tmp=$(echo "$public_subnet_ids" | tr -s ' ')
        echo "INFO ${prg}: Public subnets to be deleted: ${public_subnet_ids_tmp}"
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to delete public subnets? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            for subnet in ${public_subnet_ids}
            do
                delete_subnet "${subnet}"
                echo "INFO ${prg}: Deleted public subnet: ${subnet}"
            done
        fi
    else
        echo "INFO ${prg}: No pre-existing public subnets found."
    fi

    # Delete Private subnets
    private_subnet_ids=$(aws ec2 describe-subnets --filter Name=vpc-id,Values="${VPC_ID}" \
        Name=tag:Name,Values="${CLUSTER_NAME}-PrivateSubnet*" Name=tag:Cluster,Values="${CLUSTER_NAME}" \
        --query 'Subnets[*].SubnetId' --output text --region "${REGION}")
    echo "INFO ${prg}: Check for pre-existing private subnets"
    if [[ "${private_subnet_ids}" != "" ]]; then
        private_subnet_ids_tmp=$(echo "${private_subnet_ids}" | tr -s ' ')
        echo "INFO ${prg}: Private subnets to be deleted: ${private_subnet_ids_tmp}"
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to delete private subnets? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            for subnet in ${private_subnet_ids}
            do
                delete_subnet "${subnet}"
                echo "INFO ${prg}: Deleted private subnet: ${subnet}"
            done

        fi
    else
        echo "INFO ${prg}: No pre-existing private subnets found."
    fi

    # Delete Public route tables
    public_rtbs=$(aws ec2 describe-route-tables --filter Name=vpc-id,Values="${VPC_ID}" \
        Name=tag:Name,Values="${CLUSTER_NAME}-RtbForPublicSubnets*" Name=tag:Cluster,Values="${CLUSTER_NAME}" \
        --query 'RouteTables[*].RouteTableId' --output text --region "${REGION}")
    echo "INFO ${prg}: Check for pre-existing public route tables"
    if [[ "${public_rtbs}" != "" ]]; then
        echo "INFO ${prg}: Public route tables to be deleted: $public_rtbs"
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to delete public route tables? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            for rtb in ${public_rtbs}
            do
                delete_route_table "${rtb}"
                echo "INFO ${prg}: Deleted public route table: ${rtb}"
            done
        fi
    else
        echo "INFO ${prg}: No pre-existing public route tables found."
    fi

    # Delete Private route tables
    private_rtbs=$(aws ec2 describe-route-tables --filter Name=vpc-id,Values="${VPC_ID}" \
        Name=tag:Name,Values="${CLUSTER_NAME}-RtbForPrivateSubnets-*" Name=tag:Cluster,Values="${CLUSTER_NAME}" \
        --query 'RouteTables[*].RouteTableId' --output text --region "${REGION}")
    echo "INFO ${prg}: Check for pre-existing private route tables"
    if [[ "${private_rtbs}" != "" ]]; then
        echo "INFO ${prg}: Private route tables to be deleted: $private_rtbs"
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to delete private route tables? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            for rtb in ${private_rtbs}
            do
                delete_route_table "${rtb}"
                echo "INFO ${prg}: Deleted private route table: ${rtb}"
            done
        fi
    else
        echo "INFO ${prg}: No pre-existing private route tables found."
    fi

    # Delete NAT Gateway
    nat_gw_ids=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values="${VPC_ID}" \
        Name=tag:Name,Values="${CLUSTER_NAME}-NATGW-*" Name=tag:Cluster,Values="${CLUSTER_NAME}" \
        --query 'NatGateways[*].NatGatewayId' --output text --region "${REGION}")
    echo "INFO ${prg}: Check for pre-existing NAT gateway"
    if [[ "${nat_gw_ids}" != "" ]]; then
        echo "INFO ${prg}: NAT Gateway to be deleted: $nat_gw_ids"
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to delete NAT Gateway? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            for nat in ${nat_gw_ids}
            do
                delete_nat "${nat}"
                echo "INFO ${prg}: Deleted nat gateway: ${nat}"
            done
        fi
    else
        echo "INFO ${prg}: No pre-existing NAT gateway found."
    fi

    # Delete NAT subnet
    nat_subnet_ids=$(aws ec2 describe-subnets --filter Name=vpc-id,Values="${VPC_ID}" \
        Name=tag:Name,Values="${CLUSTER_NAME}-SubnetForNAT-*" Name=tag:Cluster,Values="${CLUSTER_NAME}" \
        --query 'Subnets[*].SubnetId' --output text --region "${REGION}")
    echo "INFO ${prg}: Check for pre-existing NAT subnet"
    if [[ "${nat_subnet_ids}" != "" ]]; then
        echo "INFO ${prg}: NAT subnets to be deleted: $nat_subnet_ids"
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to delete NAT subnets? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            for subnet in ${nat_subnet_ids}
            do
                delete_subnet "${subnet}"
                echo "INFO ${prg}: Deleted subnet: ${subnet}"
            done
        fi
    else
        echo "INFO ${prg}: No pre-existing NAT subnet found."
    fi

    # Delete NAT's route table
    nat_rtbs=$(aws ec2 describe-route-tables --filter Name=vpc-id,Values="${VPC_ID}" \
        Name=tag:Name,Values="${CLUSTER_NAME}-RtbForNATSubnet-*" Name=tag:Cluster,Values="${CLUSTER_NAME}" \
        --query 'RouteTables[*].RouteTableId' --output text --region "${REGION}")
    echo "INFO ${prg}: Check for pre-existing NAT route table"
    if [[ "${nat_rtbs}" != "" ]]; then
        echo "INFO ${prg}: NAT Subnet's route tables to be deleted: $nat_rtbs"
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to delete NAT subnet's route tables? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            for rtb in ${nat_rtbs}
            do
                delete_route_table "${rtb}"
                echo "INFO ${prg}: Deleted NAT route table: ${rtb}"
            done
        fi
    else
        echo "INFO ${prg}: No pre-existing NAT route table found."
    fi

    ## Delete Cluster SSH access keypair.
    if [[ "${ENABLE_SSH}" == true ]]; then
        echo "INFO ${prg}: Check for pre-existing Cluster ssh access keypair"
        [[ -z "${KEYPAIR_NAME}" ]] && keypairname="${CLUSTER_NAME}-keypair" || keypairname="${KEYPAIR_NAME}"
        existing_kp=$(aws ec2 describe-key-pairs --filters Name=key-name,Values="${keypairname}" \
            --query 'KeyPairs[0].KeyName' --output text --region "${REGION}")
        if [[ "${existing_kp}" == "${keypairname}" ]]; then
            echo "INFO ${prg}: Cluster ssh access keypair to be deleted: ${keypairname}"
            cont="n"
            if [[ $FORCE == "n" ]]; then
                read -r -p "Do you want to delete cluster ssh access keypair ${keypairname}? (y/n) : " cont
            fi
            if [[ $FORCE == "y" || $cont == "y" ]]; then
                set -x
                aws ec2 delete-key-pair --key-name "${keypairname}"
                stat="$?"
                set +x
                if [[ "${stat}" -ne 0 ]]; then
                    echo "ERROR ${prg}: Failure in deleting cluster ssh access keypair"
                    exit 1
                fi
                echo "INFO ${prg}: Deleted cluster keypair for ssh access"
            fi
        else
            echo "INFO ${prg}: Cluster keypair for ssh access does not exist."
        fi
    fi
# Commenting IGW deletion part, IGW may be in use by existing resources
#    igw_id=$(aws ec2 describe-internet-gateways \
#       --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
#       --query 'InternetGateways[0].InternetGatewayId' --output text)
#    echo "INFO ${prg}: Detaching IGW ${igw_id}"
#    aws ec2 detach-internet-gateway --internet-gateway-id="${igw_id}" --vpc-id="${VPC_ID}"
#    echo "INFO ${prg}: Deleting Internet Gateway"
#    aws ec2 delete-internet-gateway --internet-gateway-id="${igw_id}"
#    echo "INFO ${prg}: Deleted Internet Gateway"
#    echo "Resource clean up in ${VPC_ID} completed"
fi
