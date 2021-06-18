#!/bin/bash
set -xeuo pipefail

# AWS Region
export AWS_DEFAULT_REGION=eu-west-2 

# Get the git commit sha. This is useful to ensure that our staging and production environments are the same.
cluster_name=$(git rev-parse --short HEAD)

# Grab the id and subnet of the VPC with the Kubernetes in it.
k8s_vpc=$(aws ec2 describe-vpcs \
        --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$cluster_name \
        --output=text --query 'Vpcs[].[VpcId]')
k8s_vpc_cidr_block=$(aws ec2 describe-vpcs \
        --filters Name=tag:alpha.eksctl.io/cluster-name,Values=$cluster_name \
        --output=text --query 'Vpcs[].[CidrBlock]')

# Grab the id and subnet of the VPC with the Database in it.
database_vpc=$(aws ec2 describe-vpcs \
        --filters Name=tag:Name,Values=Database \
        --output=text --query 'Vpcs[].[VpcId]')
dbs_vpc_cidr_block=$(aws ec2 describe-vpcs \
        --filters Name=tag:Name,Values=Database \
        --output=text --query 'Vpcs[].[CidrBlock]')

# Grab the route tables for the private subnets in the Kubernetes vpc 
k8s_route_tables=$(aws ec2 describe-route-tables \
        --filters 'Name=tag:Name,Values=*Private*' 'Name=vpc-id,Values=vpc-021c2c500d2abff04' \
        --query 'RouteTables[].Associations[].RouteTableId' \
        --output=text)

# Create VPC peering connection between database VPC and Kubernetes VPC
vpc_peering_connection_id=$( \
        aws ec2 create-vpc-peering-connection \
        --vpc-id $database_vpc \
        --peer-vpc-id $k8s_vpc \
        --output=text \
        --query 'VpcPeeringConnection.[VpcPeeringConnectionId]' \
        )

aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id $vpc_peering_connection_id --query 'VpcPeeringConnection.[VpcPeeringConnectionId]'

# Grab the route tables for the private subnets in the Kubernetes vpc 
k8s_route_tables=$(aws ec2 describe-route-tables \
        --filters 'Name=tag:Name,Values=*Private*' 'Name=vpc-id,Values=vpc-021c2c500d2abff04' \
        --query 'RouteTables[].Associations[].RouteTableId' \
        --output=text)

# Grab the route tables for the database vpc
dbs_vpc_route_table=$(aws ec2 describe-route-tables \
             --filters Name=vpc-id,Values=$database_vpc Name=association.main,Values=true \
             --output=text \
             --query 'RouteTables[].[RouteTableId]')

# Create route table entries in database VPC
aws ec2 create-route \
             --route-table-id $dbs_vpc_route_table \
             --destination-cidr-block $k8s_vpc_cidr_block \
             --vpc-peering-connection-id $vpc_peering_connection_id

# Create route table entries in kubernetes VPC
for _route_table in $k8s_route_tables
    do
        aws ec2 create-route \
             --route-table-id $_route_table \
             --destination-cidr-block $dbs_vpc_cidr_block \
             --vpc-peering-connection-id $vpc_peering_connection_id
    done

# Get default security group from database VPC
database_security_group=$(aws ec2 describe-security-groups \
             --filters Name=vpc-id,Values=$database_vpc \
             --query 'SecurityGroups[].[GroupId]' \
             --output=text)

# Allow database connections from the Kubernetes VPC
aws ec2 authorize-security-group-ingress\
    --group-id $database_security_group \
    --protocol tcp \
    --port 3306 \
    --cidr $k8s_vpc_cidr_block



