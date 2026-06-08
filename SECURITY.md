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
                        │  • AWS 서비스 이벤트 필터링   │
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

### AWS 서비스 이벤트 필터링

Terraform destroy 또는 AWS 내부 자동화 작업 시 `AutoScaling`, `EKS`, `ElasticLoadBalancing` 등
AWS 서비스가 자동으로 리소스를 삭제하는 이벤트가 다수 발생합니다.
이러한 이벤트는 사람이 한 작업이 아니므로 필터링하여 알림 노이즈를 줄입니다.

```python
# AWS 내부 서비스 IP 목록 (사람이 한 작업 아님 → 스킵)
AWS_SERVICE_IPS = (
    "amazonaws.com",
    "elasticloadbalancing.amazonaws.com",
    "eks.amazonaws.com",
    "autoscaling.amazonaws.com",
    "rds.amazonaws.com",
    "eks-nodegroup.amazonaws.com",
)

# sourceIPAddress가 AWS 서비스면 스킵
if any(source_ip.endswith(svc) for svc in AWS_SERVICE_IPS):
    continue
```

### IAM Identity Center 사용자 파싱

IAM Identity Center(SSO) 계정은 `userIdentity.userName` 필드가 없습니다.
대신 `arn` 필드에서 세션 이름(사용자명)을 추출합니다.
SDK 세션 이름(`aws-go-sdk-...`)인 경우 `sessionIssuer.userName` 으로 대체합니다.

```python
def parse_username(user_identity):
    user_type = user_identity.get("type", "")

    if user_type == "AssumedRole":
        on_behalf_of = user_identity.get("onBehalfOf")
        if on_behalf_of:
            arn = user_identity.get("arn", "")
            username = arn.split("/")[-1]
            # SDK 세션이름 패턴이면 sessionIssuer에서 가져오기
            if username.startswith("aws-") or username.isdigit():
                session_issuer = user_identity.get("sessionContext", {}).get("sessionIssuer", {})
                username = session_issuer.get("userName", "Unknown")
            return username  # → "jh.lee"
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

## 🗄️ Terraform Remote Backend (S3)

### 설계 목적

로컬에 tfstate 파일을 두면 팀원 간 상태 충돌, 민감 정보 노출, PC 분실 시 상태 손실 등의 문제가 발생합니다.
S3 Remote Backend를 통해 이를 해결합니다.

| 목적 | 설명 |
|------|------|
| 팀 협업 | tfstate 중앙 관리로 상태 충돌 방지 |
| 보안 | 민감 정보(DB 비밀번호 등) GitHub 노출 차단 |
| 가용성 | 어느 PC에서든 동일한 상태로 작업 가능 |
| 복구 | S3 버저닝으로 tfstate 변경 이력 관리 |

### 구성

```hcl
terraform {
  backend "s3" {
    bucket  = "siseon-terraform-state"
    key     = "security/terraform.tfstate"
    region  = "ap-northeast-2"
    profile = "siseon"
  }
}
```

### 파트별 key 구성

| 파트 | key |
|------|-----|
| siseon-security | `security/terraform.tfstate` |
| siseon-infra | `infra/terraform.tfstate` |
| siseon-infra-monitoring | `monitoring/terraform.tfstate` |

### 초기 설정 방법

```bash
# S3 버킷 생성
aws s3 mb s3://siseon-terraform-state --region ap-northeast-2 --profile siseon

# S3 버저닝 활성화
aws s3api put-bucket-versioning \
  --bucket siseon-terraform-state \
  --versioning-configuration Status=Enabled \
  --profile siseon

# providers.tf에 backend 블록 추가 후
terraform init -migrate-state  # 로컬 tfstate → S3 자동 이관
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