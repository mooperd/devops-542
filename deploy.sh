#!/bin/bash
set -xeuo pipefail

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
cluster_name=$(git rev-parse --short HEAD)

#IP ranges and names
k8s_vpc_cidr_block=10.142.0.0/16
dbs_vpc_cidr_block=10.141.0.0/16
dbs_subnets_cidr=( 10.141.10.0/24 10.141.20.0/24 10.141.30.0/24 )
dbs_subnets_names=( Database-10 Database-20 Database-30 )
availability_zones=( $(aws ec2 describe-availability-zones --output text --query "AvailabilityZones[].[ZoneId]") )


# Get the vpc-id of the vpc where the databases are located. 
database_vpc=$(aws ec2 describe-vpcs \
         --filters Name=tag:Name,Values=Database \
         --output=text --query 'Vpcs[].[VpcId]')

# If DATABASE_VPC is empty then the database VPC does not exist. Lets create it! 
if [ -z "$database_vpc" ]
    then    
        echo "Database VPC not detected with tags - Name: Database. I'm going to create it now."
        database_vpc=$(aws ec2 create-vpc \
                --cidr-block $dbs_vpc_cidr_block \
                --tag-specifications 'ResourceType=vpc, Tags=[{Key=Name,Value=Database}]' \
                --output=text --query 'Vpc.[VpcId]')

        
        # Iterate through the arrays to create subnets for databases. We want one subnet in each availability zone.
        subnet_ids=()
        for subnet in "${!subnetsCidr[@]}"
            do
                echo "${subnetsCidr[subnet]}" is in "${subnetsNames[subnet]}"
                subnet_ids+=( $( \
                        aws ec2 create-subnet \
                        --vpc-id $database_vpc \
                        --cidr-block ${subnetsCidr[subnet]} \
                        --availability-zone-id ${availabilityZones[subnet]} \
                        --output text --query 'Subnet.[SubnetId]' \
                        --tag-specifications "ResourceType=subnet, Tags=[{Key=Name,Value=${subnetsNames[subnet]}}]" \
                        ) )
            done

        # Create database subnet group
        aws rds create-db-subnet-group \
                --db-subnet-group-name databaseSubnetGroup \
                --db-subnet-group-description "DB Subnet Group" \
                --subnet-ids "${subnet_ids[@]}"

        # Deploy database instances
        aws rds create-db-instance \
                --db-instance-identifier test-mysql-instance \
                --db-instance-class db.t3.micro \
                --db-subnet-group-name databaseSubnetGroup \
                --engine mysql \
                --master-username admin \
                --master-user-password secret99 \
                --allocated-storage 20
     
        echo vpc $database_vpc was created with subnets: "${subnet_ids[@]}"
    else
        echo "Database VPC $database_vpc discovered. We are going to assume that there is Databases in there."
fi

# Template the clusterConfig. Set the clustername for the soon to be deployed K8s cluster,
cat clusterConfig.yaml | K8S_VPC_CIDR_BLOCK=$k8s_vpc_cidr_block CLUSTER_NAME=$cluster_name envsubst > $cluster_name.yaml

# This creates our new kubernetes cluster and associated resources. 
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

# Create VPC peering connection between database VPC and Kubernetes VPC
vpc_peering_connection_id=$( \
        aws ec2 create-vpc-peering-connection \
        --vpc-id $database_vpc \
        --peer-vpc-id $k8s_vpc \
        --output=text \
        --query 'VpcPeeringConnection.[VpcPeeringConnectionId]' \
        )

aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $vpc_peering_connection_id --query 'VpcPeeringConnection.[VpcPeeringConnectionId]'

# Get route tables that we need to update for VPC peering

k8s_vpc_route_table=$( \
             aws ec2 describe-route-tables \
             --filters Name=vpc-id,Values=$k8s_vpc Name=association.main,Values=true \
             --output=text \
             --query 'RouteTables[].[RouteTableId]' \
             )

dbs_vpc_route_table=$( \
             aws ec2 describe-route-tables \
             --filters Name=vpc-id,Values=$database_vpc Name=association.main,Values=true \
             --output=text \
             --query 'RouteTables[].[RouteTableId]')

aws ec2 create-route \
             --route-table-id $k8s_vpc_route_table \
             --destination-cidr-block $dbs_vpc_cidr_block \
             --vpc-peering-connection-id $vpc_peering_connection_id

aws ec2 create-route \
             --route-table-id $dbs_vpc_route_table \
             --destination-cidr-block $k8s_vpc_cidr_block \
             --vpc-peering-connection-id $vpc_peering_connection_id

# Find the public endpoint of our kubernetes cluster.
export ingress_external_endpoint=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "public endpoint of our kubernetes cluster is $ingress_external_endpoint. You probably need to do something with that."
