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
. ./common.sh
args "$@"
prereq
export AWS_DEFAULT_REGION="${REGION}"
# shellcheck disable=SC1091
source aws_cli_common.sh

params=()
# Create public and private subnets, if existing VPC is specified
if [[ -z "${VPC_ID}" ]]; then
    echo "INFO ${prg}: Existing VPC not specified for EKS cluster deployment, will create new VPC during cluster deployment"
else
    check_dns_hostname=$(aws ec2 describe-vpc-attribute --vpc-id "${VPC_ID}" \
        --attribute enableDnsHostnames --query 'EnableDnsHostnames.Value' --output text)
    if [[ "${check_dns_hostname}" == "False" ]]; then
        echo "INFO ${prg}: 'Enable DNS Hostnames' property is disabled for VPC ${VPC_ID}, enabling it"
        aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames "{\"Value\":true}"
        exit_code="$?"
        if [[ "${exit_code}" != 0 ]]; then
            echo "ERROR ${prg}: Error in enabling DNS Hostnames property. Exiting"
            exit 1
        fi
        echo "INFO ${prg}: Enabled DNS Hostnames property"
    fi
    echo "INFO ${prg}: Prerequisite satisfied: EnableDnsHostnames property is enabled for VPC"

    echo "INFO ${prg}: Check for pre-existing internet gateway"
    igw_id=$(aws ec2 describe-internet-gateways \
        --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
        --query 'InternetGateways[0].InternetGatewayId' --output text)
    echo "INFO ${prg}: ID of existing internet gateway: ${igw_id}"
    if [[ "${igw_id}" == "None" ]]; then
        echo "INFO ${prg}: No existing VPC-IGW attachment found, creating new internet gateway."
        igw_id=$(aws ec2 create-internet-gateway \
            --query 'InternetGateway.InternetGatewayId' --output text)
        echo "INFO ${prg}: Internet gateway ${igw_id} created."
        aws ec2 attach-internet-gateway --vpc-id "${VPC_ID}" \
            --internet-gateway-id "${igw_id}"
        create_tags "${igw_id}" "Name=${CLUSTER_NAME}-IGW,Cluster=${CLUSTER_NAME}"
        echo "INFO ${prg}: Internet gateway ${igw_id} attached to vpc ${VPC_ID}."
    fi

    IFS=' ' read -r -a AvailabilityZones <<< "$AvailabilityZones"
    NUM_AZS="${#AvailabilityZones[@]}"

    nat_azs=()
    nats_subnets=()
    for i in $(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available" \
        --query "NatGateways[*].SubnetId" --output text); do
        nats_subnets+=("$i")
        az=$(aws ec2 describe-subnets --subnet-ids "${i}" \
           --query 'Subnets[0].AvailabilityZone' --output text)
        nat_azs+=("$az")
    done

    IFS=' ' read -r -a nat_sub_cidrs <<< "$NAT_SUBNET_CIDRS"
    nat_sub_cidrs=("${nat_sub_cidrs[@]:0:${NUM_AZS}}")
    echo "INFO ${prg}: Using nat subnet cidrs for NAT creation : ${nat_sub_cidrs[*]}"

    fnat_list=()
    for i in "${!AvailabilityZones[@]}"; do
        az="${AvailabilityZones[$i]}"
        nat_id=""
        echo "INFO ${prg}: Checking if NAT gateway is present in AZ ${az}"
        if [[ ${nat_azs[*]} =~ ${az} ]]; then
            echo "INFO ${prg}: NAT gateway exists in AZ"
            index=-1
            for j in "${!nat_azs[@]}"; do
                if [[ ${nat_azs[$j]} == "${az}" ]]; then
                    index=$j && break
                fi
            done
            nat_id=$(aws ec2 describe-nat-gateways --filter "Name=subnet-id,Values=${nats_subnets[$index]}" "Name=state,Values=available" \
                --query "NatGateways[0].NatGatewayId" --output text --region "${REGION}")
            fnat_list+=("${nat_id}")
        else
            echo "INFO ${prg}: NAT gateway is not present in AZ ${az}, creating"
            nat_subnet_id=$(check_subnet "${VPC_ID}" "${nat_sub_cidrs[0]}" "${az}" "${CLUSTER_NAME}-SubnetForNAT-${az}")
            if [[ "${nat_subnet_id}" != "None" ]]; then
                echo "INFO ${prg}: ID of existing NAT subnet $i in ${az} AZ: ${nat_subnet_id}"
            else
                echo "INFO ${prg}: Creating new subnet for hosting NAT gateway"
                nat_subnet_id=$(create_subnet "${VPC_ID}" "${nat_sub_cidrs[0]}" \
                    "${az}" "${CLUSTER_NAME}-SubnetForNAT-${az}")
                create_tags "${nat_subnet_id}" "Name=${CLUSTER_NAME}-SubnetForNAT-${az},Cluster=${CLUSTER_NAME},AZ=${az}"
                echo "INFO ${prg}: Created new subnet with ID ${nat_subnet_id} for hosting NAT gateway"
            fi
            nat_rtb_id=$(check_route_table "${CLUSTER_NAME}-RtbForNATSubnet-${az}" "${CLUSTER_NAME}")
            if [[ "${nat_rtb_id}" != "None" ]]; then
                echo "INFO ${prg}: Route table exists for NAT subnet"
            else
                nat_rtb_id=$(create_route_table "${VPC_ID}")
                create_tags "${nat_rtb_id}" "Name=${CLUSTER_NAME}-RtbForNATSubnet-${az},Cluster=${CLUSTER_NAME},AZ=${az}"
                create_route "${nat_rtb_id}" "0.0.0.0/0" "${igw_id}"
                create_subnet_rtb_association "${nat_subnet_id}" "${nat_rtb_id}"
                make_subnet_public "${nat_subnet_id}"
            fi

            eip_alloc_id=$(check_eip "${CLUSTER_NAME}-EIP-${az}" "${CLUSTER_NAME}")
            if [[ "${eip_alloc_id}" != "None" ]]; then
                echo "INFO ${prg}: elastic ip is present for NAT gateway to be created"
            else
                eip_alloc_id=$(aws ec2 allocate-address --domain vpc \
                    --query '{AllocationId:AllocationId}' --output text)
                create_tags "${eip_alloc_id}" "Name=${CLUSTER_NAME}-EIP-${az},Cluster=${CLUSTER_NAME},AZ=${az}"
            fi
            if [[ "${eip_alloc_id}" != "None" ]]; then
                nat_id=$(aws ec2 create-nat-gateway --subnet-id "${nat_subnet_id}" \
                    --allocation-id "${eip_alloc_id}" --query 'NatGateway.NatGatewayId' \
                    --output text --region "${REGION}")
                create_tags "${nat_id}" "Name=${CLUSTER_NAME}-NATGW-${az},Cluster=${CLUSTER_NAME},AZ=${az}"
                wait_for_nat_availability "${nat_id}" "AVAILABLE"
                exit_code="$?"
                if [[ "${exit_code}" != 0 ]]; then
                    echo "ERROR ${prg}: Error in creating NAT gateway"
                    exit 1
                fi
                echo "INFO ${prg}: NAT gateway created successfully with id ${nat_id}"
            fi
            fnat_list+=("${nat_id}")
            [[ ${#nat_sub_cidrs[@]} == 1 ]] && break
            nat_sub_cidrs=("${nat_sub_cidrs[@]:1}")
        fi
        [[ ${VPC_NAT_MODE} == "Single" ]] && [[ ${#fnat_list[@]} -ge 1 ]] && break
    done

    rtb_list=()
    for i in "${!fnat_list[@]}"; do
        echo "INFO ${prg}: Check for pre-existing private subnet route table"
        private_rtb_id=$(check_route_table "${CLUSTER_NAME}-RtbForPrivateSubnets-${i}" "${CLUSTER_NAME}")
        echo "INFO ${prg}: ID of existing private subnet route table: ${private_rtb_id}"
        if [[ "${private_rtb_id}" == "None" ]]; then
            echo "INFO ${prg}: Existing route table for private subnet not found. Creating new route table."
            private_rtb_id=$(create_route_table "${VPC_ID}")
            create_route "${private_rtb_id}" "0.0.0.0/0" "${fnat_list[$i]}"
            create_tags "${private_rtb_id}" "Name=${CLUSTER_NAME}-RtbForPrivateSubnets-${i},Cluster=${CLUSTER_NAME}"
        fi
        rtb_list+=("${private_rtb_id}")
    done

    IFS=' ' read -r -a pub_sub_cidrs <<< "$PUBLIC_SUBNET_CIDRS"
    IFS=' ' read -r -a pri_sub_cidrs <<< "$PRIVATE_SUBNET_CIDRS"


    # Optionally create public subnets, if public subnet CIDRs are specified
    if [[ "${#pub_sub_cidrs[@]}" != 0 ]]; then
        echo "INFO ${prg}: You have specified CIDRs for creating public subnets"
        cont="n"
        if [[ $FORCE == "n" ]]; then
            read -r -p "Do you want to create public subnets? (y/n) : " cont
        fi
        if [[ $FORCE == "y" || $cont == "y" ]]; then
            public_sub_cidrs=("${pub_sub_cidrs[@]:0:${NUM_AZS}}")
            echo "INFO ${prg}: Using public subnet cidrs  : ${public_sub_cidrs[*]}"
            if [[ "${#public_sub_cidrs[@]}" != "${NUM_AZS}" ]]; then
                echo "ERROR ${prg}: Please specify public subnet cidrs equal to number of AZs to deploy EKS control plane in."
                exit 1
            fi

            echo "INFO ${prg}: Check for pre-existing public subnet route table"
            public_rtb_id=$(check_route_table "${CLUSTER_NAME}-RtbForPublicSubnets" "${CLUSTER_NAME}")
            echo "INFO ${prg}: ID of existing public subnet route table: ${public_rtb_id}"
            if [[ "${public_rtb_id}" == "None" ]]; then
                echo "INFO ${prg}: Existing route table for public subnet not found. Creating new route table."
                public_rtb_id=$(create_route_table "${VPC_ID}")
                create_route "${public_rtb_id}" "0.0.0.0/0" "${igw_id}"
                create_tags "${public_rtb_id}" "Name=${CLUSTER_NAME}-RtbForPublicSubnets,Cluster=${CLUSTER_NAME}"
            fi

            public_subnet_ids=""
            echo "INFO ${prg}: Check for pre-existing public subnets"
            for i in "${!AvailabilityZones[@]}"; do
                subnet_id=$(check_subnet "${VPC_ID}" "${public_sub_cidrs[$i]}" "${AvailabilityZones[$i]}" "${CLUSTER_NAME}-PublicSubnet${i}")
                if [[ "${subnet_id}" != "None" ]]; then
                    echo "INFO ${prg}: ID of existing public subnet $i in ${AvailabilityZones[$i]} AZ: ${subnet_id}"
                else
                    echo "INFO ${prg}: Creating public subnet $i"
                    subnet_id=$(create_subnet "${VPC_ID}" "${public_sub_cidrs[$i]}" "${AvailabilityZones[$i]}" "${CLUSTER_NAME}-PublicSubnet${i}")
                    exit_code="$?"
                    if [[ "${exit_code}" != 0 ]]; then
                        echo "ERROR ${prg}: Error in creating public subnet ${i}: ${subnet_id}"
                        exit 1
                    fi
                    create_tags "${subnet_id}" "Name=${CLUSTER_NAME}-PublicSubnet${i},Cluster=${CLUSTER_NAME},kubernetes.io/role/elb=1"
                    create_subnet_rtb_association "${subnet_id}" "${public_rtb_id}"
                    make_subnet_public "${subnet_id}"
                    echo "INFO ${prg}: Public subnet ${subnet_id} created."
                fi
                public_subnet_ids="${public_subnet_ids}${subnet_id},"
            done
            public_subnets="${public_subnet_ids::-1}"
            params+=(--vpc-public-subnets="${public_subnets}")
        fi
    else
        echo "INFO ${prg}: Not creating public subnets as you have not specified CIDRs"
    fi

    private_sub_cidrs=("${pri_sub_cidrs[@]:0:${NUM_AZS}}")
    echo "INFO ${prg}: Using private subnet cidrs : ${private_sub_cidrs[*]}"

    if [[ "${#private_sub_cidrs[@]}" != "${NUM_AZS}" ]]; then
        echo "ERROR ${prg}: Please specify private subnet cidrs equal to number of AZs to deploy EKS control plane in."
        exit 1
    fi

    vpn_gws=""
    if [[ $ENABLE_ROUTE_PROPAGATION == "True" ]]; then
        echo "INFO ${prg}: You have opted to enable route propagation for VPN. This is required mainly when EKS cluster is a private cluster."
	echo "INFO ${prg}: Private subnet route tables will be configured with VPN routes for all VPN gateways"
	vpn_gws=$(aws ec2 describe-vpn-gateways --region "${REGION}" \
	    --filters Name=attachment.vpc-id,Values="${VPC_ID}" Name=state,Values="available" \
            --query 'VpnGateways[*].VpnGatewayId' --output text)
    fi
    IFS=' ' read -r -a vpn_gateways <<< "$vpn_gws"

    private_subnet_ids=""
    echo "INFO ${prg}: Check for pre-existing private subnets"
    for i in "${!AvailabilityZones[@]}"; do
        rtb_id="${rtb_list[0]}"
        [[ ${#rtb_list[@]} -gt 1 ]] && rtb_id="${rtb_list[${i}]}"

        subnet_id=$(check_subnet "${VPC_ID}" "${private_sub_cidrs[$i]}" "${AvailabilityZones[$i]}" "${CLUSTER_NAME}-PrivateSubnet${i}")
        if [[ "${subnet_id}" != "None" ]]; then
            echo "INFO ${prg}: ID of existing private subnet $i in ${AvailabilityZones[$i]} AZ: ${subnet_id}"
        elif [[ "${subnet_id}" == "None" ]]; then
            echo "INFO ${prg}: Creating private subnet $i"
            subnet_id=$(create_subnet "${VPC_ID}" "${private_sub_cidrs[$i]}" "${AvailabilityZones[$i]}" "${CLUSTER_NAME}-PrivateSubnet${i}")
            create_tags "${subnet_id}" "kubernetes.io/role/internal-elb=1,Name=${CLUSTER_NAME}-PrivateSubnet${i},Cluster=${CLUSTER_NAME}"
            create_subnet_rtb_association "${subnet_id}" "${rtb_id}"
            echo "INFO ${prg}: Private subnet ${subnet_id} created."
            if [[ $ENABLE_ROUTE_PROPAGATION == "True" ]] && [[ "${#vpn_gateways[@]}" != 0 ]]; then
                #shellcheck disable=SC2086
                enable_route_propagation "${rtb_id}" "${vpn_gateways[@]}"
            fi

        fi
        private_subnet_ids="${private_subnet_ids}${subnet_id},"
    done
    private_subnets="${private_subnet_ids::-1}"

    params+=(--vpc-private-subnets="${private_subnets}")
fi

[[ -n "${VPC_CIDR}" ]] && [[ -z "${private_subnets}" && -z "${public_subnets}" ]] && params+=(--vpc-cidr="${VPC_CIDR}")

if [[ -n "${VPC_NAT_MODE}" ]]; then
    params+=(--vpc-nat-mode="${VPC_NAT_MODE}")
fi
if [[ -n "${CLUSTER_VERSION}" ]]; then
    params+=(--version="${CLUSTER_VERSION}")
fi
if [[ -n "${AvailabilityZones[*]}" ]]; then
    [[ ! "${params[*]}" =~ --vpc-private-subnets=${private_subnets} ]]  && \
    [[ ! "${params[*]}" =~ --vpc-public-subnets=${public_subnets} ]] &&
    params+=(--zones="${AvailabilityZones// /,}")
fi

# Create EKS cluster
echo "INFO ${prg}: Check for pre-existing EKS cluster with name ${CLUSTER_NAME}"
check_cluster=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --query 'cluster.name' --output text 2> /dev/null)
if [[ "${check_cluster}" != "${CLUSTER_NAME}" ]]; then
    echo "INFO ${prg}: No pre-existing EKS cluster, creating new"
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to create EKS cluster? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        set -x
        eksctl create cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
            --without-nodegroup --asg-access \
            --full-ecr-access --external-dns-access \
            --alb-ingress-access --timeout "${STACK_CREATION_TIMEOUT}" \
            --tags "${TAGS}" \
            "${params[@]}" \
            --auto-kubeconfig
        exit_code="$?"
        set +x
        if [[ "${exit_code}" != 0 ]]; then
            echo "ERROR ${prg}: Failure in creating EKS cluster ${CLUSTER_NAME}"
            exit 1
        fi
        echo "INFO ${prg}: EKS cluster ${CLUSTER_NAME} created successfully"
    fi
else
    eksctl utils write-kubeconfig -c "${CLUSTER_NAME}" -r "${REGION}" --auto-kubeconfig
    exit_code="$?"
    if [[ ${exit_code} != 0 ]]; then
        echo "ERROR ${prg}: Error in writing kubeconfig for cluster"
        exit 1
    fi
    echo "INFO ${prg}: Found pre-existing EKS cluster."
fi

if [[ -n "${ALLOW_NETWORK_CIDRS}" ]]; then
    echo "INFO ${prg}: Updating security group for EKS control plane"
    ctrl_sg_id=$(aws ec2 describe-security-groups \
        --filters Name=tag:"aws:cloudformation:logical-id",Values=ControlPlaneSecurityGroup \
        Name=tag:alpha.eksctl.io/cluster-name,Values="${CLUSTER_NAME}" \
        Name=tag:Name,Values="eksctl-${CLUSTER_NAME}-cluster/ControlPlaneSecurityGroup" \
        --query 'SecurityGroups[0].GroupId' --output text)
    exit_code="$?"
    if [[ "${exit_code}" != 0 ]]; then
        echo "Exiting as command to check control plane security group failed"
        exit 1
    fi
    ctrl_sg_cidr_ip=$(aws ec2 describe-security-groups \
        --filters Name=tag:"aws:cloudformation:logical-id",Values=ControlPlaneSecurityGroup \
        Name=tag:alpha.eksctl.io/cluster-name,Values="${CLUSTER_NAME}" \
        Name=tag:Name,Values="eksctl-${CLUSTER_NAME}-cluster/ControlPlaneSecurityGroup" \
        --query 'SecurityGroups[0].IpPermissions[0].IpRanges' --output text | tr '\n' ' ')
    IFS=' ' read -r -a ctrl_sg_cidr_ip <<< "$ctrl_sg_cidr_ip"
    ip_ranges=""
    for cidr in ${ALLOW_NETWORK_CIDRS};
    do
        present=0
        for existing_cidr in "${ctrl_sg_cidr_ip[@]}"; do
            if [[ "${existing_cidr}" == "${cidr}" ]]; then
                present=1
                break
            fi
        done
        if [[ "${present}" -eq 0 ]]; then
            ip_ranges+="{CidrIp=$cidr},"
        fi
    done
    if [[ -n "${ip_ranges}" ]]; then
        aws ec2 authorize-security-group-ingress \
            --group-id "${ctrl_sg_id}" \
            --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges="[${ip_ranges}]"
        exit_code="$?"
        if [[ "${exit_code}" != 0 ]]; then
            echo "Error in updating control plane security group"
            exit 1
        fi
        echo "INFO ${prg}: Updated security group for EKS control plane"
    else
        echo "INFO ${prg}: Security group is already updated."
    fi
fi

kubeconfig="--kubeconfig=${HOME}/.kube/eksctl/clusters/${CLUSTER_NAME}"
# Configure pod networking
cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to update CNI plugin (optional) for ${CLUSTER_NAME}? (y/n) : " cont
fi
if [[ $FORCE == "y" || $cont == "y" ]]; then
    set -x
    amazon_k8s_cni1=$(kubectl "${kubeconfig}" describe daemonset aws-node --namespace kube-system | grep Image | grep "amazon-k8s-cni:" | cut -d "/" -f 2)
    set +x
    current_cni_version=$(echo "$amazon_k8s_cni1" | cut -d':' -f2)
    if [[ "${current_cni_version}" != "v${CNI_VERSION}" ]]; then
        echo "INFO ${prg}: Configuring pod networking for EKS cluster"
        cni_major_version=$(echo "${CNI_VERSION}" | cut -d'.' -f-2)
        kubectl "${kubeconfig}" apply -f "https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/v${CNI_VERSION}/config/v${cni_major_version}/aws-k8s-cni.yaml" > /dev/null
        exit_code="$?"
        if [[ ${exit_code} != 0 ]]; then
            echo "ERROR ${prg}: Error in updating CNI plugin for EKS cluster"
            exit 1
        fi
        echo "INFO ${prg}: Updated amazon-k8s-cni version to: ${CNI_VERSION}"
    else
        echo "INFO ${prg}: Requested CNI version is already present in cluster"
    fi
fi

echo "INFO ${prg}: Updating Warm IP target to ${WARM_IP_TARGET}"
cp --preserve=all reference/warm_ip_target.yaml "${K8S_GENESIS_CONF_DIR}/warm_ip_target.yaml"
sed -i "s#value: \"[[:digit:]]\+\"#value: \"${WARM_IP_TARGET}\"#g" "${K8S_GENESIS_CONF_DIR}/warm_ip_target.yaml"
warm_ip_target_content=$(cat "${K8S_GENESIS_CONF_DIR}/warm_ip_target.yaml")
kubectl "${kubeconfig}" patch daemonset -n kube-system aws-node --patch "${warm_ip_target_content}" > /dev/null
echo "INFO ${prg}: Patched aws-node daemonset with WARM_IP_TARGET set ${WARM_IP_TARGET}"

cluster_ep_access=$(aws eks describe-cluster --name "${CLUSTER_NAME}" \
    --query '[cluster.resourcesVpcConfig.endpointPrivateAccess,cluster.resourcesVpcConfig.endpointPublicAccess]' \
    --output text --region "${REGION}")
# shellcheck disable=SC2086
priv_access=$(echo ${cluster_ep_access} | cut -d' ' -f1)
# shellcheck disable=SC2086
pub_access=$(echo ${cluster_ep_access} | cut -d' ' -f2)
resource_vpc_config=""
if [[ -n "$ENABLE_PRIVATE_ACCESS" ]] && [[ ${ENABLE_PRIVATE_ACCESS} == "${priv_access}" ]]; then
    echo "INFO ${prg}: Private endpoint access for cluster is already set to $ENABLE_PRIVATE_ACCESS"
else
    priv_access="$ENABLE_PRIVATE_ACCESS"
    echo "INFO ${prg}: Private endpoint access for cluster needs to be changed to ${priv_access}"
    resource_vpc_config="${resource_vpc_config}endpointPrivateAccess=${priv_access},"
fi
if [[ -n "${ENABLE_PUBLIC_ACCESS}" ]] && [[ "${ENABLE_PUBLIC_ACCESS}" == "${pub_access}" ]]; then
    echo "INFO ${prg}: Public endpoint access for cluster is already set to $ENABLE_PUBLIC_ACCESS"
else
    pub_access="${ENABLE_PUBLIC_ACCESS}"
    echo "INFO ${prg}: Public endpoint access for cluster needs to be changed to ${pub_access}"
    resource_vpc_config="${resource_vpc_config}endpointPublicAccess=${pub_access}"
fi

if [[ ${resource_vpc_config} != "" ]]; then
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to update cluster endpoint accesses? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Updating endpoint access for cluster"
        update_id=$(aws eks update-cluster-config --name "${CLUSTER_NAME}" \
            --resources-vpc-config endpointPrivateAccess="${priv_access}",endpointPublicAccess="${pub_access}" \
            --query 'update.id' --output text)
        if [[ $update_id == "" ]]; then
            echo "ERROR ${prg}: Error in updating endpoint access config for cluster"
            exit 1
        fi
        wait_for_eks "${CLUSTER_NAME}" "SUCCESSFUL" "${update_id}"
        exit_code="$?"
        if [[ "${exit_code}" != 0 ]]; then
            echo "ERROR ${prg}: Error in updating endpoint access config for cluster"
            exit 1
        fi
        echo "INFO ${prg}: endpoint access parameters updated successfully"
    fi
fi

if [[ -n "$PUBLIC_ACCESS_CIDRS" ]] && [[ $pub_access == "True" ]]; then
    echo "INFO ${prg}: Allowing ${PUBLIC_ACCESS_CIDRS} to access cluster API server"
    eksctl utils set-public-access-cidrs -c "${CLUSTER_NAME}" -r "${REGION}" "$PUBLIC_ACCESS_CIDRS" --approve
    exit_code="$?"
    if [[ $exit_code != 0 ]]; then
        echo "ERROR ${prg}: Error in updating public endpoint restrictions for cluster"
        exit 1
    fi
    echo "INFO ${prg}: Public Endpoint Restrictions for cluster have been updated to ${PUBLIC_ACCESS_CIDRS}"
fi

if [[ -n "${ENABLE_LOGGING_TYPES}" ]] || [[ -n "${DISABLE_LOGGING_TYPES}" ]]; then
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to update EKS cluster to enable logging? (y/n) : " cont
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        echo "INFO ${prg}: Updating logging levels for cluster"
        logging_types=""
        [[ -n "${ENABLE_LOGGING_TYPES}" ]] && logging_types+="--enable-types=${ENABLE_LOGGING_TYPES} "
        [[ -n "${DISABLE_LOGGING_TYPES}" ]] && logging_types+="--disable-types=${DISABLE_LOGGING_TYPES} "
        # shellcheck disable=SC2086
        eksctl utils update-cluster-logging -c "${CLUSTER_NAME}" ${logging_types} --approve
        exit_code="$?"
        if [[ "${exit_code}" != 0 ]]; then
            echo "ERROR ${prg}: Error in updating logging types for cluster"
        fi
        echo "INFO ${prg}: Logging parameters updated successfully"
    fi
fi

cont="n"
if [[ $FORCE == "n" ]]; then
    read -r -p "Do you want to update IAM properties for cluster? (y/n) : " cont
fi
if [[ $FORCE == "y" || $cont == "y" ]]; then
    echo "INFO ${prg}: Updating IAM properties of cluster"
    if [[ -r "${K8S_GENESIS_CONF_DIR}/iam_serviceaccounts.yaml" ]]; then
        echo "INFO ${prg}: Enabling IAM OpenID Connect Provider (OIDC)"
        eksctl utils associate-iam-oidc-provider --cluster "${CLUSTER_NAME}" -r "${REGION}" --approve
        exit_code="$?"
        if [[ "${exit_code}" != 0 ]]; then
            echo "Error in enabling IAM OpenID Connect Provider(OIDC)"
            exit 1
        fi
        echo "INFO ${prg}: Enabled IAM OpenID Connect Provider (OIDC) Provider"
        echo "INFO ${prg}: Creating service accounts for cluster. This will create IAM roles for existing serviceaccounts and update the serviceaccount"
        eksctl create iamserviceaccount --config-file "${K8S_GENESIS_CONF_DIR}/iam_serviceaccounts.yaml" --override-existing-serviceaccounts --approve
        exit_code="$?"
        if [[ "${exit_code}" != 0 ]]; then
            echo "Error in creating service accounts for cluster"
            exit 1
        fi
        echo "INFO ${prg}: Created service accounts for cluster"
    fi
fi

while true; do
    cont="n"
    if [[ $FORCE == "n" ]]; then
        read -r -p "Do you want to add IAM users to control access to cluster? (y/n) : " cont
    fi
    if [[ $cont == "n" ]]; then
	echo "INFO ${prg}: Exiting as process to add IAM users is completed" && break
    fi
    if [[ $FORCE == "y" || $cont == "y" ]]; then
        read -r -p "Enter Account ID to automatically map to its username: " acc_id
        read -r -p "User name within Kubernetes to map to IAM role: " username
        read -r -p "Enter Group within Kubernetes to which IAM role is mapped : " group
        read -r -p "Enter Service name; valid value: emr-containers: " service_name
        read -r -p "Enter Namespace in which to create RBAC resources (only valid with --service-name): " namespace
        read -r -p "Enter ARN of the IAM role or user to create: " arn
        iamidmapping=""
        [[ -n $acc_id ]] && iamidmapping+="--account=${acc_id} "
        [[ -n $username ]] && iamidmapping+="--username=${username} "
        [[ -n $group ]] && iamidmapping+="--group=${group} "
        [[ -n $service_name ]] && iamidmapping+="--service-name=${service_name} "
        [[ -n $namespace ]] && iamidmapping+="--namespace=${namespace} "
        [[ -n $arn ]] && iamidmapping+="--arn=${arn} "
        # shellcheck disable=SC2086
        eksctl create iamidentitymapping --cluster "${CLUSTER_NAME}" -r "${REGION}" ${iamidmapping}
        exit_code="$?"
        if [[ "${exit_code}" != 0 ]]; then
            echo "Error in creating service accounts for cluster"
            exit 1
        fi
    fi
done
