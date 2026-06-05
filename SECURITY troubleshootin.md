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

Power Automate 흐름 구성:
1. **HTTP 요청 수신** 트리거 생성
2. Lambda에서 POST 요청 수신
3. Teams 채널에 메시지 게시

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
로그 이벤트 발생 즉시 Lambda가 트리거되어 **매 이벤트마다 알림**이 발송됩니다.

```python
# Lambda가 CloudWatch Logs에서 직접 CloudTrail 이벤트를 수신
def lambda_handler(event, context):
    log_data = event["awslogs"]["data"]
    decoded = gzip.decompress(base64.b64decode(log_data))
    log_events = json.loads(decoded)
    # 이벤트별 처리...
```

### 교훈
임계값 기반 Alarm은 "상태 변화 감지"에 적합하고,
이벤트 발생 자체를 감지하려면 Subscription Filter 방식이 적합합니다.
요구사항에 맞는 아키텍처를 선택하는 것이 중요합니다.

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
즉시 AWS 콘솔에서 확인하세요.
```

### 원인
Power Automate 흐름이 Lambda에서 전송한 JSON을 무시하고
**하드코딩된 템플릿 메시지**를 고정으로 발송했습니다.

### 해결
1. Lambda에서 CloudTrail 원문을 파싱하여 상세 정보를 JSON으로 전송
2. Power Automate 메시지 내용을 동적 값으로 변경

```
# Power Automate 메시지 설정
@{triggerBody()?['message']}
```

```python
# Lambda - CloudTrail 로그 파싱
username  = user_identity.get("userName") or arn.split("/")[-1]
source_ip = record["sourceIPAddress"]
region    = record["awsRegion"]
result    = record["responseElements"]["ConsoleLogin"]
```

### 최종 알림 형태

```
🔐 콘솔 로그인 감지
👤 사용자: jh.lee
🌐 IP: 121.160.42.57
📍 리전: ap-northeast-2
🔎 결과: ✅ Success
⏰ 시간: 2026-06-04 17:09:38 KST
```

### 교훈
알림 파이프라인 설계 시 메시지 포맷을 사전에 정의하고,
중간 단계(Power Automate 등)의 데이터 처리 방식을 반드시 검증해야 합니다.

---

## 4. Subscription Filter 패턴에 백틱 문자 오류

### 증상
Subscription Filter 생성 시 오류가 발생했습니다.

```
Lambda 구독 필터를 생성하지 못했습니다.
Invalid character(s) in term '`'
```

CloudTrail 로그에서도 확인:
```json
"filterPattern": "`{ ($.eventName = \"Delete*\")"
```

### 원인
복사/붙여넣기 과정에서 패턴 앞에 **백틱(`) 문자**가 포함되었습니다.

### 해결
메모장에 먼저 붙여넣기 후 다시 복사하여 특수문자를 제거했습니다.

```
올바른 패턴:
{ ($.eventName = "Delete*") || ($.eventName = "Remove*") || ($.eventName = "Terminate*") }
```

### 교훈
AWS 콘솔에서 패턴을 직접 입력할 때는 복사/붙여넣기 시 특수문자 유입에 주의해야 합니다.
Terraform 코드로 관리하면 이러한 실수를 방지할 수 있습니다.

---

## 5. Teams 메시지 줄바꿈 미적용

### 증상
Lambda에서 `\n`으로 줄바꿈을 처리했지만 Teams에서 한 줄로 표시됐습니다.

```
🔐 콘솔 로그인 감지 👤 사용자: jh.lee 🌐 IP: 121.160.42.57 ...
```

### 원인
Microsoft Teams 메시지는 일반 텍스트의 `\n`을 줄바꿈으로 처리하지 않습니다.
HTML 형식의 `<br>` 태그를 사용해야 합니다.

### 해결
Lambda 코드에서 `\n` → `<br>` 태그로 변경했습니다.

```python
# 변경 전
message = (
    f"🔐 콘솔 로그인 감지\n"
    f"👤 사용자: {username}\n"
)

# 변경 후
message = (
    f"🔐 콘솔 로그인 감지<br>"
    f"👤 사용자: {username}<br>"
)
```

### 교훈
Teams 메시지 포맷은 HTML을 지원합니다.
줄바꿈, 굵게, 색상 등을 HTML 태그로 처리할 수 있습니다.

---

## 6. CloudTrail → CloudWatch 로그 그룹 미생성

### 증상
CloudWatch에서 `/aws/cloudtrail` 로그 그룹이 생성되지 않았습니다.

### 원인
CloudTrail 생성 후 CloudWatch Logs 연동을 별도로 설정해야 합니다.
기본 생성 시 CloudWatch 연동이 활성화되지 않습니다.

### 해결
CloudTrail 편집 화면에서 CloudWatch Logs 연동을 활성화했습니다.

```hcl
# Terraform 코드
resource "aws_cloudtrail" "main" {
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cw.arn
}
```

### 교훈
CloudTrail의 CloudWatch 연동은 별도 설정이 필요합니다.
Terraform으로 인프라를 코드화하면 이러한 설정 누락을 방지할 수 있습니다.

---

## 📋 트러블슈팅 요약

| # | 문제 | 원인 | 해결 |
|---|------|------|------|
| 1 | Teams 웹훅 중단 | Microsoft 커넥터 서비스 종료 | Power Automate HTTP 트리거로 전환 |
| 2 | 알림 누락 | Alarm 상태 변화 없음 | Subscription Filter → Lambda 방식으로 전환 |
| 3 | 알림 상세 정보 없음 | Power Automate 고정 템플릿 | 동적 메시지 처리로 변경 |
| 4 | 백틱 문자 오류 | 복붙 시 특수문자 유입 | 메모장 경유 후 재복사 |
| 5 | 줄바꿈 미적용 | Teams `\n` 미지원 | `<br>` HTML 태그로 변경 |
| 6 | 로그 그룹 미생성 | CloudTrail-CW 연동 미설정 | CloudWatch Logs 연동 활성화 |