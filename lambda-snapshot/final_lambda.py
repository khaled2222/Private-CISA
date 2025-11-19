import boto3
from datetime import datetime
import os

ec2 = boto3.client("ec2")

def lambda_handler(event, context):
    search_str = os.environ["MATCH_SUBSTRING"]
    today = datetime.now().strftime("%Y-%m-%d")

    # Find instances with Name tag containing target string
    instances = ec2.describe_instances(
        Filters=[
            {"Name": "tag:Name", "Values": [f"*{search_str}*"]}
        ]
    )

    for reservation in instances["Reservations"]:
        for instance in reservation["Instances"]:
            instance_id = instance["InstanceId"]
            print(f"Processing instance: {instance_id}")

            # Snapshot each volume
            for vol in instance.get("BlockDeviceMappings", []):
                volume_id = vol["Ebs"]["VolumeId"]

                description = f"Backup {instance_id} volume {volume_id} on {today}"
                snapshot = ec2.create_snapshot(
                    VolumeId=volume_id,
                    Description=description
                )

                # Add tags including date
                ec2.create_tags(
                    Resources=[snapshot["SnapshotId"]],
                    Tags=[
                        {"Key": "Name", "Value": f"{instance_id}-{today}"},
                        {"Key": "CreatedBy", "Value": "Lambda-EBS-Backup"}
                    ]
                )

                print(f"Snapshot created: {snapshot['SnapshotId']}")

    return {"status": "completed"}
