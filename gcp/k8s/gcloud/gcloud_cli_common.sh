#!/bin/bash

get_cluster_subnet_ip_ranges(){
    subnet_name="${1}"
    region="${2}"
    subnet_pod_range_name=$(gcloud compute networks subnets describe "${subnet_name}" \
        --region="${region}" | grep -E "gke-.*pods" | cut -d":" -f2 | tr -d "[:space:]")

    subnet_services_range_name=$(gcloud compute networks subnets describe "${subnet_name}" \
        --region="${region}" | grep -E "gke-.*services" | cut -d":" -f2 | tr -d "[:space:]")

    params="${subnet_name},"
    if [[ "${NETWORK_NAT_ALLOW_SUBNET_SECONDARY_IPS}" == "true" ]]; then
        params+="${subnet_name}:${subnet_pod_range_name},${subnet_name}:${subnet_services_range_name},"
    fi
    echo "${params}"
}

check_existing_nat() {
    router="${1}"
    region="${2}"
    nat_name="${3}"
    existing_nat=$(gcloud compute routers nats list --router="${router}" \
        --region="${region}" --format='value(name)' | grep "${nat_name}")
    echo "${existing_nat}"
}

describe_nat() {
    nat_name="${1}"
    router="${2}"
    region="${3}"
    project="${4}"
    flatten="${5}"
    format="${6}"
    nat=$(gcloud compute routers nats describe "${nat_name}" --router "${router}" \
        --region "${region}" --project "${project}" --flatten="${flatten}" --format="${format}")
    echo "${nat}"
}

check_existing_router() {
    router="${1}"
    region="${2}"
    project="${3}"
    check_router=$(gcloud compute routers list \
        --project "${project}" \
        --filter="name=( ${router} ) AND region:( ${region} )" --format="value(name)")
    echo "${check_router}"
}

prep_subnet_cidrs_nat() {
    existing_nat_subnets="${1}"
    region="${2}"
    project="${3}"
    params=""
    while IFS="," read -r subnet range_type range_name; do
        if [[ $range_type == "ALL_IP_RANGES" ]]; then
            params="${params}${subnet},"
            subnet_secondary_ranges=$(gcloud compute networks subnets describe "${subnet}" --region="${region}" \
                --project "${project}" --flatten="secondaryIpRanges[]" --format="csv[no-heading](secondaryIpRanges.rangeName)")
            # shellcheck disable=SC2068
            for i in ${subnet_secondary_ranges[@]}; do
                params="${params}${subnet}:${i},"
            done
        fi
        if [[ $range_type == *PRIMARY_IP_RANGE* ]]; then
            params="${params}${subnet},"
        fi
        if [[ $range_type == *LIST_OF_SECONDARY_IP_RANGES* ]]; then
            range_name=${range_name//;/ }
            # shellcheck disable=SC2068
            for i in ${range_name[@]}; do
                params="${params}${subnet}:${i},"
            done
        fi
    done <<< "${existing_nat_subnets}"
    echo "${params}"
}
