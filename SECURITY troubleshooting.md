# 🔧 트러블슈팅 기록

> siseon-security 구성 과정에서 발생한 문제와 해결 방법을 기록합니다.

---

## 1. Microsoft Teams 웹훅 중단 → Power Automate 전환

### 증상
기존에 사용하던 Teams 인커밍 웹훅 URL이 동작하지 않았습니다.

### 원인
Microsoft가 **Office 365 커넥터(인커밍 웹훅) 서비스를 종료**했습니다.

### 해결
Microsoft Power Automate의 **HTTP 요청 트리거** 기반 워크플로우로 전환했습니다.

```
기존: Teams 인커밍 웹훅 (Office 365 커넥터)
변경: Power Automate HTTP 요청 → Teams 메시지 게시
```

### 교훈
외부 서비스 의존성은 서비스 종료, 정책 변경 등의 리스크가 있습니다.
대안 수단을 항상 확보해두고, 공식 문서를 주기적으로 확인해야 합니다.

---

## 2. CloudWatch Alarm 방식의 알림 누락

### 증상
팀원이 콘솔에 로그인했지만 Teams 알림이 오지 않았습니다.

### 원인
CloudWatch Alarm은 **상태가 변경될 때만 SNS를 발행**합니다.

```
1. jh.lee 로그인 → OK → ALARM (알림 발송 ✅)
2. zo.kim 로그인 → 이미 ALARM 상태 → 알림 없음 ❌
```

### 해결
`CloudWatch Logs Subscription Filter → Lambda` 방식으로 전환했습니다.

### 교훈
이벤트 발생 자체를 감지하려면 Subscription Filter 방식이 적합합니다.

---

## 3. Teams 알림 메시지에 상세 정보 없음

### 증상
```
✅ AWS 콘솔 로그인 감지
사용자: 확인 필요
시각: 확인 필요
IP: 확인 필요
```

### 원인
Power Automate 흐름이 Lambda에서 전송한 JSON을 무시하고
하드코딩된 템플릿 메시지를 고정으로 발송했습니다.

### 해결
Power Automate 메시지를 동적 값으로 변경:
```
@{triggerBody()?['message']}
```

Lambda에서 CloudTrail 로그 직접 파싱:
```python
username  = user_identity.get("userName") or arn.split("/")[-1]
source_ip = record["sourceIPAddress"]
region    = record["awsRegion"]
```

### 교훈
알림 파이프라인 설계 시 중간 단계의 데이터 처리 방식을 반드시 검증해야 합니다.

---

## 4. AWS 서비스 이벤트 알림 노이즈

### 증상
Terraform destroy 실행 시 AWS 서비스가 자동으로 수행하는 삭제 작업까지 Teams에 발송되었습니다.

```
🚨 리소스 삭제 작업 감지
👤 사용자: AutoScaling    ← AWS 서비스
🛠️ 작업: TerminateInstances
```

### 원인
Lambda 코드가 사람/서비스를 구분하지 않았습니다.

### 해결
`sourceIPAddress` 기반 AWS 서비스 필터링 추가:

```python
AWS_SERVICE_IPS = (
    "amazonaws.com",
    "elasticloadbalancing.amazonaws.com",
    "eks.amazonaws.com",
    "autoscaling.amazonaws.com",
    "rds.amazonaws.com",
)

if any(source_ip.endswith(svc) for svc in AWS_SERVICE_IPS):
    continue
```

### 교훈
보안 알림 설계 시 노이즈 필터링은 필수적입니다.

---

## 5. Subscription Filter 패턴에 백틱 문자 오류

### 증상
```
Invalid character(s) in term '`'
```

### 원인
복사/붙여넣기 과정에서 패턴 앞에 백틱(`) 문자가 포함되었습니다.

### 해결
메모장에 먼저 붙여넣기 후 다시 복사하여 특수문자를 제거했습니다.

### 교훈
Terraform 코드로 관리하면 이러한 실수를 방지할 수 있습니다.

---

## 6. Teams 메시지 줄바꿈 미적용

### 증상
Lambda에서 `\n`으로 줄바꿈을 처리했지만 Teams에서 한 줄로 표시됐습니다.

### 원인
Microsoft Teams는 일반 텍스트의 `\n`을 줄바꿈으로 처리하지 않습니다.

### 해결
Lambda 코드에서 `\n` → `<br>` 태그로 변경했습니다.

---

## 7. 멀티 PC 환경에서의 tfstate 관리 문제 → S3 Remote Backend 도입

### 증상
학원 PC에서 `terraform apply`로 인프라를 배포한 후,
노트북으로 작업하려 했더니 tfstate가 없어 작업이 불가능했습니다.

```
# 노트북에서 terraform plan 실행 시
→ tfstate가 없어 실제 AWS 리소스와 상태 불일치
→ Lambda 코드 수정, Billing 알람 추가 등 작업 불가
```

### 원인
tfstate가 학원 PC 로컬에만 존재했고 `.gitignore`로 GitHub에도 올라가지 않았습니다.

### 해결
S3 Remote Backend를 도입하여 tfstate를 중앙에서 관리합니다.

```bash
aws s3 mb s3://siseon-terraform-state --region ap-northeast-2 --profile siseon
aws s3api put-bucket-versioning \
  --bucket siseon-terraform-state \
  --versioning-configuration Status=Enabled \
  --profile siseon
```

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

```bash
terraform init -migrate-state  # 로컬 → S3 자동 이관
```

### 도입 후 효과
- 학원 PC, 노트북 어디서든 즉시 작업 가능
- tfstate 민감 정보 GitHub 노출 차단
- S3 버저닝으로 tfstate 변경 이력 관리

### 교훈
팀 프로젝트나 멀티 환경에서는 Remote Backend가 필수입니다.

---

## 8. Billing 알람 크로스 리전 문제 → AWS Budgets로 전환

### 증상
CloudWatch Billing 메트릭은 `us-east-1` 에서만 조회 가능합니다.
초기 설계는 `CloudWatch Alarm(us-east-1) → SNS(us-east-1) → Lambda(ap-northeast-2)` 구조였으나
Lambda Permission 설정이 계속 실패했습니다.

```
module.billing.aws_lambda_permission.billing_sns: Still creating... [02m40s elapsed]
→ 크로스 리전 Lambda Permission 타임아웃
```

### 원인
SNS(`us-east-1`)가 Lambda(`ap-northeast-2`)를 호출하려면
Lambda Permission을 Lambda가 있는 리전(ap-northeast-2)에서 설정해야 합니다.
하지만 billing 모듈 전체가 `us-east-1` provider를 사용하고 있어
같은 모듈 내에서 리전을 나눠 설정하기가 복잡했습니다.

### 해결
**AWS Budgets** 서비스로 전환했습니다.

AWS Budgets는 **글로벌 서비스**라 리전 구분이 없고,
SNS와 Lambda를 모두 `ap-northeast-2`에서 구성할 수 있어
크로스 리전 문제가 발생하지 않습니다.

```hcl
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

### 추가 장점
- AWS Budgets는 월 2개까지 **무료**
- CloudWatch Billing Alarm보다 더 직관적인 비용 관리 서비스
- 일별/월별 기준 모두 지원

### 교훈
멀티 리전 아키텍처에서는 서비스의 리전 특성을 사전에 파악해야 합니다.
크로스 리전 구성이 복잡해질 경우 글로벌 서비스 대안을 검토하는 것이 효율적입니다.

---

## 9. CloudTrail → CloudWatch 로그 그룹 미생성

### 증상
CloudWatch에서 `/aws/cloudtrail` 로그 그룹이 생성되지 않았습니다.

### 원인
CloudTrail 생성 후 CloudWatch Logs 연동을 별도로 설정해야 합니다.

### 해결
```hcl
resource "aws_cloudtrail" "main" {
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cw.arn
}
```

---

## 📋 트러블슈팅 요약

| # | 문제 | 원인 | 해결 |
|---|------|------|------|
| 1 | Teams 웹훅 중단 | Microsoft 커넥터 서비스 종료 | Power Automate HTTP 트리거로 전환 |
| 2 | 알림 누락 | Alarm 상태 변화 없음 | Subscription Filter → Lambda 방식으로 전환 |
| 3 | 알림 상세 정보 없음 | Power Automate 고정 템플릿 | 동적 메시지 처리로 변경 |
| 4 | AWS 서비스 알림 노이즈 | 서비스 이벤트 필터링 미적용 | sourceIPAddress 기반 필터링 추가 |
| 5 | 백틱 문자 오류 | 복붙 시 특수문자 유입 | 메모장 경유 후 재복사 |
| 6 | 줄바꿈 미적용 | Teams `\n` 미지원 | `<br>` HTML 태그로 변경 |
| 7 | 멀티 PC tfstate 관리 | 로컬 tfstate 한계 | S3 Remote Backend 도입 |
| 8 | Billing 크로스 리전 문제 | us-east-1 ↔ ap-northeast-2 충돌 | AWS Budgets 글로벌 서비스로 전환 |
| 9 | 로그 그룹 미생성 | CloudTrail-CW 연동 미설정 | CloudWatch Logs 연동 활성화 |