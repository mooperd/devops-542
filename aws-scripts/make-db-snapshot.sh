#!/bin/bash
set -euxo pipefail

export RDS_INSTANCE=test-mysql-instance
export SNAPSHOT_NAME=$RDS_INSTANCE-$(date +%D%H%M%S | base64)
export AWS_RECIPIENT_ACCOUNT=555466226936

aws rds create-db-snapshot \
    --db-instance-identifier $RDS_INSTANCE \
    --db-snapshot-identifier $SNAPSHOT_NAME

aws rds wait db-snapshot-available \
    --db-snapshot-identifier $SNAPSHOT_NAME

aws rds modify-db-snapshot-attribute \
    --db-snapshot-identifier $SNAPSHOT_NAME \
    --attribute-name restore \
    --values-to-add $AWS_RECIPIENT_ACCOUNT
