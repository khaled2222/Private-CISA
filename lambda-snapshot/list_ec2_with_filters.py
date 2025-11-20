#!/usr/bin/env python3
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

    # -------------------------------
    # FILTER EXAMPLES (uncomment what you need)
    # -------------------------------

    filters = [

        # Example 1: Filter by instance-id
        # {
        #     "Name": "instance-id",
        #     "Values": ["i-0123456789abcdef0"]
        # },

        # Example 2: Filter by EC2 tag (tag:Name = MyServer)
        # {
        #     "Name": "tag:Name",
        #     "Values": ["MyServer"]
        # },

        # Example 3: Filter by tag Environment = Prod
        # {
        #     "Name": "tag:Environment",
        #     "Values": ["Prod"]
        # },

        # Example 4: Filter by instance state
        # {
        #     "Name": "instance-state-name",
        #     "Values": ["running", "stopped"]
        # },

    ]

    # If no filters are used, describe_instances() retrieves all instances
    if filters:
        response = ec2.describe_instances(Filters=filters)
    else:
        response = ec2.describe_instances()

    instances = []

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:
            instances.append({
                "InstanceId": instance.get("InstanceId"),
                "InstanceType": instance.get("InstanceType"),
                "State": instance.get("State", {}).get("Name"),
                "LaunchTime": instance.get("LaunchTime"),
                "PrivateIpAddress": instance.get("PrivateIpAddress"),
                "PublicIpAddress": instance.get("PublicIpAddress"),
                "Tags": instance.get("Tags")
            })

    print(json.dumps(instances, indent=4, default=json_converter))


if __name__ == "__main__":
    list_instances()
