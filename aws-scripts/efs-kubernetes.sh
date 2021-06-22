#!/bin/bash
# https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html
set -euxo pipefail

# cluster_name=$(git rev-parse --short HEAD)
export cluster_name=73d725d
# filesystem_id=fs-d1f11b21
export AWS_ACCOUNT_ID=533016277303
export AWS_DEFAULT_REGION=eu-west-2

##########################################
# Create the filesystem and grab its ID. #
##########################################
export FILE_SYSTEM_ID=$(aws efs create-file-system \
    --region $AWS_DEFAULT_REGION \
    --performance-mode generalPurpose \
    --query 'FileSystemId' \
    --output text)

# Grab the id and subnet of the VPC with the Kubernetes in it.
k8s_vpc_id=$(aws ec2 describe-vpcs \
        --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$cluster_name \
        --output=text --query 'Vpcs[].[VpcId]')

k8s_vpc_cidr_block=$(aws ec2 describe-vpcs \
        --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$cluster_name \
        --output=text --query 'Vpcs[].[CidrBlock]')

# ( $(command) ) makes an array from the output of `command`
k8s_private_subnets=$(aws ec2 describe-subnets \
        --filters Name=tag:Name,Values=*Private* Name=vpc-id,Values=$k8s_vpc_id \
        --query Subnets[].SubnetId[] \
        --output=text)

# The EFS needs a security group to control ingress.
security_group_id=$(aws ec2 create-security-group \
    --group-name EfsSG-$FILE_SYSTEM_ID \
    --description "EFS security group for $FILE_SYSTEM_ID" \
    --vpc-id $k8s_vpc_id \
    --output text)

aws ec2 authorize-security-group-ingress \
    --group-id $security_group_id \
    --protocol tcp \
    --port 2049 \
    --cidr $k8s_vpc_cidr_block

# EFS needs to be mounted in the same subnets where the kubernetes nodes reside.
for subnet in $k8s_private_subnets
    do
        aws efs create-mount-target \
            --file-system-id $FILE_SYSTEM_ID \
            --subnet-id $subnet \
            --security-groups $security_group_id
    done

# Do shit on the kubernetes side
eksctl create iamserviceaccount \
    --name efs-csi-controller-sa \
    --namespace kube-system \
    --cluster $cluster_name \
    --attach-policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AmazonEKS_EFS_CSI_Driver_Policy \
    --approve \
    --override-existing-serviceaccounts \
    --region $AWS_DEFAULT_REGION

# Get a Kubeconfig so we can interact with the cluster.
aws eks --region $AWS_DEFAULT_REGION update-kubeconfig --name $cluster_name

# Install the EFS driver for K8s
kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.3"

# Delete the storage class before we can create another
kubectl delete sc efs-sc
cat storageclass.yaml | envsubst | kubectl apply -f -

