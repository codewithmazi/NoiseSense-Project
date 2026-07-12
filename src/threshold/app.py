"""Threshold Lambda.

This Lambda function is triggered by EventBridge on each MetricsReceived event. It compares the reading's
dB(A) against a configured threshold and, if exceeded, publishes an alert to SNS, notifying users.
"""
import json
import os

import boto3

ALERT_TOPIC_ARN = os.environ["ALERT_TOPIC_ARN"]
THRESHOLD_DBA = float(os.environ.get("THRESHOLD_DBA", "70"))

_sns = boto3.client("sns")


def handler(event, context):
    detail = event.get("detail", {})
    db_a = detail.get("dbA")
    user_id = detail.get("userId", "unknown")
    timestamp = detail.get("timestamp", "")

    if db_a is None:
        return {"evaluated": False, "reason": "no dbA in event"}

    if float(db_a) > THRESHOLD_DBA:
        message = (
            f"Noise exposure alert: {db_a} dB(A) exceeded the {THRESHOLD_DBA} dB(A) "
            f"threshold at {timestamp}."
        )
        _sns.publish(
            TopicArn=ALERT_TOPIC_ARN,
            Subject="Noise exposure alert",
            Message=message,
            MessageAttributes={
                "userId": {"DataType": "String", "StringValue": str(user_id)}
            },
        )
        return {"evaluated": True, "alerted": True, "dbA": db_a}

    return {"evaluated": True, "alerted": False, "dbA": db_a}