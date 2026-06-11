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

### 원인
tfstate가 학원 PC 로컬에만 존재했고 `.gitignore`로 GitHub에도 올라가지 않았습니다.

### 해결
S3 Remote Backend를 도입하여 tfstate를 중앙에서 관리합니다.

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

### 교훈
팀 프로젝트나 멀티 환경에서는 Remote Backend가 필수입니다.

---

## 8. Billing 알람 크로스 리전 문제 → AWS Budgets로 전환

### 증상
CloudWatch Billing 메트릭은 `us-east-1`에서만 조회 가능합니다.
크로스 리전 Lambda Permission 설정이 계속 타임아웃으로 실패했습니다.

### 해결
**AWS Budgets** 서비스로 전환했습니다. 글로벌 서비스라 리전 구분이 없고 월 2개까지 무료입니다.

### 교훈
멀티 리전 아키텍처에서는 서비스의 리전 특성을 사전에 파악해야 합니다.

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

## 10. Azure Workbook name 필드 UUID 강제

### 증상
```
Error: expected "name" to be a valid UUID, got siseon-cloudtrail-audit
```

### 원인
`azurerm_application_insights_workbook` 리소스의 `name` 필드는 Azure 스펙상 **UUID 형식만 허용**합니다.

### 해결
`name`에 UUID 형식을 사용하고, 실제 표시 이름은 `display_name`으로 분리했습니다.

```hcl
resource "azurerm_application_insights_workbook" "security_audit" {
  name         = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"  # 내부 UUID
  display_name = "StockOps CloudTrail 보안 감사 대시보드"   # 표시 이름
}
```

### 교훈
Azure 리소스는 AWS와 네이밍 규칙이 다른 경우가 있습니다. 공식 문서의 필드 제약 조건을 사전에 확인해야 합니다.

---

## 11. Azure Workbook location 오타로 배포 실패

### 증상
```
Error: "siseon-rg" was not found in the list of supported Azure Locations
```

### 원인
`main.tf` 작성 시 `location` 필드에 `var.location` 대신 `var.resource_group_name`을 잘못 입력했습니다.

```hcl
# 잘못된 코드
location = var.resource_group_name  ← 리소스 그룹 이름이 들어감

# 올바른 코드
location = var.location             ← Korea Central
```

### 해결
`location` 필드를 `var.location`으로 수정 후 재배포했습니다.

### 교훈
Terraform 코드 작성 시 변수명이 유사한 경우 오타가 발생하기 쉽습니다. `terraform plan` 출력을 꼼꼼히 확인해야 합니다.

---

## 12. Azure Function 코드 배포 별도 필요

### 증상
Terraform apply 성공 후 Azure Portal에서 Function App 함수 목록이 비어있었습니다.

### 원인
Terraform은 Function App **인프라(리소스)**만 생성합니다.
실제 Python 코드는 별도 배포 과정이 필요합니다.

### 해결
Azure Functions Core Tools로 코드를 별도 배포합니다.

```bash
# Azure Functions Core Tools 설치
winget install Microsoft.AzureFunctionsCoreTools
# 또는 https://go.microsoft.com/fwlink/?linkid=2174087 에서 직접 다운로드

# 코드 배포
cd modules/azure_monitor/functions
func azure functionapp publish siseon-blob-to-laws --python
```

### 교훈
Azure Function은 인프라 프로비저닝(Terraform)과 코드 배포(func publish)가 분리된 구조입니다.
배포 순서: `terraform apply` → `func publish`

---

## 13. Azure Monitor Workbook에서 Log Analytics 연결 안 됨

### 증상
Workbook 대시보드를 열면 모든 패널에 아래 오류가 표시됩니다.
```
Log Analytics 작업 영역 리소스가 선택되지 않았습니다.
```

### 원인
Workbook의 KQL 쿼리 패널에 `crossComponentResources` 설정이 없으면
어떤 Log Analytics Workspace를 대상으로 쿼리할지 알 수 없습니다.

### 해결
Terraform의 Workbook `data_json` 내 각 쿼리 패널에 `crossComponentResources`를 추가했습니다.

```hcl
{
  type = 3
  content = {
    version      = "KqlItem/1.0"
    query        = "CloudTrailLogs_CL | take 10"
    queryType    = 0
    resourceType = "microsoft.operationalinsights/workspaces"
    crossComponentResources = [
      "/subscriptions/.../resourceGroups/siseon-rg/providers/Microsoft.OperationalInsights/workspaces/siseon-security-logs"
    ]
  }
}
```

### 교훈
Azure Monitor Workbook에서 Log Analytics 쿼리를 사용할 때는 반드시 대상 Workspace 리소스 ID를 명시해야 합니다.

---

## 14. terraform.tfvars 노트북 환경에서 누락

### 증상
노트북에서 `terraform plan` 실행 시 민감 변수를 콘솔에서 직접 입력하라는 프롬프트가 발생했습니다.

### 원인
`terraform.tfvars`는 민감 정보 포함으로 `.gitignore`에 등록되어 있어 GitHub에 올라가지 않습니다.
새 환경(노트북)에서 `git pull` 후에도 해당 파일이 없는 상태입니다.

### 해결
작업 PC마다 `terraform.tfvars`를 직접 생성해야 합니다.

```hcl
# terraform.tfvars (직접 생성 필요, 절대 커밋 금지)
teams_webhook_login   = "https://..."
teams_webhook_delete  = "https://..."
teams_webhook_billing = "https://..."
azure_connection_string = "DefaultEndpointsProtocol=https;..."
```

### 교훈
민감 변수는 별도 시크릿 관리 도구(AWS Secrets Manager, Azure Key Vault 등) 활용을 권장합니다.
멀티 PC 환경에서는 반드시 첫 작업 전 `terraform.tfvars` 생성 여부를 확인해야 합니다.

---

## 15. AWS Budgets SNS 토픽 발행 권한 누락

### 증상
AWS로부터 아래 메일 수신:
Unfortunately, we are unable to successfully publish to this SNS topic at this time.
Please ensure that AWS Budgets has been added to the list of services that are allowed to publish to this SNS topic.

### 원인
AWS Budgets가 SNS 토픽에 메시지를 발행하려면 SNS 토픽 정책에 `budgets.amazonaws.com` 서비스 권한이 명시적으로 있어야 합니다.
`aws_sns_topic_policy` 리소스가 누락된 상태였습니다.

### 해결
`modules/billing/main.tf`에 SNS 토픽 정책 추가:

```hcl
resource "aws_sns_topic_policy" "billing" {
  arn = aws_sns_topic.billing.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBudgetsPublish"
        Effect    = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.billing.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.account_id
          }
        }
      }
    ]
  })
}
```

### 교훈
AWS Budgets, CloudWatch 등 AWS 서비스가 SNS에 발행하려면 SNS 토픽 정책에 해당 서비스를 명시적으로 허용해야 합니다. 리소스 생성 후 실제 알람이 동작하는지 반드시 검증해야 합니다.

## 16. Azure → AWS SAML Federation 구성

### 증상
처음에 AWS → Azure 방향으로 시도했으나 실패:
Azure AD Direct Federation 설정 불가
→ Microsoft Entra ID Premium P1 라이선스 필요

### 원인
Azure Free 플랜은 **외부 IdP와의 Direct Federation**을 지원하지 않습니다.
AWS → Azure 방향은 Azure가 SP가 되어야 하는데, 이 경우 Azure Premium P1이 필요합니다.

### 해결
방향을 **Azure → AWS**로 전환했습니다.
- Azure Entra ID가 IdP 역할 (SAML Token 발급)
- AWS IAM이 SP 역할 (SAML Token 검증 후 콘솔 접근 허용)
- AWS IAM SAML Federation은 무료로 지원

### 교훈
멀티클라우드 SSO 구성 시 각 클라우드 플랜의 Federation 지원 범위를 사전에 확인해야 합니다.
IdP/SP 방향에 따라 필요한 라이선스가 달라집니다.

## 17. AWS Budgets DAILY 알람 재발송 안 됨

### 증상
매일 $5 이상 비용이 발생하는데 Teams 알람이 첫날 이후 오지 않았습니다.

### 원인
AWS Budgets DAILY 알람은 `ALARM` 상태가 되면 **동일 상태 유지 시 재발송하지 않습니다.**
매일 지출이 리셋돼도 알람 상태는 유지되기 때문에 첫날만 발송됩니다.

1일차: $6 발생 → OK → ALARM → 알람 발송 ✅
2일차: $6 발생 → 이미 ALARM 상태 → 알람 없음 ❌
3일차: $6 발생 → 이미 ALARM 상태 → 알람 없음 ❌

### 해결
**EventBridge + Cost Explorer API 방식**으로 전환했습니다.
상태 개념 없이 매일 KST 09:00에 전일 비용을 직접 조회하여 임계값 초과 시 발송합니다.

EventBridge (매일 KST 09:00)
→ Lambda → Cost Explorer API로 전일 비용 조회
→ $5 초과 시 Teams 발송

### 교훈
AWS Budgets 알람은 상태 기반이라 매일 재발송이 필요한 경우 적합하지 않습니다.
주기적 비용 체크가 필요하면 EventBridge + Cost Explorer API 조합이 더 적합합니다.

## 18. Azure Workbook이 보안 대시보드답지 않음 (조회성 노이즈)

### 증상
CloudTrail 이벤트 Top 10에 Decrypt, Describe, GetCallerIdentity, AssumeRole 등
일상적인 조회성 API가 상위를 차지. 보안 감사 대시보드인데 정작 로그인·삭제·실패 같은
보안 의미 있는 이벤트가 묻혀서 "AWS API 호출 통계"처럼 보임. 소스 IP 차트에도
amazonaws.com 같은 AWS 내부 서비스가 섞여 외부 접근 식별이 어려움.

### 원인
전체 이벤트를 필터 없이 집계. CloudTrail은 조회성(읽기) 호출이 변경 호출보다 압도적으로
많아, 단순 count 시 노이즈가 상위를 점유함. "디자인이 안 예쁜" 문제가 아니라
"보여주는 데이터가 보안과 무관한" 문제였음.

### 해결
KQL을 보안 관점으로 재설계.
- 변경 작업만: `EventName_s startswith "Delete"/"Create"/"Modify"/"Put"...` 화이트리스트 방식
  (조회성 제외는 블랙리스트로는 계속 새어나와 변경 동사만 포함하는 방식이 확실)
- 콘솔 로그인 성공/실패: `parse_json(ResponseElements_s).ConsoleLogin`
- 외부 IP만: `SourceIPAddress_s !endswith ".amazonaws.com"`
- 요약 타일(총 이벤트/오류/로그인/변경)로 한눈 파악 추가

### 교훈
대시보드 "가독성"은 시각화보다 데이터 선택이 먼저다. 노이즈 제거는 데이터 삭제가 아니라
"대시보드 상위 표시에서 제외"일 뿐, 원본은 Log Analytics에 보존되어 필요 시 쿼리 가능하다.

## 19. Azure Function 재배포 누락으로 데이터 미적재

### 증상
Azure를 destroy 후 재apply했더니 Log Analytics에 `CloudTrailLogs_CL` 테이블이 없음.
Blob Storage에는 데이터가 쌓여 있는데 Log Analytics만 비어 있었음.

### 원인
Function 코드 배포(`func publish`)는 Terraform과 별개라 destroy/apply 시 함수가 비워짐.
또한 Blob 트리거는 "새로 올라오는 Blob"에만 반응하므로, 함수를 재배포해도 기존 Blob은
재처리되지 않음. 결과적으로 적재할 코드도, 트리거할 새 Blob도 없는 상태였음.

### 해결
1. `func azure functionapp publish siseon-blob-to-laws --python`로 함수 재배포
   (노트북에 Node.js/func 미설치 → winget으로 설치, F 드라이브 func.exe 직접 경로 실행)
2. S3→Azure Lambda를 백필 이벤트로 수동 실행 → 새 Blob 업로드 → 트리거 → 적재

### 교훈
Terraform 밖의 배포(`func publish`)는 destroy/apply마다 반복 필요. 매일 내리는 운영에서는
`zip_deploy_file`로 코드를 apply에 포함시키는 방식이 근본 해결책 (추후 개선 예정).

## 20. 백업 동기화 갭 — "장애 직전 로그 누락" 설계 결함

### 증상
"AWS 장애 시 확인용"이라면서 하루 1회(새벽 2시) 백업. 오후에 장애가 나면 당일 오전~오후
로그가 Azure에 없어 목적과 구현이 불일치.

### 원인
초기 설계가 "장기 보존" 관점에만 맞춰져 동기화 빈도를 고려하지 않음. 실시간성과
재해복구 시점 간격에 대한 검토 부재.

### 해결
역할을 명확히 분리. 실시간 침해 대응은 CloudTrail → Teams 알림이 담당하고, Azure는
사후 감사·재해복구용으로 정의. 동기화 주기를 하루 1회 → 3회(`cron(0 1,9,17 * * ? *)`,
KST 02/10/18시)로 개선해 갭을 8시간 이내로 축소. Workbook에 마지막 동기화 시각을
표시해 데이터 신선도를 투명하게 노출.

### 교훈
"무엇을 위한 백업인가"가 빈도를 결정한다. 실시간 전체 동기화는 비용·데이터 부담이 크므로,
역할 분리(실시간=알림, 사후=백업) + 적정 주기 + 신선도 표시의 조합이 현실적 균형점이다.



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
| 10 | Workbook name UUID 강제 | Azure 리소스 네이밍 스펙 | UUID 형식 사용 + display_name 분리 |
| 11 | location 오타 배포 실패 | 변수명 혼동 | var.location으로 수정 |
| 12 | Function 코드 미배포 | Terraform은 인프라만 생성 | func publish 별도 실행 |
| 13 | Workbook Workspace 연결 안 됨 | crossComponentResources 누락 | 각 쿼리 패널에 Workspace 리소스 ID 명시 |
| 14 | tfvars 노트북 누락 | .gitignore 처리된 파일 | 작업 PC마다 직접 생성 |
| 15 | AWS Budgets SNS 발행 권한 누락 | SNS 토픽 정책에 budgets.amazonaws.com 미포함 | aws_sns_topic_policy 리소스 추가 |
| 16 | Azure → AWS SAML Federation | Azure Free 플랜 Direct Federation 불가 | 방향 전환 (Azure IdP → AWS SP) |
| 17 | AWS Budgets DAILY 알람 재발송 안 됨 | ALARM 상태 유지 시 재알림 없음 | EventBridge + Cost Explorer 직접 조회 방식 |
| 18 | Workbook 조회성 노이즈 | 전체 이벤트 무필터 집계 | 변경/로그인/외부IP 중심 KQL 재설계 |
| 19 | Function 재배포 누락 데이터 미적재 | func publish는 Terraform 별개 + Blob 트리거는 신규만 | 함수 재배포 + Lambda 백필로 새 Blob 생성 |
| 20 | 백업 동기화 갭 | 하루 1회로 장애 직전 로그 누락 | 역할 분리 + 하루 3회 + 신선도 표시 |