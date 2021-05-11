#!/bin/bash
set -euxo pipefail

# ┌───────────────────────────────────────────────┐
# │                AWS LOAD BALANCER              │
# └───────────────────────────────────────────────┘
#
# ┌────────────┐    ┌────────────┐   ┌────────────┐
# │            │    │            │   │            │
# │ K8s Node 1 │    │ K8s Node 2 │   │ K8s Node 3 │
# │            │    │            │   │            │
# └────────────┘    └────────────┘   └────────────┘

# AWS Region
export AWS_DEFAULT_REGION=eu-west-2 

# Get the git commit sha. This is useful to ensure that our staging and production environments are the same.
export CLUSTER_NAME=$(git rev-parse --short HEAD)

# Get the vpc-id of the vpc where the databases are located. 
export DATABASE_VPC=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=Database --output=text --query 'Vpcs[].[VpcId]')
# If DATABASE_VPC is empty then the database VPC does not exist. 
if [ -z "$DATABASE_VPC" ]
    then    
        echo "Database VPC not detected. Did you deploy one? It should be tagged - Name: Database"
    else
        echo "Database VPC $DATABASE_VPC discovered. We are going to assume that there is Databases in there."
fi

# Template the clusterConfig. Set the clustername for the soon to be deployed K8s cluster,
cat clusterConfig.yaml | envsubst > $CLUSTER_NAME.yaml

# This creates our new kubernetes cluster and associated resources. 
# eksctl create cluster -f $CLUSTER_NAME.yaml

# Grab the VPC with the Kubernetes in it.
export K8S_VPC=$(aws ec2 describe-vpcs --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$CLUSTER_NAME --output=text --query 'Vpcs[].[VpcId]')

# Deploy an ingress controller. Along with the ingress controller will be deployed a Kubernetes service of Type: LoadBalancer.
# This will create a public facing AWS load balancer automatically assigned to the cluster. 
# We have to wait for a while before the public IP address becomes available.  
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.46.0/deploy/static/provider/aws/deploy.yaml


