# 🔧 트러블슈팅 기록

> siseon-security 구성 과정에서 발생한 문제와 해결 방법을 기록합니다.

---

## 1. Microsoft Teams 웹훅 중단 → Power Automate 전환

### 증상
기존에 사용하던 Teams 인커밍 웹훅 URL이 동작하지 않았습니다.

### 원인
Microsoft가 **Office 365 커넥터(인커밍 웹훅) 서비스를 종료**했습니다.
기존 방식의 웹훅 URL은 더 이상 유효하지 않습니다.

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
초기 구현은 `CloudWatch Alarm → SNS → Lambda` 방식이었습니다.
CloudWatch Alarm은 **상태가 변경될 때만 SNS를 발행**합니다.
Alarm이 이미 ALARM 상태일 때 추가 로그인이 발생해도 상태 변화가 없어 알림이 발송되지 않았습니다.

```
시나리오:
1. jh.lee 로그인 → OK → ALARM (알림 발송 ✅)
2. zo.kim 로그인 → 이미 ALARM 상태 → 알림 없음 ❌
```

### 해결
`CloudWatch Logs Subscription Filter → Lambda` 방식으로 전환했습니다.

### 교훈
임계값 기반 Alarm은 "상태 변화 감지"에 적합하고,
이벤트 발생 자체를 감지하려면 Subscription Filter 방식이 적합합니다.

---

## 3. Teams 알림 메시지에 상세 정보 없음

### 증상
Teams 알림에 사용자, IP, 시간 등 상세 정보가 표시되지 않았습니다.

```
# 기존 알림 (상세 정보 없음)
✅ AWS 콘솔 로그인 감지
사용자: 확인 필요
시각: 확인 필요
IP: 확인 필요
```

### 원인
Power Automate 흐름이 Lambda에서 전송한 JSON을 무시하고
**하드코딩된 템플릿 메시지**를 고정으로 발송했습니다.

### 해결
Power Automate 메시지 내용을 동적 값으로 변경:
```
@{triggerBody()?['message']}
```

Lambda에서 CloudTrail 로그를 직접 파싱하여 상세 정보 전송:
```python
username  = user_identity.get("userName") or arn.split("/")[-1]
source_ip = record["sourceIPAddress"]
region    = record["awsRegion"]
```

### 교훈
알림 파이프라인 설계 시 메시지 포맷을 사전에 정의하고
중간 단계의 데이터 처리 방식을 반드시 검증해야 합니다.

---

## 4. AWS 서비스 이벤트 알림 노이즈

### 증상
Terraform destroy 실행 시 `AutoScaling`, `EKS`, `ElasticLoadBalancing` 등
AWS 서비스가 자동으로 수행하는 삭제 작업까지 Teams에 알림이 발송되었습니다.

```
🚨 리소스 삭제 작업 감지
👤 사용자: AutoScaling        ← AWS 서비스
🛠️ 작업: TerminateInstances
```

### 원인
Lambda 코드가 `sourceIPAddress` 를 기준으로 사람/서비스를 구분하지 않아
AWS 내부 서비스가 수행한 작업까지 모두 알림으로 발송되었습니다.

### 해결
`sourceIPAddress` 가 AWS 서비스 도메인인 경우 스킵하도록 필터링 추가:

```python
AWS_SERVICE_IPS = (
    "amazonaws.com",
    "elasticloadbalancing.amazonaws.com",
    "eks.amazonaws.com",
    "autoscaling.amazonaws.com",
    "rds.amazonaws.com",
)

if any(source_ip.endswith(svc) for svc in AWS_SERVICE_IPS):
    continue  # AWS 서비스 이벤트 스킵
```

### 교훈
CloudTrail은 사람뿐만 아니라 AWS 서비스 자체의 작업도 기록합니다.
보안 알림 설계 시 노이즈 필터링은 필수적입니다.

---

## 5. Subscription Filter 패턴에 백틱 문자 오류

### 증상
```
Invalid character(s) in term '`'
```

### 원인
복사/붙여넣기 과정에서 패턴 앞에 **백틱(`) 문자**가 포함되었습니다.

### 해결
메모장에 먼저 붙여넣기 후 다시 복사하여 특수문자를 제거했습니다.

### 교훈
Terraform 코드로 관리하면 이러한 실수를 방지할 수 있습니다.

---

## 6. Teams 메시지 줄바꿈 미적용

### 증상
Lambda에서 `\n`으로 줄바꿈을 처리했지만 Teams에서 한 줄로 표시됐습니다.

### 원인
Microsoft Teams 메시지는 일반 텍스트의 `\n`을 줄바꿈으로 처리하지 않습니다.

### 해결
Lambda 코드에서 `\n` → `<br>` 태그로 변경했습니다.

```python
message = (
    f"🔐 콘솔 로그인 감지<br>"
    f"👤 사용자: {username}<br>"
)
```

---

## 7. 멀티 PC 환경에서의 tfstate 관리 문제 → S3 Remote Backend 도입

### 증상
학원 PC에서 `terraform apply`로 인프라를 배포한 후,
집에서 노트북으로 작업하려 했더니 tfstate 파일이 없어 작업이 불가능했습니다.

```
# 노트북에서 terraform plan 실행 시
Error: No valid credential sources found
→ 로그인 후 재시도해도 tfstate가 없어 실제 AWS 리소스와 상태 불일치
```

또한 추가 기능(Lambda 코드 수정, Billing 알람 등)을 개발하면서
**코드는 GitHub에 있지만 tfstate는 학원 PC에만 존재**하는 상황이 지속되었습니다.

### 원인
Terraform tfstate가 로컬에만 존재하여 다른 환경에서 작업이 불가능했습니다.
`.gitignore`에 tfstate를 추가했기 때문에 GitHub에도 올라가지 않는 구조였습니다.

### 해결
S3 Remote Backend를 도입하여 tfstate를 중앙에서 관리합니다.

```bash
# S3 버킷 생성
aws s3 mb s3://siseon-terraform-state --region ap-northeast-2 --profile siseon

# 버저닝 활성화
aws s3api put-bucket-versioning \
  --bucket siseon-terraform-state \
  --versioning-configuration Status=Enabled \
  --profile siseon
```

```hcl
# providers.tf
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
# 로컬 tfstate → S3 자동 이관
terraform init -migrate-state
```

### 파트별 S3 key 구성

| 파트 | key |
|------|-----|
| siseon-security | `security/terraform.tfstate` |
| siseon-infra | `infra/terraform.tfstate` |
| siseon-infra-monitoring | `monitoring/terraform.tfstate` |

### 도입 후 효과

- 학원 PC, 노트북 어디서든 `terraform init` 후 즉시 작업 가능
- tfstate에 포함된 민감 정보가 GitHub에 노출되는 것을 원천 차단
- S3 버저닝으로 tfstate 변경 이력 관리 및 롤백 가능
- 팀원 간 동일한 상태 공유로 충돌 방지

### 교훈
IaC 작업 시 tfstate 관리 전략은 초기에 반드시 설계해야 합니다.
로컬 tfstate는 개인 프로젝트에서만 적합하고,
팀 프로젝트나 멀티 환경에서는 Remote Backend가 필수입니다.

---

## 8. CloudTrail → CloudWatch 로그 그룹 미생성

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
| 8 | 로그 그룹 미생성 | CloudTrail-CW 연동 미설정 | CloudWatch Logs 연동 활성화 |