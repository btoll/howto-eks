#!/bin/bash
#shellcheck disable=2086

# Taken from https://aws.github.io/aws-eks-best-practices/upgrades/#verify-available-ip-addresses

set -eo pipefail

LANG=C
umask 0022

usage() {
    echo "Usage: $0 --cluster kilgore-trout-was-here --region eu-west-1"
    echo
    echo "Args:"
    echo "-c, --cluster  : The name of the cluster. Must confirm to DNS naming rules."
    echo "                 Default to the value of \`kubectl config current-context\`."
    echo "-r, --region   : The name of the region in which the cluster resides."
    echo "                 Defaults to \`ca-central-1\`."
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
        *) echo "Unknown flag $1"; usage 1 ;;
    esac
    shift
done

CLUSTER="${CLUSTER:-$(kubectl config current-context)}"
REGION="${REGION:-ca-central-1}"

ROLE_ARN="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.roleArn --output text)"
aws iam get-role --role-name "${ROLE_ARN##*/}" --query 'Role.AssumeRolePolicyDocument'

# It should display something like the following:
#{
#    "Version": "2012-10-17",
#    "Statement": [
#        {
#            "Effect": "Allow",
#            "Principal": {
#                "Service": "eks.amazonaws.com"
#            },
#            "Action": "sts:AssumeRole"
#        }
#    ]
#}

