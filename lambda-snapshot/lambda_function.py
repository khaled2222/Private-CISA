import boto3
import os
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ec2 = boto3.client('ec2')

MATCH_SUBSTRING = os.environ.get('MATCH_SUBSTRING', 'khaled')

def lambda_handler(event, context):
    logger.info("Starting EBS snapshot job. Searching instances containing: %s", MATCH_SUBSTRING)

    instances = _find_instances_with_name_substring(MATCH_SUBSTRING)
    snapshot_count = 0

    for inst in instances:
        instance_id = inst['InstanceId']
        name_tag = _get_name_tag_value(inst.get('Tags', []))

        logger.info("Processing instance %s (Name=%s)", instance_id, name_tag)

        for mapping in inst.get('BlockDeviceMappings', []):
            ebs = mapping.get('Ebs')
            if not ebs:
                continue

            vol_id = ebs.get('VolumeId')

            description = f"Snapshot of {vol_id} from instance {instance_id} ({name_tag}) taken at {datetime.utcnow().isoformat()}Z"

            resp = ec2.create_snapshot(
                VolumeId=vol_id,
                Description=description,
                TagSpecifications=[
                    {
                        'ResourceType': 'snapshot',
                        'Tags': [
                            {'Key': 'CreatedBy', 'Value': 'lambda-ebs-snapshot'},
                            {'Key': 'InstanceId', 'Value': instance_id},
                            {'Key': 'InstanceName', 'Value': name_tag or ''},
                            {'Key': 'VolumeId', 'Value': vol_id},
                            {'Key': 'CreatedOnUTC', 'Value': datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}
                        ]
                    }
                ]
            )
            logger.info("Created snapshot %s for volume %s", resp['SnapshotId'], vol_id)
            snapshot_count += 1

    logger.info("Job done. Total snapshots created: %d", snapshot_count)
    return {"snapshots_created": snapshot_count}


def _find_instances_with_name_substring(substr):
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
