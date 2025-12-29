---
title: Infra end-to-end 배우기 4) 프로젝트 생성 및 기본 설정
description: GCP 기반 인프라 세팅 (1)
author: annmunju
date: 2025-12-29 22:03:28 +0900
categories: [Hands On, GCP Infra 구축 실습]
tags: [infra, airflow, k8s]
pin: false
math: true
mermaid: true
comments: true
---

지난번 정리했던 체크리스트를 바탕으로 실제 작성했던 스크립트를 공유하고자 한다.  
프로젝트 생성부터 IAM 바인딩 까지 사전 설정해야하는 부분을 중심으로 작성했다.  


## 0) 프로젝트 생성 및 기본 설정

프로젝트 생성 및 기본 설정을 위해 준비해야 할 구체적인 항목은 다음과 같다.  
- Host / Service 프로젝트 생성
- IAM 및 보안 초기화
- gcloud config profile 세팅
- 기본 VPC 삭제 (보안 목적)

실행 환경이 윈도우 로컬 PC여서 이에 알맞게 CMD 에서 사용 가능한 문법으로 구성되어 있다.  
사전 변수 ACCUNT_MAIL, HOST_PROJECT, SVC_PROJECT, REGION, ZONE을 할당했다.

```cmd
REM --- gcloud 구성 생성 (재실행 안전: || true) ---
gcloud config configurations create mjahn-host    || true
gcloud config configurations create mjahn-service || true

REM --- Host 프로젝트 Config 값 세팅 ---
gcloud config set --configuration=mjahn-host core/account   %ACCUNT_MAIL%
gcloud config set --configuration=mjahn-host core/project   %HOST_PROJECT%
gcloud config set --configuration=mjahn-host compute/region %REGION%
gcloud config set --configuration=mjahn-host compute/zone   %ZONE%

REM --- Service 프로젝트 Config 값 세팅 ---
gcloud config set --configuration=mjahn-service core/account   %ACCUNT_MAIL%
gcloud config set --configuration=mjahn-service core/project   %SVC_PROJECT%
gcloud config set --configuration=mjahn-service compute/region %REGION%
gcloud config set --configuration=mjahn-service compute/zone   %ZONE%

REM --- 구성 목록 확인 ---
gcloud config configurations list

REM --- 구성 전환 시 ---
REM gcloud config configurations activate mjahn-host
REM gcloud config configurations activate mjahn-service

REM --- 보안: 기본 방화벽 규칙 및 기본 VPC 삭제 ---
gcloud compute firewall-rules delete default-allow-icmp default-allow-internal default-allow-ssh default-allow-rdp --project=%HOST_PROJECT% --quiet || true
gcloud compute firewall-rules delete default-allow-icmp default-allow-internal default-allow-ssh default-allow-rdp --project=%SVC_PROJECT% --quiet || true

gcloud compute networks delete default --project=%HOST_PROJECT% --quiet || true
gcloud compute networks delete default --project=%SVC_PROJECT% --quiet || true

REM --- 검증 ---
gcloud projects describe %HOST_PROJECT%
gcloud projects describe %SVC_PROJECT%
```

---

## 1) IAM 역할 설정 및 그룹 초대

여기서는 **사람 그룹(Google Groups)**에 프로젝트 레벨 IAM 역할을 부여한다.  
그룹은 여러 사람을 묶어 한 번에 권한을 관리할 수 있게 해주는 개념이다. 두 가지 그룹으로 나누어 권한을 설정한다.

- **kickoff-infra-admin 그룹**  
  - *Host 프로젝트*  
    - `roles/compute.networkAdmin` : 네트워크 전체 관리  
    - `roles/compute.xpnAdmin` : 공유 VPC(XPC) 관리  
  - *Service 프로젝트*  
    - `roles/project.iamAdmin` : IAM 정책 관리  
    - `roles/compute.admin` : 컴퓨팅 리소스 관리  

- **kickoff-service-dev 그룹**  
  - *Service 프로젝트*  
    - `roles/compute.instanceAdmin.v1` : 인스턴스 관리  
    - `roles/container.developer` : GKE 클러스터 접근  
    - `roles/storage.admin` : 스토리지 리소스 관리  
  - *Host 프로젝트*  
    - `roles/compute.networkUser` : Shared VPC 사용 권한  

해당 그룹 초대 및 권한 바인딩은 gcp 콘솔에서 작업하였다.  
설정 후 다음과 같은 코드로 검증할 수 있다. (출력되면 해당 그룹 잘 적용되었는지 확인 가능)

```
REM --- 검증 ---
gcloud projects get-iam-policy %HOST_PROJECT%
gcloud projects get-iam-policy %SVC_PROJECT%
```

---

## 2) Host 네트워크 (mjahn-host) & Service 연결 (mjahn-service)

앞선 그룹 초대가 끝나야 다음과 같은 작업이 가능하므로 순차적으로 진행해야한다!  
이어서는 실제 리소스 생성 부분이다. 

### 2-1) vpc 생성 및 서브넷 정의
먼저 가상 프라이빗 클라우드 VPC를 생성하고 할당할 서브넷을 미리 생성한다.  
사전에 그려둔 아키텍처에 맞춰 IP 범위를 설정해두었다.  
```cmd
REM --- VPC 생성 ---
gcloud compute networks create %NETWORK% ^
  --subnet-mode=custom ^
  --project=%HOST_PROJECT%

REM --- Subnet + Secondary Range 생성 ---
gcloud compute networks subnets create %SUBNET% ^
  --project=%HOST_PROJECT% ^
  --region=%REGION% ^
  --network=%NETWORK% ^
  --range=10.10.0.0/24 ^
  --secondary-range=%PODS_RANGE_NAME%=10.20.0.0/16,%SVCS_RANGE_NAME%=10.30.0.0/20
```

### 2-2) Private Google Access 활성화
프라이빗 내부에서 구글 API를 사용하기 위해서는 Private Google Access를 활성화 해야한다. [관련 링크](https://docs.cloud.google.com/vpc/docs/private-google-access?hl=ko)  

```cmd
REM --- Private Google Access 활성화 ---
gcloud compute networks subnets update %SUBNET% ^
  --project=%HOST_PROJECT% ^
  --region=%REGION% ^
  --enable-private-ip-google-access
```

### 2-3) Cloud Router & NAT 설정
퍼블릭 네트워크 접속(패키지 다운로드나 구글 API 접속...)을 위해서는 라우터/주소변환(NAT)이 필요하다.  

```cmd
REM --- Cloud Router / NAT ---
gcloud compute routers create cr-seoul ^
  --project=%HOST_PROJECT% ^
  --region=%REGION% ^
  --network=%NETWORK%

gcloud compute routers nats create nat-seoul ^
  --project=%HOST_PROJECT% ^
  --region=%REGION% ^
  --router=cr-seoul ^
  --nat-all-subnet-ip-ranges ^
  --auto-allocate-nat-external-ips ^
  --enable-logging
```

### 2-4) Firewall Rules 작성
이에 맞춰 방화벽 규칙도 작성한다.  
우선 ssh 허용 규칙과 외부로 나가는 규칙은 전체 허용했다. (사실 그럼 안됨.. 외부 허용 못하게 보안 설정 해둬야 했는데 첫 세팅 때는 이렇게 했다.)  

```cmd
REM --- FW: IAP SSH 허용 ---
gcloud compute firewall-rules create fw-allow-iap-ssh-dev ^
  --project=%HOST_PROJECT% ^
  --network=%NETWORK% ^
  --direction=INGRESS ^
  --priority=1000 ^
  --action=ALLOW ^
  --rules=tcp:22 ^
  --source-ranges=35.235.240.0/20 ^
  --target-tags=allow-iap-ssh

REM --- FW: 초기 Egress 허용 (임시) ---
gcloud compute firewall-rules create fw-egress-any-dev ^
  --project=%HOST_PROJECT% ^
  --network=%NETWORK% ^
  --direction=EGRESS ^
  --priority=65534 ^
  --action=ALLOW ^
  --rules=tcp,udp,icmp ^
  --destination-ranges=0.0.0.0/0 ^
  --enable-logging
```


### 2-5) Shared VPC 연결

마지막으로 Shared VPC를 연결하고 네트워크 설정이 되었는지 확인한다.  

```cmd
REM --- Shared VPC 연결 ---
gcloud compute shared-vpc enable %HOST_PROJECT%
gcloud compute shared-vpc associated-projects add %SVC_PROJECT% --host-project=%HOST_PROJECT%

REM --- 검증 ---
gcloud compute networks describe %NETWORK% --project=%HOST_PROJECT%
gcloud compute networks subnets describe %SUBNET% --region=%REGION% --project=%HOST_PROJECT%
gcloud compute routers describe cr-seoul --region=%REGION% --project=%HOST_PROJECT%
gcloud compute firewall-rules list --project=%HOST_PROJECT%
```

---

## 3) IAM 바인딩

이 섹션에서는 **서비스 어카운트(Service Account)**를 생성하고 권한을 부여한다.  
서비스 어카운트는 사람이 아닌 애플리케이션이나 코드가 GCP 리소스에 접근할 때 사용하는 비인간 계정이다.

### 3-1) 사전 설정된 그룹 권한 요약
섹션 1에서 이미 설정한 **사람 그룹(Google Groups)** 권한은 다음과 같다:
- **kickoff-infra-admin 그룹**: Host 프로젝트에 `compute.networkAdmin` (네트워크 관리자)
- **kickoff-service-dev 그룹**: Service 프로젝트에 `compute.instanceAdmin.v1`, Host/Subnet에 `compute.networkUser` (개발자)

### 3-2) 서비스 프로젝트 번호 조회
서비스 어카운트 생성에 필요한 프로젝트 번호를 조회한다.

```cmd
REM --- 서비스 프로젝트 번호 조회 (SVC_PROJECT_NUMBER 할당) ---
for /f "tokens=*" %%i in ('gcloud projects describe %SVC_PROJECT% --format^="value(projectNumber)"') do set SVC_PROJECT_NUMBER=%%i
```

### 3-3) 배포용 서비스 어카운트 생성
애플리케이션 배포 시 사용할 서비스 어카운트를 생성한다.  
서비스 어카운트는 애플리케이션이 GCP 리소스에 접근할 때 사용하는 계정이다.

```cmd
REM --- 배포용 서비스 어카운트 생성 (재실행 안전: || true) ---
set SA_DEPLOY=sa-deploy-dev

gcloud iam service-accounts create %SA_DEPLOY% ^
  --project=%SVC_PROJECT% ^
  --display-name="Deploy SA" || true
```

### 3-4) 배포용 SA에 Host VPC 사용 권한 부여
Shared VPC(Host 프로젝트)를 사용하려면 이 권한이 필요하다.

```cmd
REM --- 배포용 SA에 Host VPC 사용 권한 부여 ---
gcloud projects add-iam-policy-binding %HOST_PROJECT% ^
  --member=serviceAccount:%SA_DEPLOY%@%SVC_PROJECT%.iam.gserviceaccount.com ^
  --role=roles/compute.networkUser
```

### 3-5) 배포용 SA에 Service 프로젝트 최소 권한 부여
로깅, 모니터링, Artifact Registry 읽기 등 애플리케이션 실행에 필요한 최소 권한을 부여한다.

```cmd
REM --- 배포용 SA에 Service 프로젝트 최소 권한 부여 ---
for %%R in (
  roles/logging.logWriter
  roles/monitoring.metricWriter
  roles/artifactregistry.reader
) do (
  gcloud projects add-iam-policy-binding %SVC_PROJECT% ^
    --member=serviceAccount:%SA_DEPLOY%@%SVC_PROJECT%.iam.gserviceaccount.com ^
    --role=%%R
)
```

### 3-6) (선택) GKE SA에 Host VPC 사용 권한 부여
GKE 클러스터가 Shared VPC를 사용하려면 자동 생성된 서비스 어카운트에도 권한이 필요하다.  
**주의**: GKE 생성 후 SA를 확인한 다음 실행해야 한다.

```cmd
REM --- GKE SA에 Host VPC 사용 권한 부여 ---
REM ※ GKE 생성 후 robot SA 확인 필요
REM gcloud projects add-iam-policy-binding %HOST_PROJECT% ^
REM   --member=serviceAccount:%GKE_ROBOT_SA%@%HOST_PROJECT%.iam.gserviceaccount.com ^
REM   --role=roles/compute.networkUser
```

### 3-7) kickoff-service-dev 그룹이 배포용 SA 사용 권한 부여
그룹이 서비스 어카운트를 사용할 수 있도록 권한을 부여한다.  
개발자가 배포 작업 시 이 서비스 어카운트의 권한을 빌려서 사용할 수 있게 된다.

```cmd
REM --- kickoff-service-dev 그룹이 배포용 SA를 사용할 수 있도록 권한 부여 ---
gcloud iam service-accounts add-iam-policy-binding %SA_DEPLOY%@%SVC_PROJECT%.iam.gserviceaccount.com ^
  --member=group:kickoff-service-dev@%DOMAIN% ^
  --role=roles/iam.serviceAccountUser ^
  --project=%SVC_PROJECT%
```

### 3-8) IAP SSH 접속 권한 추가
Identity-Aware Proxy를 통한 SSH 접속을 위해 사람 그룹에 권한을 부여한다.  
이는 서비스 어카운트가 아닌 **그룹에 대한 프로젝트 레벨 권한** 설정이다.

```cmd
REM --- SVC_PROJECT 권한 추가 (IAP SSH 접속 허용) ---
gcloud projects add-iam-policy-binding %SVC_PROJECT% ^
  --member=group:kickoff-service-dev@%DOMAIN% ^
  --role=roles/iap.tunnelResourceAccessor
```

### 3-9) 검증
설정이 올바르게 적용되었는지 확인한다.

```cmd
REM --- 검증 ---
gcloud iam service-accounts list --project=%SVC_PROJECT%
gcloud projects get-iam-policy %HOST_PROJECT%
gcloud projects get-iam-policy %SVC_PROJECT%
```

---

이번 글에서는 앞서 정리했던 체크리스트 중 0) 프로젝트 생성 및 기본 설정부터 3) IAM 바인딩까지의 실습을 실제로 진행한 결과와, 진행하며 사용했던 주요 스크립트, 체크포인트를 중심으로 공유했다.  

해당 과정을 따라가며 Host/Service 프로젝트 분리, 기본 VPC/방화벽 삭제, 그룹 단위 IAM 역할 부여, 그리고 핵심 리소스 연결을 단계적으로 구축할 수 있었다. 실제 엔터프라이즈 환경에서 요구되는 보안 및 거버넌스 요구사항을 반영하는 데에도 초점을 두었다. 

이후 리소스 생성에 대한 부분으로 이어서 자세하게 정리할 예정이다. 끝!