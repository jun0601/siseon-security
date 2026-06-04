import json
import urllib.request
import urllib.error
import gzip
import base64
import os
from datetime import datetime, timezone, timedelta

WEBHOOK_URL = os.environ["TEAMS_WEBHOOK_URL"]
KST = timezone(timedelta(hours=9))
DELETE_ACTIONS = ("Delete", "Remove", "Terminate")

def lambda_handler(event, context):
    log_data = event["awslogs"]["data"]
    decoded = gzip.decompress(base64.b64decode(log_data))
    log_events = json.loads(decoded)

    for log_event in log_events.get("logEvents", []):
        try:
            record = json.loads(log_event["message"])
        except json.JSONDecodeError:
            continue

        event_name = record.get("eventName", "")
        if not any(event_name.startswith(action) for action in DELETE_ACTIONS):
            continue

        user_identity = record.get("userIdentity", {})
        username = user_identity.get("userName") or user_identity.get("arn", "Unknown").split("/")[-1]
        source_ip = record.get("sourceIPAddress", "Unknown")
        region = record.get("awsRegion", "Unknown")
        event_time_str = record.get("eventTime", "")

        resources = record.get("resources", [])
        if resources:
            resource_name = resources[0].get("ARN", "Unknown").split(":")[-1]
        else:
            resource_name = record.get("requestParameters", {})
            resource_name = next(iter(resource_name.values()), "Unknown") if resource_name else "Unknown"

        try:
            event_time = datetime.strptime(event_time_str, "%Y-%m-%dT%H:%M:%SZ")
            event_time = event_time.replace(tzinfo=timezone.utc).astimezone(KST)
            event_time_kst = event_time.strftime("%Y-%m-%d %H:%M:%S KST")
        except Exception:
            event_time_kst = event_time_str

        send_to_teams({
            "event_name": event_name,
            "username": username,
            "resource_name": resource_name,
            "source_ip": source_ip,
            "region": region,
            "event_time": event_time_kst
        })

    return {"statusCode": 200, "body": "OK"}

def send_to_teams(payload):
    message = (
        f"🚨 리소스 삭제 작업 감지<br>"
        f"👤 사용자: {payload['username']}<br>"
        f"🛠️ 작업: {payload['event_name']}<br>"
        f"📦 리소스: {payload['resource_name']}<br>"
        f"🌐 IP: {payload['source_ip']}<br>"
        f"📍 리전: {payload['region']}<br>"
        f"⏰ 시간: {payload['event_time']}"
    )

    data = json.dumps({"message": message}).encode("utf-8")
    req = urllib.request.Request(
        WEBHOOK_URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            print(f"Teams 전송 성공: {response.status}")
    except urllib.error.URLError as e:
        print(f"Teams 전송 실패: {e.reason}")
        raise