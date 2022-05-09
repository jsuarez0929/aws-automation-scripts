#!/bin/sh
# ================================================================================
# 
# This script enables a replica EFS share to accept read/write operations from 
# applications. To run, specify the script executable 
# (./efs-promotion-phase1.sh) and one required parameters:
#
#     1. SOURCE_EFS_ID - The ID of the EFS share you want to restore to using a backup.
#
# SYNTAX:
#     ./efs-promotion-phase1.sh [SOURCE_EFS_ID]
#
# ================================================================================

function print_t {
    echo [ $(date -u) ] - $1
}

SOURCE_EFS_ID=$1
SOURCE_EFS_REGION=us-west-2
start_time=$(date +%s)

# Describe replication configuration
print_t "Getting replication configuration for $SOURCE_EFS_ID"
REPLICATION_DETAILS=$(aws efs describe-replication-configurations \
--file-system-id $SOURCE_EFS_ID \
--region $SOURCE_EFS_REGION \
--query Replications[0].Destinations[0])

if [ $? -ne 0 ] || [ -z "$REPLICATION_DETAILS" ]; then
    print_t "Error: Error retreiving replication configuration details.\nExiting.\n"
    exit 1
fi

# Get value of destination efs
DESTINATION_EFS_ID=$(echo $REPLICATION_DETAILS | jq -r '.Replications[0] | .Destinations[0] | .FileSystemId')
DESTINATION_EFS_REGION=$(echo $REPLICATION_DETAILS | jq -r '.Replications[0] | .Destinations[0] | .Region')
print_t "DR EFS Details:"
print_t "DR EFS_ID: $DESTINATION_EFS_ID"
print_t "DR Region: $DESTINATION_EFS_REGION"

# Delete replication configuration 
print_t "Deleting replication configuration."
aws efs delete-replication-configuration \
--source-file-system-id $EFS_ID \
--region $DESTINATION_EFS_REGION

if [ $? -ne 0 ]; then
    print_t "Error: Error attempting to delete replication configuration.\nExiting.\n"
    exit 1
fi

# Wait for completion
print_t "Waiting for delete operation to complete."
STATUS=$(aws efs describe-replication-configurations \
    --file-system-id $EFS_ID \
    --region $SOURCE_EFS_REGION \
    --query 'Replications[0].Destinations[0].Status' \
    --output text)

while [ $STATUS = "DELETING" ]; do 
    print_t "Deleting..."
    STATUS=$(aws efs describe-replication-configurations \
        --file-system-id $EFS_ID \
        --region $SOURCE_EFS_REGION \
        --query 'Replications[0].Destinations[0].Status' \
        --output text)
        sleep 5
done

print_t "Replication configuration has been succesfully deleted."
# Create mount points
# get mount target id
# wait for mount target to complete
print_t "Creating mount target on DR EFS share ($DESTINATION_EFS_ID)."
MOUNT_TARGET_STATUS=$(aws efs create-mount-target \
    --file-system-id $DESTINATION_EFS_ID \
    --subnet-id subnet-090238a0e72a0503f \
    --security-groups sg-0bc974cccd47ac73d \
    --region $DESTINATION_EFS_REGION \
    --query 'LifeCycleState' \
    --output text)

while [ $MOUNT_TARGET_STATUS != "available" ]; do 
    print_t "Waiting for mount target creation to complete"
    MOUNT_TARGET_STATUS=$(aws efs describe-mount-targets \                                                                          <aws:reef-test-1>
        --file-system-id $DESTINATION_EFS_ID \
        --region $DESTINATION_EFS_REGION \
        --query 'MountTargets[0].LifeCycleState' \
        --output text)

    sleep 5
done

print_t "Mount target succesfully created on DR EFS Share ($DESTINATION_EFS_ID)"
# get destination efs endpoint url
# echo all output values
DESTINATION_EFS_ENDPOINT=$DESTINATION_EFS_ID.efs.$DESTINATION_EFS_REGION.amazonaws.com
DESTINATION_EFS_IP=$(aws efs describe-mount-targets \                                                                          <aws:reef-test-1>
    --file-system-id $DESTINATION_EFS_ID \
    --region $DESTINATION_EFS_REGION \
    --query 'MountTargets[0].IpAddress' \
    --output text)

print_t "Promotion completed successfully."

elapsed_time=$(( $(date +%s) - $start_time ))
eval "echo Elapsed time: $(date -ud "@$elapsed_time" +'%H hr %M min %S sec')"

print_t "OUTPUTS:"
print_t "DR EFS DNS: $DESTINATION_EFS_ENDPOINT"
print_t "DR EFS IP: $DESTINATION_EFS_IP"
