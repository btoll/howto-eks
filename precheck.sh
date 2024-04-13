#!/bin/bash
#shellcheck disable=2086

set -eo pipefail

LANG=C
umask 0022

usage() {
    echo "Usage: $0 --cluster kilgore-trout-was-here --region eu-west-1"
    echo
    echo "Args:"
    echo "--approve      : Run the script without prompting (synonym of \`yes\`)."
    echo "-c, --cluster  : The name of the cluster. Must confirm to DNS naming rules."
    echo "                 Defaults to the value of \`kubectl config current-context\`."
    echo "--dry-run      : Don't create the \`update\` script."
    echo "-o, --output   : Write the \`update\` script to a location other than \`/tmp\`."
    echo "--prompt       : Will ask to approve and run the generated script."
    echo "-r, --region   : The name of the region in which the cluster resides."
    echo "                 Defaults to \`ca-central-1\`."
    echo "--yes          : Run the script without prompting (synonym of \`approve\`."
    echo "-h, --help     : Show usage."
    exit "$1"
}

while [ "$#" -gt 0 ]
do
    OPT="$1"
    case $OPT in
        --approve|--yes) YES=1 ;;
        -c|--cluster) shift; CLUSTER=$1 ;;
        --dry-run) DRYRUN=1 ;;
        -h|--help) usage 0 ;;
        -o|--output) shift; OUTPUT=$1 ;;
        --prompt) PROMPT=1 ;;
        -r|--region) shift; REGION=$1 ;;
        *) echo "Unknown flag $1"; usage 1 ;;
    esac
    shift
done

# https://eksctl.io/usage/addon-upgrade/
DEFAULT_ADDONS="aws-node coredns kube-proxy"

CLUSTER="${CLUSTER:-$(kubectl config current-context)}"
REGION="${REGION:-ca-central-1}"

# NOTE: We need to make sure we're on the correct cluster.  Just setting the `--cluster`
# option in the shell script isn't enough, we need to tell `kubectl` to use the correct
# cluster.
# Operations like `kubent` will run against the wrong cluster leading to bugs.
# `eksctl` commands don't suffere from since we're specifying the cluster and and the
# region in each invocation.
if ! kubectl config use-context "$CLUSTER"
then
    exit 1
fi

function verify_iam_role {
    # Verify this EKS IAM role:
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
    local role_arn
    role_arn="$(eksctl get cluster --name "$CLUSTER" --region "$REGION" --output json | jq -r '.[].RoleArn')"

    local role
    role="$(aws iam get-role --role-name "${role_arn##*/}" --query Role.AssumeRolePolicyDocument --output json)"

    local valid=0

    if [ 2012-10-17 != "$(echo "$role" | jq -r '.Version')" ]
    then
        valid=1
    fi
    if [ $valid -eq 0 ] && [ Allow != "$(echo "$role" | jq -r '.Statement[0].Effect')" ]
    then
        valid=1
    fi
    if [ $valid -eq 0 ] && [ eks.amazonaws.com != "$(echo "$role" | jq -r '.Statement[0].Principal.Service')" ]
    then
        valid=1
    fi
    if [ $valid -eq 0 ] && [ sts:AssumeRole != "$(echo "$role" | jq -r '.Statement[0].Action')" ]
    then
        valid=1
    fi

    return $valid
}

if [ -z "$DRYRUN" ]
then
    if [ -n "$OUTPUT" ]
    then
        UPGRADE_SCRIPT="$OUTPUT"
    else
        UPGRADE_SCRIPT=$(mktemp -t upgrade.sh_XXXXXXXX)
    fi
    exec 5> $UPGRADE_SCRIPT
fi

cluster_info="$(eksctl get cluster --name "$CLUSTER" --region "$REGION" --output json)"
control_plane_version=$(echo "$cluster_info" | jq -r '.[].Version')

minor_version="${control_plane_version##*.}"
upgrade_version="1.$(("$minor_version"+1))"

if [ -z "$DRYRUN" ]
then
    exec 5> $UPGRADE_SCRIPT
fi

cluster_info="$(eksctl get cluster --name "$CLUSTER" --region "$REGION" --output json)"
control_plane_version=$(echo "$cluster_info" | jq -r '.[].Version')

minor_version="${control_plane_version##*.}"
upgrade_version="1.$(("$minor_version"+1))"

if [ -z "$DRYRUN" ]
then
cat << EOF >&5
#!/bin/bash
set -euo pipefail
LANG=C
umask 0022

eksctl upgrade cluster --name "$CLUSTER" --region "$REGION" --version "$upgrade_version" --approve
EOF
fi

SUCCEEDED=0
KUBENT_CHECK=0
VERSION_CHECK=0
AVAILABLE_IPS_CHECK=0

printf "Checking addons...\n"

addons=$(eksctl get addons --cluster "$CLUSTER" --region "$REGION" --verbose 0 --output json)
if [ -z "$addons" ]
then
    printf "[INFO] There are no managed addons.\n"
else
    if [ -z "$DRYRUN" ]
    then
        printf "\n" >&5
    fi
    for addon_name in $(echo "$addons" | jq -r '.[].Name')
    do
        addon="$(echo "$addons" | jq -c '.[] | select(.Name | contains('\""$addon_name"\"'))')"
        # Detailed addon information can be gotten from `describe_cluster.sh`, so I'm torn about
        # doing it again here because I'm leaning towards having minimal output for this script
        # (and no VERBOSE option).
        # Leaving it here and commented for now.
        #
#        printf "[ADDON] [%s]\n" "$addon_name"
#        printf "\tCurrent: %s\n" "$(echo "$addon" | jq -r '.Version')"
#        newer_versions=$(echo "$addon" | jq -r '.NewerVersion')
#        if [ -z "$newer_versions" ]
#        then
#            printf "\t  Newer: Up-to-date\n\n"
#        else
#            printf "\t  Newer: %s\n\n" "$newer_versions"
#            if [[ "$DEFAULT_ADDONS" =~ $addon_name ]]
#            then
#                if [ -z "$DRYRUN" ]
#                then
#                    printf 'eksctl utils update-%s --cluster "%s" --region "%s" --approve\n' "$addon_name" "$CLUSTER" "$REGION" >&5
#                fi
#            fi
#        fi
#
        printf "[ADDON] %s\n" "$addon_name"
        newer_versions=$(echo "$addon" | jq -r '.NewerVersion')
        if [ -n "$newer_versions" ]
        then
            if [[ "$DEFAULT_ADDONS" =~ $addon_name ]]
            then
                if [ -z "$DRYRUN" ]
                then
                    printf 'eksctl utils update-%s --cluster "%s" --region "%s" --approve\n' "$addon_name" "$CLUSTER" "$REGION" >&5
                fi
            fi
        fi
    done
    if [ -z "$DRYRUN" ]
    then
        printf "\n" >&5
    fi
fi

printf "\nRunning tests...\n"

# Won't return a non-zero return value when failing unless `--exit-error` is given.
#if ! kubent --exit-error &> /dev/null
#then
#    KUBENT_CHECK=1
#fi

nodegroups="$(eksctl get nodegroups --cluster "$CLUSTER" --region "$REGION" -ojson)"
for nodegroup_name in $(echo "$nodegroups" | jq -r '.[].Name')
do
    nodegroup="$(echo "$nodegroups" | jq '.[] | select(.Name | contains('\""$nodegroup_name"\"'))')"
    nodegroup_version="$(echo "$nodegroup" | jq -r '.Version')"
    if [[ "$nodegroup_version" != "$control_plane_version" ]]
    then
        VERSION_CHECK=1
        SUCCEEDED=1
    fi

    # Even if the versions don't match, write the upgrade command to the script. This is useful
    # when already having upgraded the control plane but now need to do the data plane.
    if [ -z "$DRYRUN" ]
    then
        printf 'eksctl upgrade nodegroup --name "%s" --cluster "%s" --region "%s" --kubernetes-version "%s"\n' "$nodegroup_name" "$CLUSTER" "$REGION" "$upgrade_version" >&5
    fi
done

subnet_ids=$(echo "$cluster_info" | jq -r '.[].ResourcesVpcConfig.SubnetIds')
# Don't quote `$cluster_info`, we want it to do word splitting.
for available_subnet_ips in $(aws ec2 describe-subnets --region "$REGION" --subnet-ids "$subnet_ids" --query "Subnets[*].AvailableIpAddressCount" --output text)
do
    if [[ "$available_subnet_ips" -lt 6 ]]
    then
        AVAILABLE_IPS_CHECK=1
        SUCCEEDED=1
    fi
done

if [[ "$KUBENT_CHECK" -eq 1 ]]
then
    printf "[FAIL] [KUBENT] \`kubent\` revealed at least one API issue.\n"
#    printf "[FAIL] [KUBENT] Run \`kubent -l warn -o json\` for more information.\n"
    printf "[FAIL] [KUBENT] Run \`kubent\` for more information.\n"
else
    printf "[PASS] [KUBENT] \`kube-no-trouble\` did not discover any API deprecations.\n"
fi

if [[ "$VERSION_CHECK" -eq 1 ]]
then
    printf "[FAIL] [VERSION] At least one nodegroup version (%s) doesn't equal that of the control plane (%s).\n" $nodegroup_version $control_plane_version
    printf "[FAIL] [VERSION] Run \`./describe_cluster.sh --cluster %s --region %s --verbose\` for more information.\n" $CLUSTER $REGION
else
    printf "[PASS] [VERSION] The control plane version and all node group versions are the same (%s).\n" $control_plane_version
fi

if [[ "$AVAILABLE_IPS_CHECK" -eq 1 ]]
then
    printf "[FAIL] [AVAILABLE_IPS] At least one subnet doesn't have the requisite 5 available IP addresses to perform a node group upgrade.\n"
    printf "[FAIL] [AVAILABLE_IPS] Run \`./subnets.sh --cluster %s --region %s\` for more information.\n" $CLUSTER $REGION
else
    printf "[PASS] [AVAILABLE_IPS] All cluster subnets have at least 5 available IP addresses.\n"
fi

if ! verify_iam_role
then
    printf "[FAIL] [IAM ROLE] The control plane IAM role is not present in the account.\n"
else
    printf "[PASS] [IAM ROLE] The control plane IAM role is present in the account.\n"
fi

if [ -z "$DRYRUN" ]
then
    exec 5>&-
    printf "\nUpgrade script written to %s\n" "$UPGRADE_SCRIPT"
fi

if [ -n "$PROMPT" ] || [ -n "$YES" ]
then
    printf "\n"
    cat "$UPGRADE_SCRIPT"

    if [ -n "$YES" ]
    then
        bash < "$UPGRADE_SCRIPT"
    else
        printf "\n"
        read -rp "Approve? [y/N] " approve

        if [[ "$approve" == [yY] ]]
        then
            bash < "$UPGRADE_SCRIPT"
        fi
    fi
fi

exit "$SUCCEEDED"

