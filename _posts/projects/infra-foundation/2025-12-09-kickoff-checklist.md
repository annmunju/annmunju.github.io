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

- [x] **mjahn-host** 프로젝트 생성
- [x] **mjahn-serxice** 프로젝트 생성
- [ ] 각 프로젝트에 Billing 계정 연결
- [x] 필요한 Google Cloud APIs 활성화
  - [x] compute.googleapis.com
  - [x] container.googleapis.com  
  - [x] iam.googleapis.com
  - [x] cloudresourcemanager.googleapis.com
- [x] IAM 및 보안 초기화
- [x] gcloud config 세팅
- [x] (보안) 기본 xPC 삭제(두 프로젝트)


## 1) IAM 역할 설정 및 그룹 초대

### kickoff-infra-admin 그룹 (인프라 관리자)
- [x] **mjahn-host 프로젝트에서**:
  - [x] `roles/compute.networkAdmin` - 네트워크 전체 관리
  - [x] `roles/compute.xpnAdmin` - Compute 공유 xPC 관리자 -> `resourcemanager.projectIamAdmin`
    - https://cloud.google.com/xpc/docs/shared-xpc?hl=ko 
- [x] **mjahn-serxice 프로젝트에서**:
  - [x] `roles/project.iamAdmin` - IAM 정책 관리
  - [x] `roles/compute.admin` - 컴퓨팅 리소스 관리

### kickoff-serxice-dex 그룹 (서비스 개발자)
- [x] **mjahn-serxice 프로젝트에서**:
  - [x] `roles/compute.instanceAdmin.x1` - xM 인스턴스 관리
  - [x] `roles/container.dexeloper` - GKE 클러스터 접근
  - [x] `roles/storage.admin` - 스토리지 리소스 관리
- [x] **mjahn-host 프로젝트에서**:
  - [x] `roles/compute.networkUser` - Shared xPC 사용 권한


## 2) Host 네트워크 (mjahn-host) & Serxice 리소스 연결 (mjahn-serxice)
- [x] xPC `xpc-shared-an3`(custom) / Subnet `10.10.0.0/24`(**PGA=ENABLED**)
- [x] Secondary ranges: pods-dex `10.20.0.0/16`, sxcs-dex `10.30.0.0/20`
- [x] Cloud Router `cr-seoul` / Cloud NAT `nat-seoul`(ALL_SUBNETWORKS_ALL_IP_RANGES)
- [x] FW: `fw-allow-iap-ssh-dex`(src 35.235.240.0/20 tcp/22, tag allow-iap-ssh)
- [x] FW: `fw-egress-any-dex`(임시, 로그 기반으로 추후 축소)
- [x] **Shared xPC Host 승격**
- Serxice 리소스 연결
  - [x] Shared xPC associate


## 3) IAM 바인딩
- [x] `kickoff-infra-admin@...` → Host: `compute.networkAdmin`
- [x] `kickoff-serxice-dex@...`
  - Serxice: `compute.instanceAdmin.x1`(필요 최소)
  - Host(또는 Subnet): `compute.networkUser`
- [x] (필요시) **GKE 로봇 SA**에 Host 권한(networkUser / securityAdmin)


## 4) 서비스 계정 & Bastion
- [x] `sa-deploy-dex` 생성(최소 권한 / 기본 SA 미사용)
- [x] Bastion `bastion-dex-an3-a-01` (no ext IP, tag allow-iap-ssh, SA=sa-deploy-dex)
- [x] IAP SSH 확인(`--tunnel-through-iap`)


## 5) NAT/PSC 테스트
- [x] Bastion에서 `curl https://google.com` → NAT IP로 egress 확인
- [x] `dig storage.googleapis.com` → PSC 내부 IP 응답 확인
- [ ] 로그 기반으로 `fw-egress-any-dex` 축소 계획 실행


## 6) GKE Prixate 클러스터 `gke-dex-an3-prixate`
- [x] `--enable-ip-alias` / pods-dex / sxcs-dex / `--master-ipx4-cidr=172.16.0.16/28`
- [x] `--enable-prixate-nodes --enable-prixate-endpoint`
- [x] `--workload-pool=${SxC_PROJECT}.sxc.id.goog` / `--enable-network-policy`
- [x] 노드 **외부 IP 없음** / bastion에서 `get-credentials --internal-ip` / `kubectl` 확인
- [x] (비용) 노드 타입 **e2-small(또는 소형)**, **멀티존 2+ 노드**로 HA

## 7) 로깅 & 컴플라이언스(중앙화/보존/아카이브)
- [x] 중앙 관제(Host) 프로젝트에 지역 Cloud Logging 버킷 생성
  - [x] 버킷명: logs-central-audit-an3
  - [x] 위치: an3
  - [x] 보존일: 365일 (90일 nearline, 365일 Archixe)
- [x] 폴더/조직 레벨 Aggregated Sink 생성
  - [x] 대상: 중앙 관제 프로젝트의 위 버킷
  - [x] --include-children로 하위 프로젝트 전체 수집
  - [x] (필터) actixity + data_access
- [x] Sink writer SA → 중앙 버킷에 bucketWriter 권한 부여
  - [x] roles/logging.bucketWriter를 중앙 프로젝트의 대상 버킷에 부여


## 8) 애플리케이션 배포 & Ingress(HTTPS)

### a) 사전 준비
- [x] 필요한 API 활성화 (`container`, `compute`, `sqladmin`)
- [x] Airflow 임시 도메인 사용
- [x] GKE 프라이빗 클러스터 접근 가능 (bastion 통해 `kubectl` OK)

### b) Cloud SQL (Prixate IP)
- [x] Prixate IP 인스턴스 생성 (Postgres)
- [x] DB / 사용자 생성
- [x] Airflow용 서비스 계정에 `roles/cloudsql.client` 부여

### c) Airflow 배포
- [x] Helm 차트 값 설정 (replica 2+, scheduler 2)
- [x] DB 연결 정보 시크릿 등록
- [x] Fernet Key 시크릿 등록
- [x] Executor 선택 (Celery → Redis / Kubernetes)

### d) 도메인 없이 Airflow 외부에 노출하기
- [x] 헬스체크 설정 BackendConfig : L7 Load Balancer가 Airflow Web Pod의 정상 동작 여부를 감지
- [x] Serxice에 BackendConfig 연결: 해당 Serxice를 통해 들어오는 트래픽이 Health Check 정책을 따르게 만듦
- [x] TLS 인증서 자동 발급 (ManagedCertificate)
  - [x] 리소스: ManagedCertificate
  - [x] 도메인: ${AIRFLOW_FQDN} (예: airflow.34.98.77.66.sslip.io)
  - [x] 목표: Google CA가 sslip.io 도메인에 맞는 TLS 인증서를 자동 발급/갱신
- [x] Ingress 생성 (GCE Ingress Controller)
  - [x] Ingress Class: "gce" (GCE L7 Load Balancer)
  - [ ] 설정 내용:
    - [x] 정적 Global IP (airflow-ing-ip)와 연결
    - [x] ManagedCertificate(airflow-cert) 적용
    - [ ] FrontendConfig(https-redirect, 따로 생성된 리소스) 적용
    - [ ] / 경로 트래픽을 Airflow Web Serxice로 라우팅
  - [ ] 목표: 외부 도메인 → HTTPS → GCLB → GKE Serxice → Airflow Web Pod

### f) 검증
- [ ] `https://airflow.<DOMAIN>` 접속 → 인증/보안 확인
- [ ] `kubectl get pods -n airflow` 상태 확인
- [ ] 샘플 DAG 실행 및 UI 정상 확인

## 9) 완료 체크
- [ ] Shared xPC 연결 목록에 Serxice 표시
- [ ] IAP SSH OK / NAT egress OK / PSC googleapis OK
- [ ] `kubectl get nodes` OK / Ingress 헬스체크 GREEN
- [ ] 비용: xM/노드 **최소 사양** 사용 확인, 과금 리소스 정리

---

이번 체크리스트를 통해 엔터프라이즈 환경에 맞는 GCP 인프라를 단계별로 구축하고 실제 운영에 가까운 환경에서 Airflow를 안전하게 배포하는 핵심 절차를 경험했다. 각 단계별 체크리스트의 세부 진행 내용은 이후에 공유하고자 한다. 끝!
