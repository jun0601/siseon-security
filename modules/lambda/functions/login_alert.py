import json
import urllib.request
import urllib.error
import gzip
import base64
import os
from datetime import datetime, timezone, timedelta

WEBHOOK_URL = os.environ["TEAMS_WEBHOOK_URL"]
KST = timezone(timedelta(hours=9))

def lambda_handler(event, context):
    log_data = event["awslogs"]["data"]
    decoded = gzip.decompress(base64.b64decode(log_data))
    log_events = json.loads(decoded)

    for log_event in log_events.get("logEvents", []):
        try:
            record = json.loads(log_event["message"])
        except json.JSONDecodeError:
            continue

        if record.get("eventName") != "ConsoleLogin":
            continue

        user_identity = record.get("userIdentity", {})
        username = user_identity.get("userName") or user_identity.get("arn", "Unknown").split("/")[-1]
        source_ip = record.get("sourceIPAddress", "Unknown")
        region = record.get("awsRegion", "Unknown")
        result = record.get("responseElements", {}).get("ConsoleLogin", "Unknown")
        event_time_str = record.get("eventTime", "")

        try:
            event_time = datetime.strptime(event_time_str, "%Y-%m-%dT%H:%M:%SZ")
            event_time = event_time.replace(tzinfo=timezone.utc).astimezone(KST)
            event_time_kst = event_time.strftime("%Y-%m-%d %H:%M:%S KST")
        except Exception:
            event_time_kst = event_time_str

        result_emoji = "✅" if result == "Success" else "❌"

        send_to_teams({
            "title": "🔐 콘솔 로그인 감지",
            "username": username,
            "source_ip": source_ip,
            "region": region,
            "result": f"{result_emoji} {result}",
            "event_time": event_time_kst
        })

    return {"statusCode": 200, "body": "OK"}

def send_to_teams(payload):
    message = (
        f"{payload['title']}<br>"
        f"👤 사용자: {payload['username']}<br>"
        f"🌐 IP: {payload['source_ip']}<br>"
        f"📍 리전: {payload['region']}<br>"
        f"🔎 결과: {payload['result']}<br>"
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