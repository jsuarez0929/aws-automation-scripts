# API Gateway - Disaster recovery

# DR API gateway needs to have the following resources created/available
# - all required vpc links (api gateway config)
# - stage variables defined
# - custom authorizer (api gateway config)
# - custom authorizer (lambda)
# - custom domain name
# - acm cert


#!/bin/sh
# ================================================================================
# 
# This script will export all api gateway resource definitions from the primary
# api-gateway as json in swagger 2.0 format. The exported file will be used to 
# update/populate a DR api-gateway kept in standby mode with the most recent changes.
# To run, specify the executable (./apigateway-phase1.sh) and two required parameters:
#
#     1. SOURCE_APIGW_ID - The ID of the primary api gateway to be cloned.
#     2. DESTINATION_APIGW_ID - The ID of the DR api gateway to be updated
#
# SYNTAX:
#     ./apigateway-phase1.sh [SOURCE_APIGW_ID] [DESTINATION_APIGW_ID]
#
# ================================================================================
# REGION=$PRIMARY_REGION
# DR_REGION=$DR_REGION

SOURCE_APIGW_ID=$1
DESTINATION_APIGW_ID=$2

STAGE=dev

set -e

echo "Getting primary API Gateway resouce/method swagger export."
aws apigateway get-export \
--parameters extensions='apigateway' \
--rest-api-id $SOURCE_APIGW_ID \
--stage-name $STAGE \
--export-type swagger ./export.json \
--region $AWS_DEFAULT_REGION 1> /dev/null

if [ $? -eq 0 ]; then

    if [ -f "export.json" ]; then
        #curl -H 'Content-type: application/json' -X PUT -d @export.json https://apigateway.$DR_REGION.amazonaws.com/restapis/$DESTINATION_APIGW_ID?mode=overwrite

        echo "Copying swagger definitions to DR API Gateway."
        aws apigateway put-rest-api \
        --rest-api-id $DESTINATION_APIGW_ID \
        --mode overwrite \
        --fail-on-warnings \
        --body 'fileb://export.json' \
        --region $DR_REGION 1> /dev/null

        # cat test.txt
        
        #Deploy to stage
        echo "Deploying latest changes to stage: $STAGE"
        DEPLOYMENT_ID=$(aws apigateway create-deployment \
        --rest-api-id $DESTINATION_APIGW_ID \
        --description "DR Event - Cloning data from $SOURCE_APIGW_ID ($REGION)" \
        --region $DR_REGION \
        --query 'id' \
        --output text)

        aws apigateway update-stage \
        --rest-api-id $DESTINATION_APIGW_ID \
        --stage-name $STAGE \
        --patch-operations op='replace',path='/deploymentId',value="$DEPLOYMENT_ID" \
        --region $DR_REGION
        
        echo "Successfully cloned resources/methods from source ($SOURCE_APIGW_ID) to DR API Gateway ($DESTINATION_APIGW_ID)"
    fi
fi

set +e

