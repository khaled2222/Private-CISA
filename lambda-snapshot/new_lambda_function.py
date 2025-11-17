import boto3
import os
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')

MATCH_SUBSTRING = os.environ.get('MATCH_SUBSTRING', 'khaled')


def lambda_handler(event, context):
    logger.info("Starting EC2 full backup job. Searching for instances with Name containing: %s", MATCH_SUBSTRING)

    instances = _find_instances_with_name_substring(MATCH_SUBSTRING)
    snapshot_count = 0
    date_str = datetime.utcnow().strftime('%Y-%m-%d')

    for inst in instances:
        instance_id = inst['InstanceId']
        name_tag = _get_name_tag_value(inst.get('Tags', [])) or "UnknownName"

        logger.info("Backing up instance %s (%s)", instance_id, name_tag)

        # All attached EBS volumes
        for mapping in inst.get('BlockDeviceMappings', []):
            ebs = mapping.get('Ebs')
            if not ebs:
                continue

            volume_id = ebs['VolumeId']

            snapshot_description = (
                f"Automated snapshot for instance {instance_id} ({name_tag}) "
                f"volume {volume_id} taken on {date_str}"
            )

            snapshot_name_tag = f"{name_tag}-{volume_id}-backup-{date_str}"

            try:
                resp = ec2.create_snapshot(
                    VolumeId=volume_id,
                    Description=snapshot_description,
                    TagSpecifications=[
                        {
                            'ResourceType': 'snapshot',
                            'Tags': [
                                {'Key': 'Name', 'Value': snapshot_name_tag},
                                {'Key': 'InstanceId', 'Value': instance_id},
                                {'Key': 'InstanceName', 'Value': name_tag},
                                {'Key': 'VolumeId', 'Value': volume_id},
                                {'Key': 'CreatedBy', 'Value': 'lambda-ebs-full-instance-backup'},
                                {'Key': 'BackupDate', 'Value': date_str}
                            ]
                        }
                    ]
                )

                snap_id = resp['SnapshotId']
                snapshot_count += 1
                logger.info("Created snapshot %s for volume %s", snap_id, volume_id)

            except Exception as e:
                logger.exception("Failed to snapshot volume %s: %s", volume_id, str(e))

    logger.info("Backup completed. Snapshots created: %d", snapshot_count)
    return {"snapshots_created": snapshot_count}


def _find_instances_with_name_substring(substr):
    """Return list of instance dicts where Name tag contains substr (case-insensitive)."""
    substr_l = substr.lower()
    instances = []
    paginator = ec2.get_paginator('describe_instances')

    for page in paginator.paginate():
        for reservation in page.get('Reservations', []):
            for inst in reservation.get('Instances', []):
                name = _get_name_tag_value(inst.get('Tags', []))
                if name and substr_l in name.lower():
                    instances.append(inst)

    return instances


def _get_name_tag_value(tags):
    for t in tags:
        if t.get('Key') == 'Name':
            return t.get('Value')
    return None