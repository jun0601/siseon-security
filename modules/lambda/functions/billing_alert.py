import json
import urllib.request
import urllib.error
import os
from datetime import datetime, timezone, timedelta

WEBHOOK_URL = os.environ["TEAMS_WEBHOOK_URL"]
KST = timezone(timedelta(hours=9))

def lambda_handler(event, context):
    for record in event.get("Records", []):
        sns_message = json.loads(record["Sns"]["Message"])

        alarm_name = sns_message.get("AlarmName", "")
        new_state  = sns_message.get("NewStateValue", "")
        reason     = sns_message.get("NewStateReason", "")
        timestamp  = sns_message.get("StateChangeTime", "")

        if new_state != "ALARM":
            continue

        # KST 변환
        try:
            event_time = datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%S.%f%z")
            event_time_kst = event_time.astimezone(KST).strftime("%Y-%m-%d %H:%M:%S KST")
        except Exception:
            try:
                event_time = datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ")
                event_time_kst = event_time.replace(tzinfo=timezone.utc).astimezone(KST).strftime("%Y-%m-%d %H:%M:%S KST")
            except Exception:
                event_time_kst = timestamp

        if "daily" in alarm_name.lower():
            emoji       = "⚠️"
            period_text = "일별"
            threshold   = "$5"
        else:
            emoji       = "🚨"
            period_text = "월별"
            threshold   = "$60"

        message = (
            f"{emoji} AWS 비용 경보<br>"
            f"📊 유형: {period_text} 예산 초과<br>"
            f"💰 임계값: {threshold}<br>"
            f"📋 사유: {reason}<br>"
            f"⏰ 시간: {event_time_kst}"
        )

        send_to_teams(message)

    return {"statusCode": 200, "body": "OK"}

def send_to_teams(message):
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