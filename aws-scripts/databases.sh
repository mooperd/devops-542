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
        for subnet in "${!dbs_subnets_cidr[@]}"
            do
                echo "${dbs_subnets_cidr[subnet]}" is in "${dbs_subnets_names[subnet]}"
                subnet_ids+=( $( \
                        aws ec2 create-subnet \
                        --vpc-id $database_vpc \
                        --cidr-block ${dbs_subnets_cidr[subnet]} \
                        --availability-zone-id ${availability_zones[subnet]} \
                        --output text --query 'Subnet.[SubnetId]' \
                        --tag-specifications "ResourceType=subnet, Tags=[{Key=Name,Value=${dbs_subnets_names[subnet]}}]" \
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

