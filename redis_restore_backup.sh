#!/bin/sh

# ===================================================================================
#
# This script creates a new Elasticache Redis cluster from a specified point-in-time
# backup. To run, specify the script executable (./redis-restore-backup-phase2.sh)
# and one required parameter:
#
#     1. BACKUP_ID - The Name/ID of the Redis Backup you want to restore from. To 
#                    restore from the latest backup, specify the "-latest" flag or
#                    simply leave this parameter empty.
#
# SYNTAX:
#     ./redis-restore-backup-phase2.sh [BACKUP_ID]   ---> Restore from specific backup
#     ./redis-restore-backup-phase2.sh -latest   ---> Restore using latest backup
#
# ===================================================================================
function print_t {
    echo [ $(date -u) ] - $1
}

BACKUP_ID=${1:--latest}
REGION=""

start_time=$(date +%s)

case $BACKUP_ID in
    "-latest")  
        print_t "Getting latest Redis backup."
        REDIS_BACKUP_DETAILS=$(aws elasticache describe-snapshots \
        --region $REGION \
        --query 'reverse(sort_by(Snapshots, &NodeSnapshots[0].SnapshotCreateTime))[0]')
    ;;

    *)
        print_t "Getting Redis backup $BACKUP_ID"
        REDIS_BACKUP_DETAILS=$(aws elasticache describe-snapshots \
        --region $REGION \
        --query "Snapshots[?SnapshotName=='$BACKUP_ID'] | [0]")
    ;;
esac


if [ $? -ne 0 ] || [ -z "$REDIS_BACKUP_DETAILS" ]; then
    print_t "Error: Error retreiving latest Redis backup details.\nExiting.\n"
    exit 1
fi

print_t "Backup to be restored: "
echo $REDIS_BACKUP_DETAILS | jq
SNAPSHOT_NAME=$(echo $REDIS_BACKUP_DETAILS | jq -r '.SnapshotName' )
SNAPSHOT_TIME=$(echo $REDIS_BACKUP_DETAILS | jq -r '.NodeSnapshots[0] | .SnapshotCreateTime' | sed -E 's/(\+.*)//g; s/(\:)/-/g')

print_t "Restoring backup to new Redis cluster"
REDIS_CLUSTER_DETAILS=$(aws elasticache create-replication-group \
--replication-group-id redis-restore-$SNAPSHOT_TIME \
--replication-group-description "Redis Cluster restored from snapshot $BACKUP_ID" \
--replicas-per-node-group 3 \
--transit-encryption-enabled \
--at-rest-encryption-enabled \
--cache-parameter-group default.redis5.0 \
--snapshot-name $SNAPSHOT_NAME \
--region $REGION)

if [ $? -ne 0 ] || [ -z "$REDIS_CLUSTER_DETAILS" ]; then
    print_t "Error: Error creating Redis cluster from backup.\nExiting.\n"
    exit 1
fi

REDIS_CLUSTER_STATUS=$(aws elasticache describe-replication-groups \
--replication-group-id "redis-restore-$SNAPSHOT_TIME" \
--region $REGION \
--query 'ReplicationGroups[0].Status' \
--output text)

while [ $REDIS_CLUSTER_STATUS != "available" ]; do
    
    if [ $REDIS_CLUSTER_STATUS = "create-failed" ]; then
        print_t "Error while trying to restore from backup."
        exit 1
    fi

    print_t "Waiting for Redis cluster to become available."

    REDIS_CLUSTER_STATUS=$(aws elasticache describe-replication-groups \
    --replication-group-id "redis-restore-$SNAPSHOT_TIME" \
    --region $REGION \
    --query 'ReplicationGroups[0].Status' \
    --output text)
    
    sleep 5
done

elapsed_time=$(( $(date +%s) - $start_time ))
print_t "Lastest Redis backup has been successfully restored."
eval "echo Elapsed time: $(date -ud "@$elapsed_time" +'%H hr %M min %S sec')"

exit 0