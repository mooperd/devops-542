#!/bin/bash
set -xeuo pipefail

# AWS Region
export AWS_DEFAULT_REGION=eu-west-2 

# Get the git commit sha. This is useful to ensure that our staging and production environments are the same.
cluster_name=$(git rev-parse --short HEAD)

# Get the id and subnet of the vpc where the databases are located. 
database_vpc=$(aws ec2 describe-vpcs \
         --filters Name=tag:Name,Values=Database \
         --output=text --query 'Vpcs[].[VpcId]')

dbs_vpc_cidr_block=$(aws ec2 describe-vpcs \
         --filters Name=tag:Name,Values=Database \
         --output=text --query 'Vpcs[].[CidrBlock]')

# Grab the id and subnet of the VPC with the Kubernetes in it.
k8s_vpc=$(aws ec2 describe-vpcs \
        --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$cluster_name \
        --output=text --query 'Vpcs[].[VpcId]')

k8s_vpc_cidr_block=$(aws ec2 describe-vpcs \
        --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$cluster_name \
        --output=text --query 'Vpcs[].[CidrBlock]')

k8s_public_subnets=( $(aws ec2 describe-subnets \
        --filters="Name=tag:Name,Values=*SubnetPublic*" \
        --output=text --query="Subnets[].[SubnetId]") )

export GITLAB_RUNNER_SUBNET=${k8s_public_subnets[0]}

export GITLAB_RUNNER_AMI=$(aws ec2 describe-images \
        --owners self \
        --filters 'Name=tag:Name,Values=flibber-flobber' \
        --output=text --query 'Images[].[ImageId]')

cat launch-template.json | envsubst

# cat launch-template.json | envsubst | xargs -0 aws ec2 create-launch-template --launch-template-name meow --launch-template-data

