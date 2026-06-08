import json
import boto3
import os
import urllib.request
import urllib.parse
import hmac
import hashlib
import base64
from datetime import datetime, timezone

# 환경변수
AZURE_CONNECTION_STRING = os.environ["AZURE_CONNECTION_STRING"]
AZURE_CONTAINER_NAME = os.environ["AZURE_CONTAINER_NAME"]
SOURCE_BUCKET = os.environ["SOURCE_BUCKET"]
SOURCE_PREFIX = os.environ.get("SOURCE_PREFIX", "")

def lambda_handler(event, context):
    s3 = boto3.client("s3")
    
    # S3 버킷에서 오늘 날짜 기준 파일 목록 가져오기
    today = datetime.now(timezone.utc).strftime("%Y/%m/%d")
    prefix = f"{SOURCE_PREFIX}{today}/"
    
    response = s3.list_objects_v2(
        Bucket=SOURCE_BUCKET,
        Prefix=prefix
    )
    
    if "Contents" not in response:
        print(f"오늘 날짜({today}) 파일 없음")
        return {"statusCode": 200, "body": "No files to sync"}
    
    success = 0
    fail = 0
    
    for obj in response["Contents"]:
        key = obj["Key"]
        try:
            # S3에서 파일 다운로드
            s3_obj = s3.get_object(Bucket=SOURCE_BUCKET, Key=key)
            file_content = s3_obj["Body"].read()
            
            # Azure Blob에 업로드
            blob_name = key
            upload_to_azure(blob_name, file_content)
            print(f"업로드 성공: {key}")
            success += 1
        except Exception as e:
            print(f"업로드 실패: {key} - {e}")
            fail += 1
    
    return {
        "statusCode": 200,
        "body": f"성공: {success}, 실패: {fail}"
    }

def parse_connection_string(conn_str):
    """Azure 연결 문자열 파싱"""
    parts = {}
    for item in conn_str.split(";"):
        if "=" in item:
            key, value = item.split("=", 1)
            parts[key] = value
    return parts

def upload_to_azure(blob_name, content):
    """Azure Blob Storage에 파일 업로드 (REST API)"""
    conn = parse_connection_string(AZURE_CONNECTION_STRING)
    account_name = conn["AccountName"]
    account_key = conn["AccountKey"]
    
    # URL 인코딩
    encoded_blob = urllib.parse.quote(blob_name, safe="/")
    url = f"https://{account_name}.blob.core.windows.net/{AZURE_CONTAINER_NAME}/{encoded_blob}"
    
    # 헤더 생성
    date_str = datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S GMT")
    content_length = str(len(content))
    content_type = "application/octet-stream"
    
    # 서명 생성
    string_to_sign = (
        f"PUT\n\n\n{content_length}\n\n{content_type}\n\n\n\n\n\n\n"
        f"x-ms-blob-type:BlockBlob\nx-ms-date:{date_str}\nx-ms-version:2020-10-02\n"
        f"/{account_name}/{AZURE_CONTAINER_NAME}/{encoded_blob}"
    )
    
    decoded_key = base64.b64decode(account_key)
    signature = base64.b64encode(
        hmac.new(decoded_key, string_to_sign.encode("utf-8"), hashlib.sha256).digest()
    ).decode("utf-8")
    
    auth_header = f"SharedKey {account_name}:{signature}"
    
    req = urllib.request.Request(
        url,
        data=content,
        method="PUT",
        headers={
            "Authorization": auth_header,
            "x-ms-date": date_str,
            "x-ms-version": "2020-10-02",
            "x-ms-blob-type": "BlockBlob",
            "Content-Type": content_type,
            "Content-Length": content_length,
        }
    )
    
    with urllib.request.urlopen(req) as response:
        print(f"Azure 응답: {response.status}")