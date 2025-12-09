---
title: Infra end-to-end 배우기 3) 체크리스트 작성하기
description: GCP 엔터프라이즈 인프라 코드 구현 순서
author: annmunju
date: 2025-12-09 12:42:00 +0900
categories: [Hands On, GCP Infra 구축 실습]
tags: [infra, airflow, k8s]
pin: false
math: true
mermaid: true
comments: true
---

> **Hands-on 실습: 체크리스트 작성**

지난 글에 실습 요건과 전체적인 아키텍처를 그려보았다.  
이번 단계에서는 실제 작업한 내용의 체크리스트를 정리한다.  
다음 글에 이어서 실제로 사용한 cli 명령어를 정리할 예정이다.
  

## 0) 프로젝트 생성 및 기본 설정

- [v] **mjahn-host** 프로젝트 생성
- [v] **mjahn-service** 프로젝트 생성
- [-] 각 프로젝트에 Billing 계정 연결
- [v] 필요한 Google Cloud APIs 활성화
  - [v] compute.googleapis.com
  - [v] container.googleapis.com  
  - [v] iam.googleapis.com
  - [v] cloudresourcemanager.googleapis.com
- [v] IAM 및 보안 초기화
- [v] gcloud config 세팅
- [v] (보안) 기본 VPC 삭제(두 프로젝트)


## 1) IAM 역할 설정 및 그룹 초대

### kickoff-infra-admin 그룹 (인프라 관리자)
- [v] **mjahn-host 프로젝트에서**:
  - [v] `roles/compute.networkAdmin` - 네트워크 전체 관리
  - [v] `roles/compute.xpnAdmin` - Compute 공유 VPC 관리자 -> `resourcemanager.projectIamAdmin`
    - https://cloud.google.com/vpc/docs/shared-vpc?hl=ko 
- [v] **mjahn-service 프로젝트에서**:
  - [v] `roles/project.iamAdmin` - IAM 정책 관리
  - [v] `roles/compute.admin` - 컴퓨팅 리소스 관리

### kickoff-service-dev 그룹 (서비스 개발자)
- [v] **mjahn-service 프로젝트에서**:
  - [v] `roles/compute.instanceAdmin.v1` - VM 인스턴스 관리
  - [v] `roles/container.developer` - GKE 클러스터 접근
  - [v] `roles/storage.admin` - 스토리지 리소스 관리
- [v] **mjahn-host 프로젝트에서**:
  - [v] `roles/compute.networkUser` - Shared VPC 사용 권한


## 2) Host 네트워크 (mjahn-host) & Service 리소스 연결 (mjahn-service)
- [v] VPC `vpc-shared-an3`(custom) / Subnet `10.10.0.0/24`(**PGA=ENABLED**)
- [v] Secondary ranges: pods-dev `10.20.0.0/16`, svcs-dev `10.30.0.0/20`
- [v] Cloud Router `cr-seoul` / Cloud NAT `nat-seoul`(ALL_SUBNETWORKS_ALL_IP_RANGES)
- [v] FW: `fw-allow-iap-ssh-dev`(src 35.235.240.0/20 tcp/22, tag allow-iap-ssh)
- [v] FW: `fw-egress-any-dev`(임시, 로그 기반으로 추후 축소)
- [v] **Shared VPC Host 승격**
- Service 리소스 연결
  - [v] Shared VPC associate


## 3) IAM 바인딩
- [v] `kickoff-infra-admin@...` → Host: `compute.networkAdmin`
- [v] `kickoff-service-dev@...`
  - Service: `compute.instanceAdmin.v1`(필요 최소)
  - Host(또는 Subnet): `compute.networkUser`
- [v] (필요시) **GKE 로봇 SA**에 Host 권한(networkUser / securityAdmin)


## 4) 서비스 계정 & Bastion
- [v] `sa-deploy-dev` 생성(최소 권한 / 기본 SA 미사용)
- [v] Bastion `bastion-dev-an3-a-01` (no ext IP, tag allow-iap-ssh, SA=sa-deploy-dev)
- [v] IAP SSH 확인(`--tunnel-through-iap`)


## 5) NAT/PSC 테스트
- [v] Bastion에서 `curl https://google.com` → NAT IP로 egress 확인
- [v] `dig storage.googleapis.com` → PSC 내부 IP 응답 확인
- [ ] 로그 기반으로 `fw-egress-any-dev` 축소 계획 실행


## 6) GKE Private 클러스터 `gke-dev-an3-private`
- [v] `--enable-ip-alias` / pods-dev / svcs-dev / `--master-ipv4-cidr=172.16.0.16/28`
- [v] `--enable-private-nodes --enable-private-endpoint`
- [v] `--workload-pool=${SVC_PROJECT}.svc.id.goog` / `--enable-network-policy`
- [v] 노드 **외부 IP 없음** / bastion에서 `get-credentials --internal-ip` / `kubectl` 확인
- [v] (비용) 노드 타입 **e2-small(또는 소형)**, **멀티존 2+ 노드**로 HA

## 7) 로깅 & 컴플라이언스(중앙화/보존/아카이브)
- [v] 중앙 관제(Host) 프로젝트에 지역 Cloud Logging 버킷 생성
  - [v] 버킷명: logs-central-audit-an3
  - [v] 위치: an3
  - [v] 보존일: 365일 (90일 nearline, 365일 Archive)
- [v] 폴더/조직 레벨 Aggregated Sink 생성
  - [v] 대상: 중앙 관제 프로젝트의 위 버킷
  - [v] --include-children로 하위 프로젝트 전체 수집
  - [v] (필터) activity + data_access
- [v] Sink writer SA → 중앙 버킷에 bucketWriter 권한 부여
  - [v] roles/logging.bucketWriter를 중앙 프로젝트의 대상 버킷에 부여


## 8) 애플리케이션 배포 & Ingress(HTTPS)

### a) 사전 준비
- [v] 필요한 API 활성화 (`container`, `compute`, `sqladmin`)
- [v] Airflow 임시 도메인 사용
- [v] GKE 프라이빗 클러스터 접근 가능 (bastion 통해 `kubectl` OK)

### b) Cloud SQL (Private IP)
- [v] Private IP 인스턴스 생성 (Postgres)
- [v] DB / 사용자 생성
- [v] Airflow용 서비스 계정에 `roles/cloudsql.client` 부여

### c) Airflow 배포
- [v] Helm 차트 값 설정 (replica 2+, scheduler 2)
- [v] DB 연결 정보 시크릿 등록
- [v] Fernet Key 시크릿 등록
- [v] Executor 선택 (Celery → Redis / Kubernetes)

### d) 도메인 없이 Airflow 외부에 노출하기
- [v] 헬스체크 설정 BackendConfig : L7 Load Balancer가 Airflow Web Pod의 정상 동작 여부를 감지
- [v] Service에 BackendConfig 연결: 해당 Service를 통해 들어오는 트래픽이 Health Check 정책을 따르게 만듦
- [v] TLS 인증서 자동 발급 (ManagedCertificate)
  - [v] 리소스: ManagedCertificate
  - [v] 도메인: ${AIRFLOW_FQDN} (예: airflow.34.98.77.66.sslip.io)
  - [v] 목표: Google CA가 sslip.io 도메인에 맞는 TLS 인증서를 자동 발급/갱신
- [v] Ingress 생성 (GCE Ingress Controller)
  - [v] Ingress Class: "gce" (GCE L7 Load Balancer)
  - [ ] 설정 내용:
    - [v] 정적 Global IP (airflow-ing-ip)와 연결
    - [v] ManagedCertificate(airflow-cert) 적용
    - [ ] FrontendConfig(https-redirect, 따로 생성된 리소스) 적용
    - [ ] / 경로 트래픽을 Airflow Web Service로 라우팅
  - [ ] 목표: 외부 도메인 → HTTPS → GCLB → GKE Service → Airflow Web Pod

### f) 검증
- [ ] `https://airflow.<DOMAIN>` 접속 → 인증/보안 확인
- [ ] `kubectl get pods -n airflow` 상태 확인
- [ ] 샘플 DAG 실행 및 UI 정상 확인

## 9) 완료 체크
- [ ] Shared VPC 연결 목록에 Service 표시
- [ ] IAP SSH OK / NAT egress OK / PSC googleapis OK
- [ ] `kubectl get nodes` OK / Ingress 헬스체크 GREEN
- [ ] 비용: VM/노드 **최소 사양** 사용 확인, 과금 리소스 정리

---

이번 체크리스트를 통해 엔터프라이즈 환경에 맞는 GCP 인프라를 단계별로 구축하고 실제 운영에 가까운 환경에서 Airflow를 안전하게 배포하는 핵심 절차를 경험했다. 각 단계별 체크리스트의 세부 진행 내용은 이후에 공유하고자 한다. 끝!
