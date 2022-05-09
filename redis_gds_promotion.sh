#!/bin/sh
# ================================================================================
# 
# To run this script specify the script executable (./promote_redis.sh) and two 
# required parameters:
#
#     1. GLOBAL_DS_NAME - The name of the redis global datastore in AWS
#     2. DESIRED_PRIMARY - The name of the Redis cluster that should be 
#                          promoted to primary.
#
# SYNTAX:
#     ./redis_promote.sh [GLOBAL_DS_NAME] [DESIRED_PRIMARY]
#
# ================================================================================
function print_t {
    echo [ $(date -u) ] - $1
}

GLOBAL_DS_NAME=$1
DESIRED_PRIMARY=$2
REGION=""

# Input validation
if [ -z $GLOBAL_DS_NAME ] || [ -z $DESIRED_PRIMARY ]; then
    print_t 'Error: Missing parameters.'
    print_t 'SYNTAX: ./redis_promote.sh [GLOBAL_DS_NAME] [DESIRED_PRIMARY]'
    exit 1
fi
# Get GDS member details
PRIMARY_CLUSTER_DETAILS=$(aws elasticache describe-global-replication-groups \
    --global-replication-group-id $GLOBAL_DS_NAME \
    --region $REGION \
    --show-member-info \
    --query 'GlobalReplicationGroups[0].Members[?Role==`PRIMARY`]')
SECONDARY_CLUSTER_DETAILS=$(aws elasticache describe-global-replication-groups \
    --global-replication-group-id $GLOBAL_DS_NAME \
    --region $REGION \
    --show-member-info \
    --query 'GlobalReplicationGroups[0].Members[?Role==`SECONDARY`]')
if [ $? -ne 0 ] || [ -z "$PRIMARY_CLUSTER_DETAILS" ] || [ -z "$SECONDARY_CLUSTER_DETAILS" ]; then
    print_t "Error: Error retreiving global datastore member details.\n Exiting.\n"
    exit 1
fi
print_t "Current primary cluster: "
echo $PRIMARY_CLUSTER_DETAILS | jq '.[0]'
print_t "Current secondary cluster: "
echo $SECONDARY_CLUSTER_DETAILS | jq '.[0]'

# Get cluster name & region for both primary and secondary
PRIMARY_CLUSTER_NAME=$(echo $PRIMARY_CLUSTER_DETAILS | jq -r '.[0] | .ReplicationGroupId')
PRIMARY_CLUSTER_REGION=$(echo $PRIMARY_CLUSTER_DETAILS | jq -r '.[0] | .ReplicationGroupRegion')
SECONDARY_CLUSTER_NAME=$(echo $SECONDARY_CLUSTER_DETAILS | jq -r '.[0] | .ReplicationGroupId')
SECONDARY_CLUSTER_REGION=$(echo $SECONDARY_CLUSTER_DETAILS | jq -r '.[0] | .ReplicationGroupRegion')

echo '[{ "Id": "myRequest", "MetricStat": { "Metric": { "Namespace": "AWS/ElastiCache", "MetricName": "GlobalDatastoreReplicationLag", "Dimensions": [ { "Name": "ReplicationGroupId", "Value": "'$SECONDARY_CLUSTER_NAME'" }] }, "Period": 300, "Stat": "Average" }, "Label": "myRequestLabel", "ReturnData": true }]' | jq > metric-data.json

REPLICATION_LAG=$(aws cloudwatch get-metric-data \
--metric-data-queries file://./metric-data.json \
--start-time $(date -ud "-5 min" +"%Y-%m-%dT%H:%M:%SZ") \
--end-time $(date -u +"%Y-%m-%dT%H:%M:%SZ") \
--region $SECONDARY_CLUSTER_REGION \
--query 'MetricDataResults[0].Values[0]')

if [ $? -ne 0 ] || [ -z $REPLICATION_LAG ]; then
    print_t "Error: Error retreiving replication lag.\n Exiting.\n"
    exit 1
else
    # Calculate replication lag
    if [ $(echo "$REPLICATION_LAG < 1" | bc -l) ]; then
        print_t "REPLICATION LAG VALUE: $REPLICATION_LAG"
        start_time=$(date +%s)
        # Promote to desired cluster
        case $DESIRED_PRIMARY in
            $PRIMARY_CLUSTER_NAME)
                print_t "Promoting cluster $PRIMARY_CLUSTER_NAME to primary."
                aws elasticache failover-global-replication-group \
                --global-replication-group-id $GLOBAL_DS_NAME \
                --primary-region $PRIMARY_CLUSTER_REGION \
                --primary-replication-group-id $PRIMARY_CLUSTER_NAME
            ;;
            $SECONDARY_CLUSTER_NAME)
                print_t "Promoting cluster $SECONDARY_CLUSTER_NAME to primary."
                aws elasticache failover-global-replication-group \
                --global-replication-group-id $GLOBAL_DS_NAME \
                --primary-region $SECONDARY_CLUSTER_REGION \
                --primary-replication-group-id $SECONDARY_CLUSTER_NAME
            ;;
            *)
                print_t "ERROR: Invalid cluster name specified for DESIRED_PRIMARY"
                print_t "Exiting."
                exit 1
            ;;
        esac

        if [ $? -ne 0 ]; then
            print_t "Error: Error Promoting cluster $DESIRED_PRIMARY to primary.\n Exiting.\n"
            exit 1
        fi

        # Get status of GDS and wait until promotion is complete
        GDS_STATUS=$(aws elasticache describe-global-replication-groups \
        --global-replication-group-id $GLOBAL_DS_NAME \
        --region $REGION \
        --show-member-info \
        --query 'GlobalReplicationGroups[0].Status' \
        --output text)
        while [ $GDS_STATUS != "available" ]; do
            print_t "Waiting for promotion to complete."
            sleep 5
            GDS_STATUS=$(aws elasticache describe-global-replication-groups \
            --global-replication-group-id $GLOBAL_DS_NAME \
            --region $REGION \
            --show-member-info \
            --query 'GlobalReplicationGroups[0].Status' \
            --output text)
        done

        elapsed_time=$(( $(date +%s) - $start_time ))
        print_t "Redis cluster $DESIRED_PRIMARY has been succesfully promoted to primary."
        eval "echo Elapsed time: $(date -ud "@$elapsed_time" +'%H hr %M min %S sec')"
        exit 0
    else
        print_t "Error: Replication lag is above the required value of 0."
        print_t "REPLICATION LAG VALUE: $REPLICATION_LAG"
        print_t "Exiting."
        exit 1
    fi
fi