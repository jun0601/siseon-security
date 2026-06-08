import json
import logging
import os
import hmac
import hashlib
import base64
import re
from datetime import datetime, timezone
from urllib import request, parse, error

import azure.functions as func

# 환경변수
WORKSPACE_ID = os.environ["LOG_ANALYTICS_WORKSPACE_ID"]
WORKSPACE_KEY = os.environ["LOG_ANALYTICS_WORKSPACE_KEY"]
LOG_TYPE = "CloudTrailLogs"

def build_signature(workspace_id, workspace_key, date, content_length, method, content_type, resource):
    x_headers = f"x-ms-date:{date}"
    string_to_hash = f"{method}\n{content_length}\n{content_type}\n{x_headers}\n{resource}"
    bytes_to_hash = string_to_hash.encode("utf-8")
    decoded_key = base64.b64decode(workspace_key)
    encoded_hash = base64.b64encode(
        hmac.new(decoded_key, bytes_to_hash, hashlib.sha256).digest()
    ).decode("utf-8")
    return f"SharedKey {workspace_id}:{encoded_hash}"

def post_to_log_analytics(body):
    method = "POST"
    content_type = "application/json"
    resource = "/api/logs"
    rfc1123date = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")
    content_length = len(body)

    signature = build_signature(
        WORKSPACE_ID, WORKSPACE_KEY,
        rfc1123date, content_length,
        method, content_type, resource
    )

    uri = f"https://{WORKSPACE_ID}.ods.opinsights.azure.com{resource}?api-version=2016-04-01"

    req = request.Request(
        uri,
        data=body.encode("utf-8"),
        method=method,
        headers={
            "Content-Type": content_type,
            "Authorization": signature,
            "Log-Type": LOG_TYPE,
            "x-ms-date": rfc1123date,
        }
    )

    with request.urlopen(req) as resp:
        if resp.status in (200, 202):
            logging.info(f"Log Analytics 전송 성공: {resp.status}")
        else:
            raise Exception(f"Log Analytics 전송 실패: {resp.status}")

def parse_cloudtrail_log(content: bytes) -> list:
    """CloudTrail JSON 로그 파싱"""
    try:
        data = json.loads(content)
        records = data.get("Records", [])
        parsed = []
        for r in records:
            parsed.append({
                "EventTime":       r.get("eventTime", ""),
                "EventName":       r.get("eventName", ""),
                "EventSource":     r.get("eventSource", ""),
                "AWSRegion":       r.get("awsRegion", ""),
                "SourceIPAddress": r.get("sourceIPAddress", ""),
                "UserAgent":       r.get("userAgent", ""),
                "UserIdentity":    json.dumps(r.get("userIdentity", {})),
                "RequestParams":   json.dumps(r.get("requestParameters", {})),
                "ResponseElements":json.dumps(r.get("responseElements", {})),
                "ErrorCode":       r.get("errorCode", ""),
                "ErrorMessage":    r.get("errorMessage", ""),
                "ReadOnly":        r.get("readOnly", False),
                "EventID":         r.get("eventID", ""),
                "EventType":       r.get("eventType", ""),
                "RecipientAccountId": r.get("recipientAccountId", ""),
            })
        return parsed
    except Exception as e:
        logging.error(f"CloudTrail 파싱 실패: {e}")
        return []

def main(myblob: func.InputStream):
    logging.info(f"Blob 처리 시작: {myblob.name}, 크기: {myblob.length} bytes")

    try:
        # gzip 여부 확인 (CloudTrail 로그는 .gz)
        content = myblob.read()
        if myblob.name.endswith(".gz"):
            import gzip
            content = gzip.decompress(content)

        records = parse_cloudtrail_log(content)

        if not records:
            logging.warning(f"파싱된 레코드 없음: {myblob.name}")
            return

        # 배치 전송 (Log Analytics 최대 30MB)
        batch_size = 500
        for i in range(0, len(records), batch_size):
            batch = records[i:i + batch_size]
            body = json.dumps(batch)
            post_to_log_analytics(body)
            logging.info(f"배치 전송 완료: {i}~{i+len(batch)}")

        logging.info(f"처리 완료: {myblob.name}, 총 {len(records)}개 레코드")

    except Exception as e:
        logging.error(f"처리 실패: {myblob.name} - {e}")
        raise