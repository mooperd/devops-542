#!/bin/bash
set -xeuo pipefail
alias aws='/usr/local/bin/aws'

# AWS Region
export AWS_DEFAULT_REGION=eu-west-2 

# Get the git commit sha. This is useful to ensure that our staging and production environments are the same.
cluster_name=$(git rev-parse --short HEAD)
k8s_vpc_cidr_block=10.142.0.0/16
dbs_vpc_cidr_block=10.141.0.0/16

# Get the vpc-id of the vpc where the databases are located. 
database_vpc=$(aws ec2 describe-vpcs \
         --filters Name=tag:Name,Values=Database \
         --output=text --query 'Vpcs[].[VpcId]')

# If DATABASE_VPC is empty then the database VPC does not exist. Lets create it! 
if [ -z "$database_vpc" ]
    then    
        echo "Database VPC not detected with tags - Name: Database. Please create your database VPC first"
        exit 1
    else
        echo "Database VPC $database_vpc discovered. We are going to assume that there is Databases in there."
fi

# Template the clusterConfig. Set the clustername for the soon to be deployed K8s cluster,
cat clusterConfig.yaml | K8S_VPC_CIDR_BLOCK=$k8s_vpc_cidr_block CLUSTER_NAME=$cluster_name envsubst > $cluster_name.yaml

# This creates our new kubernetes cluster and associated resources. 
# This will also set up kubeconfig locally so we can connect to the cluster.
eksctl create cluster -f $cluster_name.yaml || echo "Cluster $cluster_name probably already exists. Passing"

# Grab the id of the VPC with the Kubernetes in it.
k8s_vpc=$( \
        aws ec2 describe-vpcs \
        --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$cluster_name \
        --output=text --query 'Vpcs[].[VpcId]' \
        )

# Deploy an ingress controller. Along with the ingress controller will be deployed a Kubernetes service of Type: LoadBalancer.
# This will create a public facing AWS load balancer automatically assigned to the cluster. 
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v0.46.0/deploy/static/provider/aws/deploy.yaml

# Find the public endpoint of our kubernetes cluster.
export ingress_external_endpoint=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "public endpoint of our kubernetes cluster is $ingress_external_endpoint. You probably need to do something with that."
