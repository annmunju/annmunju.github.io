---
title: Infra end-to-end 배우기 1) 프로젝트 기획
description: GCP 엔터프라이즈 인프라 설계 및 GKE 기반 Airflow 배포 실습
author: annmunju
date: 2025-09-23 14:29:00 +0900
categories: [Hands On, GCP Infra 구축 실습]
tags: [infra, airflow, k8s]
pin: false
math: true
mermaid: true
comments: true
---

> **Hands-on 실습: GCP 환경에서 엔터프라이즈급 인프라를 직접 설계하고 운영해보자**

이번 시리즈에서는 **Google Cloud Platform(GCP)** 기반으로 엔터프라이즈 표준에 부합하는 인프라 파운데이션을 직접 설계하고, `GKE` 위에 `Apache Airflow`를 배포하는 과정을 다룬다.  

단순히 돌아가는 환경을 만드는 것을 넘어 **보안·거버넌스·비용 최적화**까지 고려한 실습을 통해 실제 기업 환경에 가까운 인프라 아키텍처를 경험하는 것이 목표다.

---

## 1. 주요 목표
- Google 권장 아키텍처 원칙(보안, 거버넌스, 확장성, 가시성 등)을 반영한 **고가용성 인프라** 설계
- GKE 클러스터에 **Apache Airflow**를 Helm Chart로 배포

---

## 2. 실습 요건

### 2.1 프로젝트 구조
- 모든 리소스는 2개의 프로젝트로 분리  
  - `[prefix]-host`: 네트워크·보안·로깅 등 인프라 리소스 관리  
  - `[prefix]-service`: 실제 애플리케이션(Airflow) 배포  
- 명명 규칙 및 리소스 계층 구조 준수

### 2.2 네트워크 아키텍처
- **Shared VPC 아키텍처** 사용 (기본 네트워크 금지)  
- **서브넷 분리**: web / app / db → 티어별 보안 경계 강화  
- **Bastion Host** 운영: 지정된 IP만 SSH 허용, 네트워크 태그 기반 방화벽 제어  
- **Private Google Access** 활성화: 외부 IP 없이 Google API 접근 가능

### 2.3 IAM 및 보안
- Cloud Identity 그룹 기반 권한 관리 (`project-service-dev`, `project-infra-admin`)  
- 개별 사용자 권한 부여 금지, **전용 서비스 계정만 사용**  
- 최소 권한 원칙 적용 (폴더/프로젝트 단위)

### 2.4 로깅 및 규정 준수
- 감사 로그 및 데이터 접근 로그를 **호스트 프로젝트의 중앙 로그 버킷으로 집계**  
- 1년 이상 보관 후 Cloud Storage로 아카이빙  
- 로그 수명주기 정책으로 장기 보관 비용 절감

### 2.5 비용 최적화
- 모든 VM 및 GKE 노드는 `e2-micro` 또는 `e2-small` 등 최소 사양 사용  
- 리소스 자동 종료/스케일링 정책 적용  

---

## 3. Apache Airflow on GKE
Airflow는 데이터 워크플로우 자동화에 널리 사용되는 오케스트레이션 도구다.  
이번 실습에서는 **Helm Chart**를 활용하여 Airflow를 GKE에 배포한다.  

- 실습 포인트:  
  - Helm values.yaml 커스터마이징 (DB 연결, 로그, 인증 설정 등)  
  - Shared VPC 네트워크와 연동  
  - Web UI는 Bastion Host를 통해서만 접근 가능 (외부 인터넷 격리)  

---

## 4. 실습 아키텍처 개요

- 리소스 계층 구조  
  - `[prefix]-host`: 네트워크, 로깅, 보안  
  - `[prefix]-service`: Airflow 등 애플리케이션  
- 네트워크  
  - Shared VPC, 서브넷(web/app/db), Bastion Host, Private Google Access  
- 보안  
  - Cloud Identity 그룹 기반 IAM, 전용 서비스 계정  
- 운영  
  - 중앙 로그 버킷, 장기 보관 아카이빙  
- 비용  
  - 최소 사양 리소스 + 자동 스케일링

---

## 5. 참고 자료
- [Google Cloud Enterprise Foundations Blueprint](https://cloud.google.com/architecture/blueprints/security-foundations/organization-structure?hl=ko)  
- [GKE 공식 문서](https://cloud.google.com/kubernetes-engine/docs?hl=ko)  
- [GCP Shared VPC 개념](https://cloud.google.com/vpc/docs/provisioning-shared-vpc?hl=ko)  
- [IAM Best Practices](https://cloud.google.com/iam/docs/using-iam-securely?hl=ko)  
- [Apache Airflow Helm Chart](https://airflow.apache.org/docs/helm-chart/stable/index.html)  

---

본 실습을 통해 실제 엔터프라이즈 환경에서 통용되는 아키텍처를 직접 설계하고 배포해보는 경험을 쌓아보려고 한다.
우선 전체 아키텍처를 그려보는 작업부터 어떤 작업을 수행해야하는지 TODO를 작성하고 하나씩 해치워보려고 한다. 끝!