import json
import urllib.request
import urllib.error
import os
import boto3
from datetime import datetime, timezone, timedelta

WEBHOOK_URL = os.environ["TEAMS_WEBHOOK_URL"]
DAILY_THRESHOLD = 5.0
MONTHLY_THRESHOLD = 60.0
KST = timezone(timedelta(hours=9))

ce = boto3.client("ce", region_name="us-east-1")

def get_cost(granularity, start, end):
    response = ce.get_cost_and_usage(
        TimePeriod={"Start": start, "End": end},
        Granularity=granularity,
        Metrics=["UnblendedCost"]
    )
    return float(response["ResultsByTime"][0]["Total"]["UnblendedCost"]["Amount"])

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

def lambda_handler(event, context):
    now_kst = datetime.now(KST)
    today = now_kst.date()
    yesterday = today - timedelta(days=1)
    month_start = today.replace(day=1)

    # 일별 비용 (어제)
    daily_cost = get_cost("DAILY", str(yesterday), str(today))
    print(f"일별 비용 ({yesterday}): ${daily_cost:.2f}")

    # 월별 비용 (이번달 누적)
    monthly_cost = get_cost("MONTHLY", str(month_start), str(today))
    print(f"월별 누적 비용 ({month_start} ~ {today}): ${monthly_cost:.2f}")

    now_str = now_kst.strftime("%Y-%m-%d %H:%M:%S KST")
    alerted = False

    if daily_cost > DAILY_THRESHOLD:
        message = (
            f"⚠️ AWS 비용 경보<br>"
            f"📊 유형: 일별 예산 초과<br>"
            f"📅 날짜: {yesterday}<br>"
            f"💰 실제 비용: ${daily_cost:.2f} / 임계값: ${DAILY_THRESHOLD}<br>"
            f"⏰ 시간: {now_str}"
        )
        send_to_teams(message)
        alerted = True

    if monthly_cost > MONTHLY_THRESHOLD:
        message = (
            f"🚨 AWS 비용 경보<br>"
            f"📊 유형: 월별 예산 초과<br>"
            f"📅 기간: {month_start} ~ {today}<br>"
            f"💰 누적 비용: ${monthly_cost:.2f} / 임계값: ${MONTHLY_THRESHOLD}<br>"
            f"⏰ 시간: {now_str}"
        )
        send_to_teams(message)
        alerted = True

    if not alerted:
        print(f"정상 범위 - 일별: ${daily_cost:.2f}, 월별: ${monthly_cost:.2f}")

    return {"statusCode": 200, "daily": daily_cost, "monthly": monthly_cost}