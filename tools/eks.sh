#!/bin/bash

# https://github.com/eksctl-io/eksctl/issues/4478
# https://stackoverflow.com/questions/70201235/correct-way-of-using-eksctl-clusterconfig-with-vpc-cni-addon-and-pass-maxpodsper

set -eo pipefail
LANG=C
umask 0022

usage() {
    echo "Usage: $0 --cluster kilgore-trout-was-here --region eu-west-1 --version 1.29"
    echo
    echo "Args:"
    echo "-c, --cluster  : The name of the cluster. Must confirm to DNS naming rules."
    echo "-r, --region   : The name of the region in which the cluster resides."
    echo "-v, --version  : The version of Kubernetes to upgrade to."
    echo "-h, --help     : Show usage."
    exit "$1"
}
while [ "$#" -gt 0 ]
do
    OPT="$1"
    case $OPT in
        -c|--cluster) shift; CLUSTER=$1 ;;
        -h|--help) usage 0 ;;
        -r|--region) shift; REGION=$1 ;;
        -v|--version) shift; VERSION=$1 ;;
        *) echo "Unknown flag $1"; usage 1 ;;
    esac
    shift
done

if [ -z "$CLUSTER" ] || [ -z "$REGION" ] || [ -z "$VERSION" ]
then
    echo "Must provide CLUSTER, REGION and VERSION."
    usage 1
fi

eksctl upgrade cluster --name "$CLUSTER" --region "$REGION" --version "$VERSION" --approve

for addon in update-aws-node update-coredns update-kube-proxy
do
    eksctl utils $addon --cluster "$CLUSTER" --region "$REGION" --approve
done

eksctl upgrade nodegroup --name "infra-1" --cluster "$CLUSTER" --region "$REGION" --kubernetes-version "$VERSION"

