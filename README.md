# 🔐 Siseon Security Monitoring

> **StockOps ERP** 하이브리드 멀티클라우드 프로젝트의 보안/감사 모니터링 인프라  
> AWS CloudTrail 기반 실시간 보안 이벤트 감지 및 Microsoft Teams 알림 파이프라인을 Terraform으로 구현  
> AWS 장애 시나리오 대비 Azure Monitor 기반 CloudTrail 보안 감사 로그 페일오버 모니터링 구성

---

## 📌 프로젝트 개요

| 항목 | 내용 |
|------|------|
| 프로젝트명 | StockOps ERP - 보안/감사 모니터링 파트 |
| 팀명 | 시선 (SISEON) |
| 담당 | 이준형 - 로그/모니터링 & 보안 파트 |
| 클라우드 | AWS (ap-northeast-2) + Azure (Korea Central) |
| IaC | Terraform (AWS + Azure 멀티클라우드 통합 관리) |

---

## 🏗️ 파이프라인 아키텍처

```
AWS 콘솔 이벤트 발생 (로그인 / 리소스 삭제)
            ↓
        CloudTrail
   (관리 이벤트 수집 + S3 장기 보관)
            ↓
  CloudWatch Logs (/aws/cloudtrail)
            ↓
   Subscription Filter (패턴 매칭)
            ↓
       Lambda 함수
  (CloudTrail 로그 파싱 + 상세 정보 추출)
            ↓
   Power Automate 웹훅 POST
            ↓
  Microsoft Teams 채널 실시간 알림

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AWS Budgets (비용 모니터링)
  일별 $5 / 월별 $60 임계값 초과
            ↓
        SNS 토픽
            ↓
       Lambda 함수
  (비용 경보 메시지 포맷)
            ↓
   Power Automate 웹훅 POST
            ↓
  Microsoft Teams 💸aws-billing 채널

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

S3 (CloudTrail 로그)
            ↓
  Lambda (매일 KST 02:00, EventBridge)
  (날짜 범위 파라미터 지원 / 기본값: 오늘)
            ↓
  Azure Blob Storage
  (siseonstorage/cloudtrail-backup)
            ↓
  Azure Function (Blob 트리거 자동 실행)
  (CloudTrail JSON 파싱 + Log Analytics 전송)
            ↓
  Azure Log Analytics Workspace
  (siseon-security-logs)
            ↓
  Azure Monitor Workbook
  (StockOps CloudTrail 보안 감사 대시보드)
  ※ AWS 장애 시 Azure에서 보안 감사 로그 조회
```

---

## 📡 알림 채널

### 🔐 콘솔 로그인 감지 → `aws-logins` 채널
```
🔐 콘솔 로그인 감지
👤 사용자: jh.lee
🌐 IP: 121.160.42.57
📍 리전: ap-northeast-2
🔎 결과: ✅ Success
⏰ 시간: 2026-06-04 17:09:38 KST
```

### 🚨 리소스 삭제 감지 → `aws-alerts` 채널
```
🚨 리소스 삭제 작업 감지
👤 사용자: jh.lee
🛠️ 작업: DeleteAlarms
📦 리소스: siseon-alarm-test
🌐 IP: 121.160.42.57
📍 리전: ap-northeast-2
⏰ 시간: 2026-06-04 17:23:11 KST
```

### 💸 비용 경보 → `aws-billing` 채널
```
⚠️ AWS 비용 경보
📊 유형: 일별 예산 초과
💰 임계값: $5
📋 사유: 일별 비용 임계값 초과
⏰ 시간: 2026-06-08 10:00:00 KST
```

---

## 🔒 감지 이벤트 목록

### 삭제 작업 (`aws-alerts`)

| 패턴 | 예시 이벤트 |
|------|------------|
| `Delete*` | DeleteBucket, DeleteUser, DeleteRole, DeleteAlarms, DeleteTrail 등 |
| `Remove*` | RemoveUserFromGroup, RemoveRoleFromInstanceProfile 등 |
| `Terminate*` | TerminateInstances |

### 로그인 (`aws-logins`)

| 이벤트 | 설명 |
|--------|------|
| `ConsoleLogin` | AWS 콘솔 로그인 전체 감지 (성공/실패 모두) |

### 비용 경보 (`aws-billing`)

| 알람 | 임계값 | 기준 | 근거 |
|------|--------|------|------|
| 일별 경보 | $5 초과 | DAILY | 하루 8시간 기준 예상 비용 |
| 월별 경보 | $60 초과 | MONTHLY | 월 176시간 기준 예상 비용 |

---

## 🔄 S3 → Azure Blob 동기화

### 목적
AWS 장애 시에도 CloudTrail 보안 감사 로그를 Azure에서 확인할 수 있도록
매일 새벽 S3 로그를 Azure Blob Storage에 자동 동기화합니다.

### 동기화 구성

| 항목 | 값 |
|------|-----|
| 소스 | S3 `aws-cloudtrail-logs-448768137813-05d6a32b` |
| 소스 경로 | `AWSLogs/448768137813/CloudTrail/ap-northeast-2/` |
| 대상 | Azure Blob `siseonstorage/cloudtrail-backup` |
| 실행 주기 | 매일 KST 02:00 (EventBridge cron) |
| Lambda | `siseon-lambda-s3-to-azure` |

### 날짜 범위 수동 동기화 (백필)
```json
{
  "start_date": "2026-06-02",
  "end_date": "2026-06-07"
}
```
Lambda 테스트 이벤트로 위 JSON을 전달하면 지정 기간의 로그를 일괄 동기화합니다.
파라미터 없이 실행 시 오늘 날짜 기준으로 동작합니다 (크론탭 기본 동작).

### Azure Blob Storage

| 항목 | 값 |
|------|-----|
| 스토리지 계정 | siseonstorage |
| 리소스 그룹 | siseon-rg |
| 리전 | Korea Central |
| 컨테이너 | cloudtrail-backup (보안 감사 로그) |
| 컨테이너 | db-backup (RDS 스냅샷, 김시온 파트) |

### Azure Blob RBAC

| 사용자 | 역할 |
|--------|------|
| jh.lee@siseoninfra.onmicrosoft.com | 소유자 (구독 상속) |
| hs.lee@siseoninfra.onmicrosoft.com | Storage Blob 데이터 소유자 + 읽기 권한자 및 데이터 액세스 |
| jw.kim@siseoninfra.onmicrosoft.com | Storage Blob 데이터 소유자 + 읽기 권한자 및 데이터 액세스 |
| zo.kim@siseoninfra.onmicrosoft.com | Storage Blob 데이터 소유자 + 읽기 권한자 및 데이터 액세스 |

---

## 🔵 Azure Monitor 페일오버 모니터링

### 목적
AWS 장애 시나리오에서 Azure Blob에 백업된 CloudTrail 로그를 Azure Monitor Workbook으로 시각화합니다.

### 아키텍처

```
Azure Blob (cloudtrail-backup)
        ↓ Blob 트리거 (자동)
Azure Function (siseon-blob-to-laws)
  • CloudTrail JSON 파싱
  • gzip 압축 해제
  • Log Analytics REST API 전송
        ↓
Log Analytics Workspace (siseon-security-logs)
  • 테이블: CloudTrailLogs_CL
  • 보존: 30일
        ↓
Azure Monitor Workbook
  • CloudTrail 이벤트 현황 (Top 10) - 바차트
  • 오류 발생 이벤트 - 테이블
  • 소스 IP별 접근 현황 - 파이차트
  • 시간대별 이벤트 추이 - 타임차트
```

### Azure 리소스 구성

| 리소스 | 이름 | 설명 |
|--------|------|------|
| Log Analytics Workspace | siseon-security-logs | CloudTrail 로그 수집/쿼리 |
| Function App | siseon-blob-to-laws | Blob 트리거 → Log Analytics 전송 |
| App Service Plan | siseon-func-plan | Consumption(Y1) 무료 티어 |
| Storage Account | siseonfuncstore | Function App 내부 스토리지 |
| Azure Workbook | StockOps CloudTrail 보안 감사 대시보드 | KQL 기반 시각화 |

### KQL 쿼리 예시
```kusto
// 이벤트 현황
CloudTrailLogs_CL
| where TimeGenerated > ago(24h)
| summarize Count=count() by EventName_s
| order by Count desc
| take 10

// 오류 발생 이벤트
CloudTrailLogs_CL
| where isnotempty(ErrorCode_s)
| project TimeGenerated, EventName_s, ErrorCode_s, SourceIPAddress_s
| order by TimeGenerated desc
```

---

## 📦 S3 로그 장기 보관 정책

| 기간 | 스토리지 클래스 | 비용 |
|------|----------------|------|
| 0 ~ 30일 | S3 Standard | 일반 |
| 30 ~ 90일 | Standard-IA | 저감 |
| 90 ~ 365일 | Glacier | 최저 |
| 365일 이후 | 삭제 | - |

---

## 📁 디렉토리 구조

```
siseon-security/
├── main.tf                        # 루트 모듈
├── variables.tf                   # 변수 정의
├── outputs.tf                     # 출력값
├── providers.tf                   # AWS + Azure Provider + S3 Backend
├── terraform.tfvars               # 민감 변수 (git 제외)
├── .gitignore
├── README.md
├── SECURITY.md
├── TROUBLESHOOTING.md
└── modules/
    ├── cloudtrail/                # CloudTrail + S3 Lifecycle + CW 연동
    ├── lambda/                    # Lambda 함수 + Subscription Filter
    │   └── functions/
    │       ├── login_alert.py
    │       ├── delete_alert.py
    │       ├── billing_alert.py
    │       └── s3_to_azure.py     # 날짜 범위 파라미터 지원
    ├── cloudwatch/                # Metric Filter + Alarm
    ├── billing/                   # AWS Budgets + SNS
    └── azure_monitor/             # Azure Monitor 페일오버 모니터링
        ├── main.tf                # Log Analytics + Function App + Workbook
        ├── variables.tf
        ├── outputs.tf
        └── functions/
            ├── function_app.py    # Blob 트리거 + Log Analytics 전송
            ├── host.json
            ├── requirements.txt
            └── local.settings.json
```

---

## 🛠️ 기술 스택

| 분류 | 기술 |
|------|------|
| IaC | Terraform >= 1.0 (AWS + Azure 멀티클라우드) |
| 클라우드 (주) | AWS (CloudTrail, CloudWatch, Lambda, S3, IAM, Budgets) |
| 클라우드 (부) | Azure (Blob Storage, Function App, Log Analytics, Monitor Workbook) |
| 런타임 | Python 3.12 (Lambda) / Python 3.11 (Azure Function) |
| 알림 | Microsoft Teams + Power Automate |
| 인증 | AWS IAM Identity Center (SSO) |
| tfstate 관리 | S3 Remote Backend (`siseon-terraform-state`) |

---

## 🚀 배포 방법

### 사전 요구사항
- Terraform >= 1.0
- AWS CLI + SSO 설정 (`aws configure sso --profile siseon`)
- Azure CLI (`az login`)
- Azure Functions Core Tools (`func --version`)
- Microsoft Teams + Power Automate 웹훅 URL 3개
- Azure Blob Storage 연결 문자열

### 배포

```bash
# 1. SSO 로그인
aws sso login --profile siseon

# 2. Azure 로그인
az login

# 3. 초기화
terraform init

# 4. 플랜 확인
terraform plan

# 5. 배포
terraform apply -auto-approve

# 6. Azure Function 코드 배포
cd modules/azure_monitor/functions
func azure functionapp publish siseon-blob-to-laws --python
```

### Azure만 삭제

```bash
terraform destroy -target module.azure_monitor -auto-approve
```

### 전체 삭제

```bash
terraform destroy -auto-approve
```

---

## 🔗 연관 레포지토리

| 레포 | 설명 |
|------|------|
| [siseon-security](https://github.com/jun0601/siseon-security) | CloudTrail 보안/감사 모니터링 (현재) |
| [siseon-infra-monitoring](https://github.com/jun0601/siseon-infra-monitoring) | EKS 인프라 모니터링 |
| [siseon-infra](https://github.com/jun0601/siseon-infra) | 팀 메인 인프라 (VPC, EKS, ALB, RDS) |

---

## ⚠️ 주의사항

- `terraform.tfvars` 는 웹훅 URL + Azure 연결 문자열 포함으로 **절대 커밋 금지** (`.gitignore` 처리됨)
- 다른 PC에서 작업 시 `terraform.tfvars` 직접 생성 필요 (민감 변수 4개)
- Azure Function 코드는 Terraform과 별도로 `func publish` 명령으로 배포
- AWS CLI SSO 토큰 만료 시 `aws sso login --profile siseon` 재로그인 필요
- Azure CLI 토큰 만료 시 `az login` 재로그인 필요
- AWS Budgets는 월 2개까지 무료