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
│        ↓          │    ┌──────────────────────────────┐
│  Lambda (매일)    │    │  Subscription Filter          │
│  KST 02:00       │    │  (이벤트 패턴 실시간 매칭)      │
└────────┬─────────┘    │  • ConsoleLogin               │
         ↓              │  • Delete* / Remove* /        │
┌──────────────────┐    │    Terminate*                 │
│  Azure Blob      │    └──────────┬───────────────────┘
│  cloudtrail-     │               ↓
│  backup          │    ┌──────────────────────────────┐
│  (재해복구 백업)  │    │      AWS Lambda (Python)      │
│        ↓          │    │  • gzip 압축 해제             │
│  Azure Function  │    │  • CloudTrail 로그 파싱       │
│  (Blob 트리거)   │    │  • AWS 서비스 이벤트 필터링   │
│        ↓          │    │  • 사용자/IP/리전/시간 추출   │
│  Log Analytics   │    │  • KST 시간 변환              │
│  Workspace       │    └──────────┬───────────────────┘
│        ↓          │               ↓
│  Azure Monitor   │    ┌──────────────────────────────┐
│  Workbook        │    │    Power Automate 웹훅        │
│  (페일오버 대시  │    └──────────┬───────────────────┘
│   보드)          │               ↓
└──────────────────┘    ┌──────────────────────────────┐
                        │   Microsoft Teams 채널        │
                        │  • aws-logins (로그인 알림)   │
                        │  • aws-alerts (삭제 알림)     │
                        │  • aws-billing (비용 경보)    │
                        └──────────────────────────────┘

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

┌──────────────────────────────────────────┐
│           AWS Budgets (비용 모니터링)      │
│  • 일별 $5 초과 경보                      │
│  • 월별 $60 초과 경보                     │
└──────────────────┬───────────────────────┘
                   ↓
          SNS 토픽 → Lambda → Teams
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

## ☁️ S3 → Azure Blob 동기화 설계

### 목적

AWS 전체 장애 시에도 보안 감사 로그를 확인할 수 있도록
CloudTrail 로그를 Azure Blob Storage에 이중 백업합니다.
보안 감사는 장애 상황에서도 중단되면 안 되기 때문입니다.

```
S3 (CloudTrail 로그 원본)
        ↓
Lambda (매일 KST 02:00 EventBridge 트리거)
  • 날짜 파라미터 있으면 해당 기간 동기화 (백필용)
  • 파라미터 없으면 오늘 날짜 기준 동기화 (크론 기본 동작)
        ↓
Azure Blob Storage
siseonstorage/cloudtrail-backup/
AWSLogs/448768137813/CloudTrail/ap-northeast-2/YYYY/MM/DD/
```

### 동기화 구성

| 항목 | 값 |
|------|-----|
| 소스 버킷 | `aws-cloudtrail-logs-448768137813-05d6a32b` |
| 소스 경로 | `AWSLogs/448768137813/CloudTrail/ap-northeast-2/` |
| 대상 스토리지 | `siseonstorage` (Azure Blob, Korea Central) |
| 대상 컨테이너 | `cloudtrail-backup` |
| 실행 주기 | 매일 KST 02:00 (`cron(0 17 * * ? *)`) |
| Lambda 함수 | `siseon-lambda-s3-to-azure` |

### Lambda 핵심 로직

```python
def lambda_handler(event, context):
    # 날짜 범위 파라미터 지원 (백필용)
    if "start_date" in event and "end_date" in event:
        dates = generate_date_range(event["start_date"], event["end_date"])
    else:
        # 크론탭 실행 시 오늘 날짜 기준 (기존 동작 유지)
        dates = [datetime.now(timezone.utc).strftime("%Y/%m/%d")]

    for today in dates:
        prefix = f"{SOURCE_PREFIX}{today}/"
        response = s3.list_objects_v2(Bucket=SOURCE_BUCKET, Prefix=prefix)
        for obj in response.get("Contents", []):
            file_content = s3.get_object(
                Bucket=SOURCE_BUCKET, Key=obj["Key"]
            )["Body"].read()
            upload_to_azure(obj["Key"], file_content)
```

### 수동 백필 방법 (Lambda 테스트 이벤트)

```json
{
  "start_date": "2026-06-02",
  "end_date": "2026-06-07"
}
```

### S3 읽기 IAM 권한

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::aws-cloudtrail-logs-448768137813-05d6a32b",
    "arn:aws:s3:::aws-cloudtrail-logs-448768137813-05d6a32b/*"
  ]
}
```

---

## 🔵 Azure Monitor 페일오버 모니터링 설계

### 설계 목적

AWS 장애 시나리오에서 Azure Blob에 백업된 CloudTrail 로그를
Azure Monitor Workbook으로 시각화하여 보안 감사를 중단 없이 수행합니다.

### 파이프라인 구성

```
Azure Blob (cloudtrail-backup)
        ↓ Blob 트리거 (파일 업로드 즉시 자동 실행)
Azure Function (siseon-blob-to-laws, Python 3.11)
  • CloudTrail .gz 파일 압축 해제
  • JSON Records[] 파싱
  • 500건 단위 배치 전송
        ↓ Log Analytics Data Collector API
Log Analytics Workspace (siseon-security-logs)
  • 테이블명: CloudTrailLogs_CL
  • 보존: 30일 (PerGB2018 SKU)
        ↓ KQL 쿼리
Azure Monitor Workbook
  • CloudTrail 이벤트 현황 Top 10 (바차트)
  • 오류 발생 이벤트 (테이블)
  • 소스 IP별 접근 현황 (파이차트)
  • 시간대별 이벤트 추이 (타임차트)
```

### Terraform 멀티클라우드 통합 관리

단일 Terraform 프로젝트에서 AWS와 Azure 리소스를 통합 관리합니다.

```hcl
# providers.tf
provider "aws" {
  region  = var.aws_region
  profile = "siseon"
}

provider "azurerm" {
  features {}
  tenant_id       = var.azure_tenant_id
  subscription_id = var.azure_subscription_id
}
```

### Azure Function 배포 방식

Terraform은 Azure Function App 인프라만 생성하고,
실제 Python 코드는 Azure Functions Core Tools로 별도 배포합니다.

```bash
cd modules/azure_monitor/functions
func azure functionapp publish siseon-blob-to-laws --python
```

### Azure 리소스 구성

| 리소스 | 이름 | 설명 |
|--------|------|------|
| Log Analytics Workspace | siseon-security-logs | CloudTrail 로그 수집/쿼리 |
| Function App | siseon-blob-to-laws | Blob 트리거 → Log Analytics 전송 |
| App Service Plan | siseon-func-plan | Consumption(Y1) 무료 티어 |
| Storage Account | siseonfuncstore | Function App 내부 스토리지 |
| Azure Workbook | StockOps CloudTrail 보안 감사 대시보드 | KQL 기반 시각화 |

### CloudTrailLogs_CL 테이블 스키마

| 필드 | 타입 | 설명 |
|------|------|------|
| EventTime_t | datetime | 이벤트 발생 시각 |
| EventName_s | string | API 이름 (ConsoleLogin, DeleteBucket 등) |
| EventSource_s | string | AWS 서비스 (signin.amazonaws.com 등) |
| AWSRegion_s | string | 이벤트 발생 리전 |
| SourceIPAddress_s | string | 요청 소스 IP |
| UserAgent_s | string | 클라이언트 에이전트 |
| UserIdentity_s | string | 사용자 정보 (JSON) |
| ErrorCode_s | string | 오류 코드 (정상 시 공백) |
| ErrorMessage_s | string | 오류 메시지 |
| EventID_s | string | 이벤트 고유 ID |

### KQL 쿼리 예시

```kusto
// 이벤트 현황 Top 10
CloudTrailLogs_CL
| where TimeGenerated > ago(24h)
| summarize Count=count() by EventName_s
| order by Count desc | take 10

// 오류 발생 이벤트
CloudTrailLogs_CL
| where isnotempty(ErrorCode_s)
| project TimeGenerated, EventName_s, ErrorCode_s, SourceIPAddress_s
| order by TimeGenerated desc
```

### Azure Blob RBAC

| 사용자 | 역할 |
|--------|------|
| jh.lee@siseoninfra.onmicrosoft.com | 소유자 (구독 상속) |
| hs.lee@siseoninfra.onmicrosoft.com | Storage Blob 데이터 소유자 + 읽기 권한자 및 데이터 액세스 |
| jw.kim@siseoninfra.onmicrosoft.com | Storage Blob 데이터 소유자 + 읽기 권한자 및 데이터 액세스 |
| zo.kim@siseoninfra.onmicrosoft.com | Storage Blob 데이터 소유자 + 읽기 권한자 및 데이터 액세스 |

---

## 💸 비용 모니터링 설계 (AWS Budgets)

### 설계 목적

포트폴리오 프로젝트 특성상 필요할 때만 인프라를 배포하고 destroy하는 패턴을 사용합니다.
실수로 인프라를 내리지 않거나 예상보다 많은 리소스가 배포된 경우를 감지하기 위해
비용 모니터링 알람을 구성했습니다.

### 비용 예측 근거

하루 8시간 × 22일 = 176시간 기준:

| 리소스 | 시간당 비용 | 월 예상 비용 |
|--------|-----------|------------|
| EKS 클러스터 | $0.10 | $17.6 |
| EC2 t3.medium x2 | $0.0416 | $14.6 |
| RDS t4g.micro | $0.016 | $2.8 |
| NAT Gateway | $0.059 | $10.4 |
| ALB | $0.008 | $1.4 |
| NLB (Grafana) | $0.008 | $1.4 |
| **합계** | | **~$48** |

### 알람 임계값 설정

| 알람 | 임계값 | 기준 | 의미 |
|------|--------|------|------|
| 일별 경보 | $5 초과 | DAILY | 하루 예상 비용 ($48/22일 ≈ $2.2) 2배 초과 시 |
| 월별 경보 | $60 초과 | MONTHLY | 월 예상 비용 초과 시 즉시 알림 |

### AWS Budgets 선택 이유

초기에는 `CloudWatch Billing Alarm → SNS(us-east-1) → Lambda(ap-northeast-2)` 구성을 시도했으나
**크로스 리전 Lambda Permission 설정 문제**로 실패했습니다.
AWS Budgets는 글로벌 서비스라 리전 문제가 없고, SNS와 Lambda를 동일 리전(ap-northeast-2)에서 구성할 수 있어 채택했습니다.

```hcl
# AWS Budgets - 일별 $5 초과
resource "aws_budgets_budget" "daily" {
  name         = "${var.project_name}-budget-daily"
  budget_type  = "COST"
  limit_amount = "5"
  limit_unit   = "USD"
  time_unit    = "DAILY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.billing.arn]
  }
}
```

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
AWS_SERVICE_IPS = (
    "amazonaws.com",
    "elasticloadbalancing.amazonaws.com",
    "eks.amazonaws.com",
    "autoscaling.amazonaws.com",
    "rds.amazonaws.com",
    "eks-nodegroup.amazonaws.com",
)

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

## 🗄️ tfstate 보안 관리 (S3 Remote Backend)

### 보안 위협

로컬에 tfstate를 저장하면 아래 보안 위협이 발생합니다.

| 위협 | 설명 |
|------|------|
| 민감정보 노출 | tfstate에는 DB 비밀번호, API 키 등 평문 저장 |
| GitHub 실수 커밋 | .gitignore 누락 시 민감정보 공개 레포에 노출 |
| PC 분실/도난 | 로컬 tfstate 유출 시 인프라 전체 정보 노출 |
| 상태 충돌 | 멀티 PC 환경에서 tfstate 불일치로 인프라 꼬임 |

### 해결: S3 Remote Backend + 버저닝

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

### 보안 설정

| 항목 | 설정 | 이유 |
|------|------|------|
| S3 버저닝 | 활성화 | tfstate 변경 이력 관리 및 롤백 |
| 퍼블릭 액세스 | 차단 | tfstate 외부 노출 방지 |
| IAM Identity Center | SSO 인증 | 장기 액세스 키 미사용 |
| .gitignore | tfstate, tfvars 제외 | 민감정보 GitHub 노출 차단 |

### 파트별 tfstate 분리

| 파트 | key | 담당 |
|------|-----|------|
| siseon-security | `security/terraform.tfstate` | 이준형 |
| siseon-infra | `infra/terraform.tfstate` | 김진우 |
| siseon-infra-monitoring | `monitoring/terraform.tfstate` | 이준형 |

---

### 파트별 key 구성

| 파트 | key |
|------|-----|
| siseon-security | `security/terraform.tfstate` |
| siseon-infra | `infra/terraform.tfstate` |
| siseon-infra-monitoring | `monitoring/terraform.tfstate` |

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
| `aws_lambda_function` | 로그인/삭제/비용/S3동기화 함수 4개 |
| `aws_lambda_permission` | CloudWatch Logs / SNS / EventBridge 트리거 권한 |
| `aws_cloudwatch_log_subscription_filter` | 이벤트 패턴 필터 + Lambda 연결 |
| `aws_cloudwatch_event_rule` | EventBridge 스케줄 (매일 KST 02:00) |
| `aws_iam_role_policy` | S3 읽기 권한 (CloudTrail 버킷) |

### cloudwatch 모듈

| 리소스 | 설명 |
|--------|------|
| `aws_cloudwatch_log_metric_filter` | 지표 필터 (대시보드/모니터링용) |
| `aws_cloudwatch_metric_alarm` | 임계값 기반 경보 (SNS 미연결) |

### billing 모듈

| 리소스 | 설명 |
|--------|------|
| `aws_budgets_budget` | 일별/월별 비용 예산 설정 |
| `aws_sns_topic` | 비용 경보 SNS 토픽 |
| `aws_sns_topic_subscription` | SNS → Lambda 구독 |
| `aws_lambda_permission` | SNS 트리거 Lambda 권한 |

### azure_monitor 모듈 (신규)

| 리소스 | 설명 |
|--------|------|
| `azurerm_log_analytics_workspace` | CloudTrail 로그 수집 Workspace |
| `azurerm_storage_account` | Function App 내부 스토리지 |
| `azurerm_service_plan` | Function App 실행 플랜 (Consumption Y1) |
| `azurerm_linux_function_app` | Blob 트리거 → Log Analytics 전송 |
| `azurerm_application_insights_workbook` | 보안 감사 대시보드 |

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

### Lambda S3 읽기 권한 (s3_to_azure 전용)

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:ListBucket"],
  "Resource": [
    "arn:aws:s3:::aws-cloudtrail-logs-448768137813-05d6a32b",
    "arn:aws:s3:::aws-cloudtrail-logs-448768137813-05d6a32b/*"
  ]
}
```

### Azure RBAC (siseonstorage)

| 역할 | 용도 |
|------|------|
| Storage Blob 데이터 소유자 | Blob 데이터 읽기/쓰기/삭제/권한 설정 |
| 읽기 권한자 및 데이터 액세스 | Azure Portal에서 스토리지 계정 목록 표시 |

> **참고**: `Storage Blob 데이터 소유자`만으로는 Azure Portal에서 스토리지 계정이 목록에 표시되지 않습니다.
> Portal에서 리소스를 보려면 Azure Resource Manager 레벨의 `읽기 권한자 및 데이터 액세스` 역할이 별도로 필요합니다.

---

## 📊 CloudWatch Metric Filter

Subscription Filter와 별도로 Metric Filter를 유지합니다.
알림용이 아닌 **대시보드 시각화 및 장기 지표 모니터링** 목적입니다.

| 필터 | 패턴 | 지표 |
|------|------|------|
| `siseon-filter-console-login` | `{ $.eventName = "ConsoleLogin" }` | `SiseonSecurity/ConsoleLoginCount` |
| `siseon-filter-delete-action` | `{ ($.eventName = "Delete*") \|\| ... }` | `SiseonSecurity/DeleteActionCount` |