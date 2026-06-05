# 🛡️ StockOps 보안/감사 모니터링 설계 문서

> CloudTrail 기반 실시간 보안 이벤트 감지 파이프라인 설계 및 구현 문서

---

## 🏗️ 전체 아키텍처

```
┌─────────────────────────────────────────────────────┐
│                   AWS 계정 이벤트                     │
│  (콘솔 로그인 / 리소스 생성·수정·삭제 / API 호출)       │
└──────────────────────┬──────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────┐
│                   AWS CloudTrail                      │
│  • 관리 이벤트 수집 (Management Events)               │
│  • 멀티 리전 추적 (is_multi_region_trail = true)      │
│  • 글로벌 서비스 이벤트 포함                           │
└──────────┬───────────────────────┬───────────────────┘
           ↓                       ↓
┌──────────────────┐    ┌──────────────────────────────┐
│   Amazon S3      │    │  CloudWatch Logs              │
│  (장기 보관)      │    │  (/aws/cloudtrail)            │
│  30d → IA        │    │  보존: 90일                   │
│  90d → Glacier   │    └──────────┬───────────────────┘
│  365d → 삭제      │               ↓
└──────────────────┘    ┌──────────────────────────────┐
                        │  Subscription Filter          │
                        │  (이벤트 패턴 실시간 매칭)      │
                        │  • ConsoleLogin               │
                        │  • Delete* / Remove* /        │
                        │    Terminate*                 │
                        └──────────┬───────────────────┘
                                   ↓
                        ┌──────────────────────────────┐
                        │      AWS Lambda (Python)      │
                        │  • gzip 압축 해제             │
                        │  • CloudTrail 로그 파싱       │
                        │  • 사용자/IP/리전/시간 추출   │
                        │  • KST 시간 변환              │
                        └──────────┬───────────────────┘
                                   ↓
                        ┌──────────────────────────────┐
                        │    Power Automate 웹훅        │
                        └──────────┬───────────────────┘
                                   ↓
                        ┌──────────────────────────────┐
                        │   Microsoft Teams 채널        │
                        │  • aws-logins (로그인 알림)   │
                        │  • aws-alerts (삭제 알림)     │
                        └──────────────────────────────┘
```

---

## 📌 설계 결정 사항

### CloudWatch Alarm 방식 → Subscription Filter 방식으로 전환

초기에는 `CloudTrail → CloudWatch Metric Filter → Alarm → SNS → Lambda` 방식을 채택했습니다.
그러나 이 방식은 **Alarm 상태가 변경될 때만 SNS를 발행**하는 구조로, 동일 상태가 유지되면 알림이 발송되지 않는 문제가 있었습니다.

```
# 문제 시나리오
1. jh.lee 로그인 → OK → ALARM → 알림 ✅
2. zo.kim 로그인 → 이미 ALARM 상태 → 알림 ❌ (상태 변화 없음)
```

이를 해결하기 위해 `CloudWatch Logs Subscription Filter → Lambda` 방식으로 전환했습니다.
이 방식은 **로그 이벤트 발생 즉시 Lambda를 트리거**하여 매 이벤트마다 알림을 보낼 수 있습니다.

| 구분 | Alarm 방식 | Subscription Filter 방식 |
|------|-----------|------------------------|
| 알림 트리거 | Alarm 상태 변경 시 | 이벤트 발생 즉시 |
| 상세 정보 | Alarm 메타데이터만 | CloudTrail 원문 파싱 가능 |
| 실시간성 | 5분 집계 후 | 즉시 (수초 내) |
| 유연성 | 제한적 | 커스텀 파싱 가능 |

---

## ⚙️ Lambda 함수 설계

### 공통 처리 흐름

```python
def lambda_handler(event, context):
    # 1. CloudWatch Logs 데이터 디코딩
    log_data = event["awslogs"]["data"]
    decoded = gzip.decompress(base64.b64decode(log_data))
    log_events = json.loads(decoded)

    # 2. 각 로그 이벤트 처리
    for log_event in log_events.get("logEvents", []):
        record = json.loads(log_event["message"])  # CloudTrail 원문

        # 3. 이벤트 필터링
        if record.get("eventName") != "ConsoleLogin":
            continue

        # 4. 정보 추출
        username = record["userIdentity"].get("userName") \
                   or record["userIdentity"]["arn"].split("/")[-1]
        source_ip = record["sourceIPAddress"]
        region    = record["awsRegion"]

        # 5. KST 변환
        event_time = datetime.strptime(record["eventTime"], "%Y-%m-%dT%H:%M:%SZ")
        event_time_kst = event_time.replace(tzinfo=timezone.utc).astimezone(KST)

        # 6. Teams 웹훅 전송
        send_to_teams(payload)
```

### IAM Identity Center 사용자 파싱

IAM Identity Center(SSO) 계정은 `userIdentity.userName` 필드가 없습니다.
대신 `arn` 필드에서 세션 이름(사용자명)을 추출합니다.

```python
# IAM Identity Center 사용자 ARN 예시
# arn:aws:sts::448768137813:assumed-role/AWSReservedSSO_.../jh.lee

username = user_identity.get("userName") \
           or user_identity.get("arn", "Unknown").split("/")[-1]
# → "jh.lee"
```

### 웹훅 메시지 포맷

Teams는 일반 텍스트에서 `\n` 줄바꿈을 지원하지 않습니다.
HTML `<br>` 태그를 사용하여 줄바꿈을 처리합니다.

```python
message = (
    f"🔐 콘솔 로그인 감지<br>"
    f"👤 사용자: {username}<br>"
    f"🌐 IP: {source_ip}<br>"
    f"📍 리전: {region}<br>"
    f"🔎 결과: {result}<br>"
    f"⏰ 시간: {event_time_kst}"
)
```

---

## 🗂️ Terraform 모듈 구조

### cloudtrail 모듈

| 리소스 | 설명 |
|--------|------|
| `data.aws_s3_bucket` | 기존 CloudTrail S3 버킷 참조 |
| `aws_s3_bucket_lifecycle_configuration` | 30d→IA, 90d→Glacier, 365d→삭제 |
| `aws_cloudwatch_log_group` | `/aws/cloudtrail` 로그 그룹 |
| `aws_iam_role` | CloudTrail → CloudWatch 전송 역할 |
| `aws_cloudtrail` | 멀티 리전 추적 생성 |

### lambda 모듈

| 리소스 | 설명 |
|--------|------|
| `aws_iam_role` | Lambda 실행 역할 |
| `data.archive_file` | Python 코드 → ZIP 패키징 |
| `aws_lambda_function` | 로그인/삭제 감지 함수 |
| `aws_lambda_permission` | CloudWatch Logs 트리거 권한 |
| `aws_cloudwatch_log_subscription_filter` | 이벤트 패턴 필터 + Lambda 연결 |

### cloudwatch 모듈

| 리소스 | 설명 |
|--------|------|
| `aws_cloudwatch_log_metric_filter` | 지표 필터 (대시보드/모니터링용) |
| `aws_cloudwatch_metric_alarm` | 임계값 기반 경보 (SNS 미연결) |

---

## 🔑 IAM 권한 설계 (최소 권한 원칙)

### CloudTrail → CloudWatch IAM 역할

```json
{
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogStream",
    "logs:PutLogEvents"
  ],
  "Resource": "arn:aws:logs:*:*:log-group:/aws/cloudtrail:*"
}
```

### Lambda 실행 역할

```
AWSLambdaBasicExecutionRole (AWS 관리형 정책)
→ CloudWatch Logs 기록 권한만 부여
```

### Lambda 트리거 권한

```json
{
  "Action": "lambda:InvokeFunction",
  "Principal": "logs.amazonaws.com",
  "SourceArn": "arn:aws:logs:...:log-group:/aws/cloudtrail:*"
}
```

---

## 📊 CloudWatch Metric Filter

Subscription Filter와 별도로 Metric Filter를 유지합니다.
알림용이 아닌 **대시보드 시각화 및 장기 지표 모니터링** 목적입니다.

| 필터 | 패턴 | 지표 |
|------|------|------|
| `siseon-filter-console-login` | `{ $.eventName = "ConsoleLogin" }` | `SiseonSecurity/ConsoleLoginCount` |
| `siseon-filter-delete-action` | `{ ($.eventName = "Delete*") \|\| ... }` | `SiseonSecurity/DeleteActionCount` |