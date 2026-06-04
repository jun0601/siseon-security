# 🔐 Siseon Security Monitoring

> **StockOps ERP** 하이브리드 멀티클라우드 프로젝트의 보안/감사 모니터링 인프라  
> AWS CloudTrail 기반 실시간 보안 이벤트 감지 및 Microsoft Teams 알림 파이프라인을 Terraform으로 구현

---

## 📌 프로젝트 개요

| 항목 | 내용 |
|------|------|
| 프로젝트명 | StockOps ERP - 보안/감사 모니터링 파트 |
| 팀명 | 시선 (SISEON) |
| 담당 | 팀원C - 로그/모니터링 |
| 클라우드 | AWS (ap-northeast-2) |
| IaC | Terraform |

---

## 🏗️ 아키텍처

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

---

## 📁 디렉토리 구조

```
siseon-security/
├── main.tf                        # 루트 모듈
├── variables.tf                   # 변수 정의
├── outputs.tf                     # 출력값
├── providers.tf                   # AWS Provider 설정
├── terraform.tfvars               # 민감 변수 (git 제외)
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
    │       └── delete_alert.py    # 삭제 감지 Lambda
    └── cloudwatch/                # Metric Filter + Alarm
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

---

## 🛠️ 기술 스택

| 분류 | 기술 |
|------|------|
| IaC | Terraform >= 1.0 |
| 클라우드 | AWS (CloudTrail, CloudWatch, Lambda, S3, IAM) |
| 런타임 | Python 3.12 |
| 알림 | Microsoft Teams + Power Automate |

---

## 🚀 배포 방법

### 사전 요구사항
- Terraform >= 1.0
- AWS CLI + SSO 설정 (`aws configure sso`)
- Microsoft Teams + Power Automate 웹훅 URL

### 배포

```bash
# 1. 초기화
terraform init

# 2. 변수 파일 생성 후 웹훅 URL 입력
cp terraform.tfvars.example terraform.tfvars

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

## 🔒 감지 이벤트 목록

### 삭제 작업 (`aws-alerts`)

| 패턴 | 예시 이벤트 |
|------|------------|
| `Delete*` | DeleteBucket, DeleteUser, DeleteRole, DeleteAlarms 등 |
| `Remove*` | RemoveUserFromGroup, RemoveRoleFromInstanceProfile 등 |
| `Terminate*` | TerminateInstances |

### 로그인 (`aws-logins`)

| 이벤트 | 설명 |
|--------|------|
| `ConsoleLogin` | AWS 콘솔 로그인 전체 감지 |

---

## 📦 S3 로그 장기 보관 정책

| 기간 | 스토리지 클래스 |
|------|----------------|
| 0 ~ 30일 | S3 Standard |
| 30 ~ 90일 | Standard-IA |
| 90 ~ 365일 | Glacier |
| 365일 이후 | 삭제 |

---

## ⚠️ 주의사항

- `terraform.tfvars` 는 웹훅 URL 포함으로 **절대 커밋 금지** (`.gitignore` 처리됨)
- Power Automate 웹훅 URL 변경 시 `terraform.tfvars` 수정 후 `terraform apply` 재실행
- AWS CLI SSO 토큰 만료 시 `aws sso login --profile siseon` 으로 재로그인 필요