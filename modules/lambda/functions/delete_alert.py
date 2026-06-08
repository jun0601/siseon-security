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

# AWS 내부 서비스 IP (사람이 한 작업 아님 → 스킵)
AWS_SERVICE_IPS = (
    "amazonaws.com",
    "elasticloadbalancing.amazonaws.com",
    "eks.amazonaws.com",
    "autoscaling.amazonaws.com",
    "rds.amazonaws.com",
    "eks-nodegroup.amazonaws.com",
)

def parse_username(user_identity):
    """사용자명 파싱 - IAM Identity Center SSO 계정 포함"""
    user_type = user_identity.get("type", "")

    # IAM Identity Center SSO 사용자
    if user_type == "AssumedRole":
        # sessionIssuer에서 실제 사용자명 추출
        session_context = user_identity.get("sessionContext", {})
        session_issuer = session_context.get("sessionIssuer", {})

        # onBehalfOf가 있으면 SSO 사용자
        on_behalf_of = user_identity.get("onBehalfOf")
        if on_behalf_of:
            # ARN 마지막 부분이 실제 사용자명 (jh.lee 등)
            arn = user_identity.get("arn", "")
            username = arn.split("/")[-1]
            # sdk 세션이름 패턴이면 sessionIssuer에서 가져오기
            if username.startswith("aws-") or username.isdigit():
                username = session_issuer.get("userName", "Unknown")
            return username

        # 일반 AssumedRole
        arn = user_identity.get("arn", "")
        username = arn.split("/")[-1]
        if username.startswith("aws-") or username.isdigit():
            username = session_issuer.get("userName", "AWSService")
        return username

    # IAM 사용자
    if user_type == "IAMUser":
        return user_identity.get("userName", "Unknown")

    # AWS 서비스
    if user_type in ("Service", "AWSService"):
        return user_identity.get("invokedBy", "AWSService")

    return user_identity.get("userName") or user_identity.get("arn", "Unknown").split("/")[-1]


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

        source_ip = record.get("sourceIPAddress", "")

        # AWS 내부 서비스가 한 작업 스킵
        if any(source_ip.endswith(svc) for svc in AWS_SERVICE_IPS):
            continue

        user_identity = record.get("userIdentity", {})
        username = parse_username(user_identity)
        region = record.get("awsRegion", "Unknown")
        event_time_str = record.get("eventTime", "")

        # 리소스 파싱
        resources = record.get("resources", [])
        if resources:
            resource_name = resources[0].get("ARN", "Unknown").split(":")[-1]
        else:
            request_params = record.get("requestParameters", {})
            resource_name = next(iter(request_params.values()), "Unknown") if request_params else "Unknown"

        # 시간 KST 변환
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