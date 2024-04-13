## Upgrade Process

1. Review release notes.
1. Optionally take a backup (`velero`).
1. Run precheck script.
    - Check for [deprecated APIs].
    - Ensure control plane and all node groups (data plane) are currently on the same minor release version.
    - Ensure each subnet in the VPC has at least five available IP addresses.
    - Ensure the [EKS IAM role] is attached to the cluster.
    - Precheck will also check for newer addon release versions that are compatible with the minor release version being upgraded to.
    - Automatically generate an `update.sh` script that will automate the rest of the steps.
1. Upgrade cluster control plane.
1. Upgrade addons.
1. Upgrade `kubect`.
1. Upgrade cluster data plane.

## Recommendations

- leverage eks to upgrade both control plane and data plane
- different node values for min, max and desired sizes to allow for eks to autoscale
- have different minor versions depending upon environment
    + lower environments have more recent versions
- don't mount secrets or credentials in pods that don't expire and don't rotate
    + credentials that never expire or are never rotated is not great
    + eks can help us with this (see IRSA)
- use IRSA
    + pods should use a role that is annotated in a service account that gives least privileges necessary to a pod or group of pods
        - pods should explicitly set the `spec.serviceAccountName` pod spec field for IRSA
    + pods that don't need to interact with any aws services should not be given any tokens (even default)
        - pods that don't need any injected credentials should set the `automountServiceAccountToken` to `false` so the `kubelet` doesn't automatically mount a projected volume, even with the `default` service account
- use EBS encrypted volumes and snapshots
    + aws handles encryption keys and rotation
    + free
- if any of the addons are self-managed they should be migrated to managed addons

## Docker

```bash
$ docker run \
    --rm
    -e KUBECONFIG=/kube/config
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
    -e AWS_SESSION_TOKEN="$AWS_SESSION_TOKEN"
    -v ~/.kube:/kube
    -it
    precheck --cluster kilgore-trout-was-here --region eu-west-1 --dry-run
```

## References

- [Available Amazon EKS add-ons from Amazon EKS](https://docs.aws.amazon.com/eks/latest/userguide/eks-add-ons.html#workloads-add-ons-available-eks)

[deprecated APIs]: https://github.com/doitintl/kube-no-trouble
[EKS IAM role]: https://docs.aws.amazon.com/eks/latest/userguide/service_IAM_role.html

