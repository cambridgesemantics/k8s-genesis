#!/bin/bash

###########################################################
# Copyright (c) 2016-2021 Cambridge Semantics Incorporated.
# All rights reserved.
###########################################################

wait_for_nat_availability() {
  state="PENDING"
  wait_count=0
  desired_state="${2}"

  while [[ "${wait_count}" -le "${WAIT_DURATION}" ]]; do
    state=$(aws ec2 describe-nat-gateways --nat-gateway-ids "${1}" \
        --query 'NatGateways[*].{State:State}' --output text )
    state=$(echo "${state}" | tr '[:lower:]' '[:upper:]')
    [[ "${state}" == "${desired_state}" ]] && break
    sleep "${WAIT_INTERVAL}"
    wait_count=$(( wait_count + WAIT_INTERVAL ))
  done
  [[ "${state}" == "${desired_state}" ]] && return 0 || exit 1
}

wait_for_eks() {
  state=""
  wait_count=0
  desired_state="${2}"
  update_id="${3}"

  while [[ "${wait_count}" -le "${WAIT_DURATION}" ]]; do
    state=$(aws eks describe-update --name "${1}" --update-id "${update_id}"\
        --query 'update.status' --output text )
    state=$(echo "${state}" | tr '[:lower:]' '[:upper:]')
    echo "Current cluster state: ${state}"
    [[ "${state}" == "${desired_state}" ]] || [[ "${state}" == "" ]] && break
    sleep "${WAIT_INTERVAL}"
    wait_count=$(( wait_count + WAIT_INTERVAL ))
  done
  if [[ "${state}" == "${desired_state}" ]]; then
      echo "EKS cluster is in desired state"
      return 0
  else
      echo "EKS cluster is not in desired state"
      return 1
  fi
}

check_subnet() {
  subnet_id=$(aws ec2 describe-subnets \
      --filters Name=vpc-id,Values="${1}" Name=cidr-block,Values="${2}" Name=availability-zone,Values="${3}" \
      Name=tag:Name,Values="${4}" \
      --query 'Subnets[0].SubnetId' --output text)
  exit_code="$?"
  if [[ "${exit_code}" != 0 ]]; then
      echo "Exiting as command to check subnet failed"
      exit 1
  fi
  echo "${subnet_id}"
}

create_subnet() {
  subnet_id=$(aws ec2 create-subnet --vpc-id "${1}" --cidr-block "${2}" --availability-zone "${3}" \
      --query 'Subnet.SubnetId' --output text)
  exit_code="$?"
  if [[ "${exit_code}" != 0 ]]; then
      echo "Exiting as command to create subnet failed"
      exit 1
  fi
  echo "${subnet_id}"
}

check_route_table() {
  route_table_id=$(aws ec2 describe-route-tables \
    --filters Name=tag:Name,Values="$1" Name=tag:Cluster,Values="$2" \
    --query 'RouteTables[0].RouteTableId' --output text)
  exit_code="$?"
  if [[ "${exit_code}" != 0 ]]; then
      echo "Exiting as command to check route table failed"
      exit 1
  fi
  echo "${route_table_id}"
}

create_route_table() {
  route_table_id=$(aws ec2 create-route-table --vpc-id "${1}" \
    --query 'RouteTable.RouteTableId' --output text)
  exit_code="$?"
  if [[ "${exit_code}" != 0 ]]; then
      echo "Exiting as command to create route table failed"
      exit 1
  fi
  echo "${route_table_id}"
}


create_route() {
  aws ec2 create-route --route-table-id "${1}" \
    --destination-cidr-block "${2}" --gateway-id "${3}" --output text > /dev/null
  exit_code="$?"
  if [[ "${exit_code}" != 0 ]]; then
      echo "Exiting as command to create route failed"
      exit 1
  fi
}


create_subnet_rtb_association() {
  aws ec2 associate-route-table --subnet-id "${1}" \
    --route-table-id "${2}" --output text
  exit_code="$?"
  if [[ "${exit_code}" != 0 ]]; then
      echo "Exiting as command to add subnet to route failed"
      exit 1
  fi
}


make_subnet_public() {
  aws ec2 modify-subnet-attribute --subnet-id "${1}" \
    --map-public-ip-on-launch --output text
  exit_code="$?"
  if [[ "${exit_code}" != 0 ]]; then
      echo "Exiting as command to modify vpc attribute failed"
      exit 1
  fi
}

create_tags() {
  tagString=""
  all_tags=("${2//,/ }")
  # shellcheck disable=SC2128
  IFS=' ' read -r -a all_tags <<< "${all_tags}"
  for i in "${all_tags[@]}";
  do
      tag=("${i//=/ }")
      # shellcheck disable=SC2128
      IFS=' ' read -r -a tag <<< "${tag}"
      tagString+="Key=${tag[0]},Value=${tag[1]} "
  done
  IFS=' ' read -r -a tagString <<< "$tagString"
  aws ec2 create-tags --resources "${1}" --tags "${tagString[@]}"
  exit_code="$?"
  if [[ "${exit_code}" != 0 ]]; then
      echo "Exiting as command to add tags to resource ${1} failed"
      exit 1
  fi
}

delete_nat() {
  eip=$(aws ec2 describe-nat-gateways --nat-gateway-id="${1}" \
                       --query 'NatGateways[*].NatGatewayAddresses[*].AllocationId' --output text)
  aws ec2 delete-nat-gateway --nat-gateway-id="${1}"
  wait_for_nat_availability "${1}" "DELETED"
  exit_code="$?"
  if [[ "${exit_code}" == 0 ]]; then
    echo "Releasing elastic ip ${eip}"
    aws ec2 release-address --allocation-id "${eip}"
    echo "Released elastic ip ${eip}"
  else
    echo "Problem in deleting NAT gateway"
    exit 1
  fi
}

delete_subnet() {
  aws ec2 delete-subnet --subnet-id="${1}"
}

delete_route_table() {
  aws ec2 delete-route-table --route-table-id="${1}"
}

check_eip() {
  eip=$(aws ec2 describe-addresses \
    --filters Name=tag:Name,Values="$1" Name=tag:Cluster,Values="$2" \
    --query 'Addresses[0].AllocationId' --output text)
  exit_code="$?"
  if [[ "${exit_code}" != 0 ]]; then
      echo "Exiting as command to check elastic ip allocation failed"
      exit 1
  fi
  echo "${eip}"
}

enable_route_propagation() {
  rtb="${1}"
  vpn_gw_list="${2}"
  if [[ "${#vpn_gw_list[@]}" != 0 ]]; then
      for i in "${!vpn_gw_list[@]}"; do
          aws ec2 enable-vgw-route-propagation --route-table-id "${rtb}" --gateway-id "${vpn_gw_list[${i}]}"
      done
  fi
}
