#!/bin/bash
set -x

# AWS Region
export AWS_DEFAULT_REGION=eu-west-2 

# Database instances
for instance in $(aws rds describe-db-instances --output text --query 'DBInstances[].[DBInstanceIdentifier]')
    do
       aws rds modify-db-instance --db-instance-identifier $instance --no-deletion-protection
       aws rds delete-db-instance --db-instance-identifier $instance --delete-automated-backups --skip-final-snapshot
    done

# VPC peering connections
for peering in $(aws ec2 describe-vpc-peering-connections --output text --query 'VpcPeeringConnections[].[VpcPeeringConnectionId]')
    do
       aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id $peering
    done

# Subnet groups
for subnet_group in $(aws rds describe-db-subnet-groups --output text --query 'DBSubnetGroups[].[DBSubnetGroupName]')
    do
      aws rds delete-db-subnet-group --db-subnet-group-name $subnet_group
    done

for vpc in $(aws ec2 describe-vpcs --filters Name=tag:Name,Values=Database --output=text --query 'Vpcs[].[VpcId]')
