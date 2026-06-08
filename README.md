# 🔐 Siseon Security Monitoring

> **StockOps ERP** 하이브리드 멀티클라우드 프로젝트의 보안/감사 모니터링 인프라  
> AWS CloudTrail 기반 실시간 보안 이벤트 감지 및 Microsoft Teams 알림 파이프라인을 Terraform으로 구현

---

## 📌 프로젝트 개요

| 항목 | 내용 |
|------|------|
| 프로젝트명 | StockOps ERP - 보안/감사 모니터링 파트 |
| 팀명 | 시선 (SISEON) |
| 담당 | 이준형 - 로그/모니터링 & 보안 파트 |
| 클라우드 | AWS (ap-northeast-2) |
| IaC | Terraform |

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
├── providers.tf                   # AWS Provider 설정 + S3 Backend
├── terraform.tfvars               # 민감 변수 (git 제외)
├── .gitignore
├── README.md                      # 프로젝트 개요
├── SECURITY.md                    # 보안 설계 문서
├── TROUBLESHOOTING.md             # 트러블슈팅 기록
└── modules/
    ├── cloudtrail/                # CloudTrail + S3 Lifecycle + CW 연동
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── lambda/                    # Lambda 함수 + Subscription Filter
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── functions/
    │       ├── login_alert.py     # 로그인 감지 Lambda
    │       ├── delete_alert.py    # 삭제 감지 Lambda
    │       └── billing_alert.py   # 비용 경보 Lambda
    ├── cloudwatch/                # Metric Filter + Alarm
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── billing/                   # AWS Budgets + SNS
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

---

## 🛠️ 기술 스택

| 분류 | 기술 |
|------|------|
| IaC | Terraform >= 1.0 |
| 클라우드 | AWS (CloudTrail, CloudWatch, Lambda, S3, IAM, Budgets) |
| 런타임 | Python 3.12 |
| 알림 | Microsoft Teams + Power Automate |
| 인증 | AWS IAM Identity Center (SSO) |
| tfstate 관리 | S3 Remote Backend (`siseon-terraform-state`) |

---

## 🚀 배포 방법

### 사전 요구사항
- Terraform >= 1.0
- AWS CLI + SSO 설정 (`aws configure sso --profile siseon`)
- Microsoft Teams + Power Automate 웹훅 URL 3개
  - `aws-logins` 채널용
  - `aws-alerts` 채널용
  - `aws-billing` 채널용

### 배포

```bash
# 1. SSO 로그인
aws sso login --profile siseon

# 2. 초기화
terraform init

# 3. 플랜 확인
terraform plan

# 4. 배포
terraform apply
```

### 삭제

```bash
terraform destroy
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

- `terraform.tfvars` 는 웹훅 URL 포함으로 **절대 커밋 금지** (`.gitignore` 처리됨)
- Power Automate 웹훅 URL 변경 시 `terraform.tfvars` 수정 후 `terraform apply` 재실행
- AWS CLI SSO 토큰 만료 시 `aws sso login --profile siseon` 으로 재로그인 필요
- S3 backend 최초 설정 시 `terraform init -migrate-state` 로 로컬 tfstate 이관 필요
- AWS Budgets는 월 2개까지 무료