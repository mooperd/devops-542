#!/bin/bash
# https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html
set -euxo pipefail
alias aws='/usr/local/bin/aws'

if [ -z "$1" ]
then
      echo "gimme a string mf"
else
      export RANDOM_STRING=$1
fi

# cluster_name=$(git rev-parse --short HEAD)
export RANDOM_STRING="${1,,}"
export cluster_name=d56baae
export AWS_ACCOUNT_ID=533016277303
export AWS_DEFAULT_REGION=eu-west-2
export BUCKET_ARN=arn:aws:s3:::invalidbucketname
export NAMESPACE=efs-$RANDOM_STRING
export PV_NAME=pv-$RANDOM_STRING
export PVC_NAME=pvc-$RANDOM_STRING
export SERVICE_ACCOUNT_NAME=$RANDOM_STRING


# First create the namespace
cat namespace.yaml | envsubst
cat namespace.yaml | envsubst | kubectl apply -f - 

eksctl create iamserviceaccount \
    --name $SERVICE_ACCOUNT_NAME \
    --cluster $cluster_name \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --namespace $NAMESPACE \
    --approve \
    --region $AWS_DEFAULT_REGION

cat pv-dep-job.yaml | envsubst
cat pv-dep-job.yaml | envsubst | kubectl apply -n $NAMESPACE -f -

kubectl wait --for=condition=complete job/create-efs-dir -n $NAMESPACE

# Create the deployment
cat pv-dep-example.yaml | envsubst
cat pv-dep-example.yaml | envsubst | kubectl apply -n $NAMESPACE -f -
