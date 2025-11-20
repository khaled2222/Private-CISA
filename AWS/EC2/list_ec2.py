import boto3
import json
import datetime
import os

def json_converter(o):
    if isinstance(o, datetime.datetime):
        return o.isoformat()
    return str(o)

def list_instances():
    ec2 = boto3.client("ec2")

    response = ec2.describe_instances()

    # Extract instance details into a simple list
    instances = []

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            instances.append({
                "InstanceId": instance.get("InstanceId"),
                "InstanceType": instance.get("InstanceType"),
                "State": instance.get("State", {}).get("Name"),
                "LaunchTime": instance.get("LaunchTime"),
                "Tags": instance.get("Tags")
            })

    # Print JSON with datetime support
    print(json.dumps(instances, indent=4, default=json_converter))

if __name__ == "__main__":
    list_instances()
