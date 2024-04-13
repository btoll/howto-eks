#!/bin/bash

# Taken from https://aws.github.io/aws-eks-best-practices/upgrades/#verify-available-ip-addresses

set -eo pipefail

LANG=C
umask 0022

usage() {
    echo "Usage: $0 --addon kube-proxy --version 1.29"
    echo
    echo "Args:"
    echo "-a, --addon    : The name of the addon."
    echo "-v, --version  : The Kubernetes version."
    echo "-h, --help     : Show usage."
    exit "$1"
}

while [ "$#" -gt 0 ]
do
    OPT="$1"
    case $OPT in
        -a|--addon) shift; ADDON=$1 ;;
        -h|--help) usage 0 ;;
        -v|--version) shift; VERSION=$1 ;;
        *) echo "Unknown flag $1"; usage 1 ;;
    esac
    shift
done

if [ -z "$ADDON" ] || [ -z "$VERSION" ]
then
    echo "[ERROR] Please provide both an \`ADDON\` and a \`VERSION\`."
    usage 1
fi

#cluster_info="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query 'cluster.resourcesVpcConfig.subnetIds' --output text)"
aws eks describe-addon-versions --kubernetes-version "$VERSION" --addon-name "$ADDON" \
    --query 'addons[].addonVersions[].{Version: addonVersion, "Default Version": compatibilities[0].defaultVersion}' --output table

