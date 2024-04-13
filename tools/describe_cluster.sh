#!/bin/bash
#shellcheck disable=2060

set -eo pipefail

LANG=C
umask 0022

usage() {
    echo "Usage: $0 --cluster kilgore-trout-was-here --region eu-west-1"
    echo
    echo "Args:"
    echo "-c, --cluster  : The name of the cluster. Must confirm to DNS naming rules."
    echo "                 Defaults to the value of \`kubectl config current-context\`."
    echo "-r, --region   : The name of the region in which the cluster resides."
    echo "                 Defaults to \`ca-central-1\`."
    echo "-v             : Print additional information about the cluster (\`-vv\` for"
    echo "                 even more verbosity)."
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
        -vv) VERBOSE=2 ;;
        -v) VERBOSE=1 ;;
        *) echo "Unknown flag $1"; usage 1 ;;
    esac
    shift
done

function get {
    local blob="$1"
    local label="$2"
    local key="$3"
    printf "%-22s %-s\n" "$label" "$(echo "$blob" | jq -r "$key")"
}

function get_labels {
    # Sadly, `eksctl get labels` does not allow for setting `--output` like the other `get` commands.
    local nodegroup="$1"
    local labels
    labels=$(eksctl get labels \
        --cluster "$CLUSTER" \
        --region "$REGION" \
        --nodegroup "$nodegroup" \
        | awk 'NR!=1 {print $3}')   # NR!=1 skips the first line (the headers).
    printf "%s" "$labels"
}

KUBECONFIG_CLUSTER=$(kubectl config current-context)
CLUSTER="${CLUSTER:-$KUBECONFIG_CLUSTER}"
REGION="${REGION:-ca-central-1}"

cluster_info=$(eksctl get cluster --name "$CLUSTER" --region "$REGION" --output json)
addons=$(eksctl get addons --cluster "$CLUSTER" --region "$REGION" --verbose 0 --output json)
addon_names="$(echo "$addons" | jq -r '.[].Name')"
is_ebs_encrypted=$(aws ec2 get-ebs-encryption-by-default --region "$REGION" --query "EbsEncryptionByDefault" --output text)

printf "%-22s %-s\n" Cluster "$CLUSTER"
printf "%-22s %-s\n" Region "$REGION"
get "$cluster_info" Version .[].Version
get "$cluster_info" "Service CIDR" .[].KubernetesNetworkConfig.ServiceIpv4Cidr
printf "%-22s %-s\n" Addons "$(echo "$addon_names" | tr \\n ,)"
get "$cluster_info" "Role ARN" .[].RoleArn
get "$cluster_info" "OIDC Provider" .[].Identity.Oidc.Issuer
printf "%-22s %-s\n" "EBS Encrypted" "$is_ebs_encrypted"
#get "$cluster_info" "Cluster Logging" .[].Logging.ClusterLogging[].Enabled

# Enable decryption by default:
# aws ec2 enable-ebs-encryption-by-default --region "$REGION"

# https://eksctl.io/usage/iam-identity-mappings/
# EKS clusters use IAM users and roles to control access to the cluster. The rules are implemented in a config map called `aws-auth`.
# `eksctl` provides commands to read and edit this config map.

# Get all identity mappings:
# eksctl get iamidentitymapping --cluster kilgore-trout-was-here --region eu-west-1

nodegroups=$(eksctl get nodegroups --cluster "$CLUSTER" --region "$REGION" --output json)
nodegroup_names=$(echo "$nodegroups" | jq -r '.[].Name')
if [[ "$VERBOSE" -eq 0 ]]
then
    printf "\n"
    # If you double quote `$nodegroups`, it will not word split, and the loop will only run once.
    for nodegroup in $nodegroup_names
    do
        printf "%-12s %-s\n" Nodegroup "$nodegroup"
        printf "%-12s %-s\n\n" Labels "$(get_labels "$nodegroup")"
    done
fi

if [[ "$VERBOSE" -gt 0 ]]
then
    for nodegroup in $nodegroup_names
    do
        printf "\n"
        ng_info="$(echo "$nodegroups" | jq -c '.[] | select(.Name | contains('\""$nodegroup"\"'))')"
        printf "%-s:\n" NodeGroup
        get "$ng_info" Name .Name
        printf "%-22s %-s\n" Labels "$(get_labels "$nodegroup")"
        get "$ng_info" Version .Version
        get "$ng_info" Status .Status
        get "$ng_info" "Min Size" .MinSize
        get "$ng_info" "Max Size" .MaxSize
        get "$ng_info" "Desired Size" .DesiredCapacity
        get "$ng_info" "Instance Types" .InstanceType
        get "$ng_info" "AMI Type" .ImageID
        get "$ng_info" "Node Role ARN" .NodeInstanceRoleARN
        get "$ng_info" "ASG Name" .AutoScalingGroupName

        # Just print the node names.
        # If you get connection refused errors here, make sure that the current context (kubeconfig)
        # matches that of the cluster name passed to this script.
        nodes=$(kubectl get no -l eks.amazonaws.com/nodegroup="$nodegroup" -ojsonpath='{.items[*].metadata.name}')
        if [ -n "$nodes" ]
        then
            echo -e "Nodes:\n$(echo "$nodes" | tr [:space:] \\n)"
        else
            printf "%-s %-s\n" "No nodes found when querying cluster" "$KUBECONFIG_CLUSTER"
        fi
        #        echo "Get all pods on the nodes in the nodegroup in all namespaces:"
        #        echo -e "for node in $nodes\ndo\nkubectl get po -A --field-selector spec.nodeName="'$node'" -owide; echo\ndone\n"
    done

    if [ -z "$addons" ]
    then
        printf "[INFO] There are no managed addons.\n"
    else
        if [[ "$VERBOSE" -gt 1 ]]
        then
            for addon_name in $(echo "$addons" | jq -r '.[].Name')
            do
                # eksctl get addons \
                #     --cluster production-compliancepro-cacentral1 \
                #     --region ca-central-1 \
                #     --verbose 0 --output json \
                #     | jq '.[] | select(.Name | contains("vpc-cni"))'
                addon="$(echo "$addons" | jq -c '.[] | select(.Name | contains('\""$addon_name"\"'))')"
                printf "\n"
                get "$addon" "Addon name" .Name
                get "$addon" Version .Version
                get "$addon" "Newer Version" .NewerVersion
                get "$addon" "IAM Role" .IAMRole
                get "$addon" Status .Status
                get "$addon" "Configuration Values" .ConfigurationValues
                get "$addon" Issues .Issues
            done
        fi
    fi
fi

# Just print the namespaces.
#namespaces=$(kubectl get ns -ojsonpath='{.items[*].metadata.name}' | tr [:space:] \\n)
#echo -e "Namespaces:\n$namespaces\n"

