#!/bin/sh
# ================================================================================
# 
# To run this script specify the script executable (./efs-restore-backup-phase2.sh) 
# and two required parameters:
#
#     1. EFS_ID - The ID of the EFS share you want to restore to using a backup.
#     2. BACKUP_JOB_ID - The ID of the EFS Backup you want to restore from. To restore
#                         from the latest backup, specify the "-latest" flag or simply
#                         leave this parameter empty.
#
# SYNTAX:
#     ./efs-restore-backup-phase2.sh [EFS_ID] [BACKUP_JOB_ID]   ---> Restore from specific backup
#     ./efs-restore-backup-phase2.sh [EFS_ID] -latest   ---> Restore using latest backup
#
# ================================================================================
function print_t {
    echo [ $(date -u) ] - $1
}

EFS_ID=$1
REGION="us-west-2"
BACKUP_JOB_ID=${2:--latest}

EFS_ARN="arn:aws:elasticfilesystem:<REGION>:<AWS_ACCT_NUM>:file-system/$EFS_ID"
IAM_ROLE_ARN="arn:aws:iam::<AWS_ACCT_NUM>:role/service-role/AWSBackupDefaultServiceRole"

start_time=$(date +%s)

# Get latest EFS Backup
case $BACKUP_JOB_ID in

    "-latest")
        print_t "Getting latest EFS backup for $EFS_ID.\n"
        LATEST_EFS_BACKUP=$(aws backup list-backup-jobs \
        --by-resource-arn $EFS_ARN \
        --by-state COMPLETED \
        --region $REGION \
        --query 'reverse(sort_by(BackupJobs, &CreationDate))[0]')
    ;;

    *)
        print_t "Getting details for EFS backup $BACKUP_JOB_ID for $EFS_ID.\n"
        LATEST_EFS_BACKUP=$(aws backup list-backup-jobs \
        --by-resource-arn $EFS_ARN \
        --by-state COMPLETED \
        --region $REGION \
        --query "BackupJobs[?BackupJobId=='$BACKUP_JOB_ID'] | [0]")
    ;;
esac

if [ $? -ne 0 ] || [ -z "$LATEST_EFS_BACKUP" ]; then
    print_t "Error: Error retreiving latest EFS backup details.\nExiting.\n"
    exit 1
fi

print_t "EFS Backup to be restored:"
echo $LATEST_EFS_BACKUP | jq

#Get Recovery Point ARN
RECOVERY_POINT_ARN=$(echo $LATEST_EFS_BACKUP | jq -r .RecoveryPointArn)

# Restore from backup
print_t "Starting restore job.\n"
RESTORE_JOB_ID=$(aws backup start-restore-job \
--region $REGION \
--recovery-point-arn $RECOVERY_POINT_ARN \
--iam-role-arn $IAM_ROLE_ARN \
--metadata '{"file-system-id": "'$EFS_ID'", "newFileSystem": "false", "Encrypted": "false", "PerformanceMode":"generalPurpose"}' | jq -r .RestoreJobId)

if [ $? -ne 0 ] || [ -z "$RESTORE_JOB_ID" ]; then
    print_t "Error: Error starting restore job.\nExiting.\n"
    exit 1
fi

RESTORE_JOB_STATUS=$(aws backup describe-restore-job --restore-job-id $RESTORE_JOB_ID --region $REGION --query Status)

# Wait for restore to complete
print_t "Waiting for restore job to complete."
while [ $RESTORE_JOB_STATUS != "COMPLETED" ]; do
    
    if [ $RESTORE_JOB_STATUS = "FAILED" ] || [ $RESTORE_JOB_STATUS = "ABORTED" ]; then
        print_t "Error while trying to restore from backup."
        print_t "Status message: $(aws backup describe-restore-job --restore-job-id $RESTORE_JOB_ID --region $REGION --query StatusMessage)"
        exit 1
    fi

    RESTORE_JOB_DETAILS=$(aws backup describe-restore-job --restore-job-id $RESTORE_JOB_ID --region $REGION)

    print_t "Percent done: $(echo $RESTORE_JOB_DETAILS | jq -r .PercentDone)"
    RESTORE_JOB_STATUS=$(echo $RESTORE_JOB_DETAILS | jq -r .Status)
    sleep 5
done

elapsed_time=$(( $(date +%s) - $start_time ))
print_t "Lastest backup has been successfully restored to $EFS_ID"
eval "echo Elapsed time: $(date -ud "@$elapsed_time" +'%H hr %M min %S sec')"

exit 0
