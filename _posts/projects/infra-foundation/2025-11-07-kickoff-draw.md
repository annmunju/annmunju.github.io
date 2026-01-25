---
title: Infra end-to-end 배우기 2) 아키텍처 그리기
description: GCP 엔터프라이즈 GKE 기반 인프라 설계하기
author: annmunju
date: 2025-11-07 15:32:00 +0900
categories: [Hands On, GCP Infra 구축 실습]
tags: [infra, airflow, k8s]
pin: false
math: true
mermaid: true
comments: true
---

> **Hands-on 실습: 아키텍처 그리기**

지난번 글에서는 주요 목표와 실습 요건들을 정의하는 사전 작업을 진행했다. 해당 요건에 맞는 GKE 기반 아키텍처를 직접 그려보았다.

![architecture_v1](sources\project2_kickoff\architecture_v1.png)

이번 글은 아키텍처를 세부적으로 소개하면서 지난번 정의한 실습 요건에 맞추어서 작성해보려고 한다.

## 프로젝트 구조

서비스를 주요로 하는 프로젝트와 네트워크 설정을 주요로 하는 프로젝트를 구분했다. 명칭은 `mjahn-host`, `mjahn-service`으로 표기했다.

### Service Project

서비스 프로젝트는 주로 애플리케이션을 배포하는 목적으로 만들어진다. 즉 다른 애플리케이션이 생기면 새로운 서비스 프로젝트를 만들수 있다. 이번 경우에는 airflow를 배포하는 목적으로 만든 케이스다.

User라고 표현한 외부의 행위자에는 두 종류가 있다.
1. 웹 접근 사용자
2. GCP 관리자

각각의 사용자는 각기 다른 방식으로 GCP에 접근한다.
1. 웹 접근 사용자는 Cloud Load Balancing으로 GKE에 배포된 웹 (airflow) 사이트에 접근한다.
2. GCP 관리자는 IAP로 불리는 방식 (gcloud로 접근하는 방식. 구글에서 Identity를 점검하는 Proxy를 쓴다.)으로 Bastion Server를 접근한다. 

이후에 GCP 관리자의 경우 Bastion Server에서 GKE나 RDB에 접근해서 필요한 업무를 진행할 수 있다.

구체적 구성 요소들은 다음과 같다.

1. Bastion VM `bastion-dev-an3-a-01`
    - 의도: 외부 IP 없이 IAP로 안전하게 SSH 접속하는 호스트
    - 핵심 설정
        - Host 방화벽 `fw-allow-iap-ssh-dev`
        (src 35.235.240.0/20, tcp/22, 태그: allow-iap-ssh)
        - VM에는 외부 IP 없이

2. GKE Private 클러스터 gke-dev-an3-private
    - 의도: 외부 공개 없이 프라이빗 제어계면 + 노드 외부 IP 없이 운영.
    Pod/Service IP는 Host 서브넷의 Secondary ranges(pods-dev/svcs-dev) 사용.
    - 핵심 설정
        - --enable-ip-alias + --cluster-secondary-range-name=$PODS_RANGE_NAME
        - --services-secondary-range-name=$SVCS_RANGE_NAME
        - --enable-private-nodes --enable-private-endpoint (외부 공개 엔드포인트 없음)
        - --master-ipv4-cidr=$MASTER_CIDR (예: 172.16.0.16/28)
        - 보안: --workload-pool=${SVC_PROJECT}.svc.id.goog, --enable-network-policy

3. Cloud Load Balancing : External HTTP(S) LB(Ingress/NEG)로 Airflow 웹 노출
    - 의도: 쿠버네티스 Ingress(GCE)로 외부 트래픽을 받아 **HTTPS LB → 백엔드(NEG/파드)**까지 연결



### Host Project

호스트 프로젝트는 나머지 네트워크, 보안 관련 인프라 리소스를 관리하는 목적으로 만들어진다. 이렇게 프로젝트를 분리하는 이유는 일반적으로 네트워크 관리자와 애플리케이션 개발자가 나뉘어져 있기 때문이다. 
  
필요에 맞게 애플리케이션 개발자는 네트워크 관리자에게 필요한 서브넷을 요청하면 그에 맞춰 생성해준다. 이를 Shared VPC로 연결된 호스트 프로젝트로부터 Service Account가 서브넷을 사용할 수 있는 권한을 받아서 서비스 프로젝트가 사용할 수 있는 것이다.

구체적 구성 요소는 다음과 같다.

1. VPC
    - 의도: 모든 서비스 프로젝트가 붙는 중앙 네트워크. 서브넷/방화벽/라우팅을 Host에서 통제
    - 핵심 설정
        - 서브넷 : 직접 서브넷 생성 (custom)
        - 라우팅 모드 : 글로벌 (하이브리드 / 멀티 리전)
        - CIDR 넉넉하게 (확장 / 다중 서브넷 대비)


2. 서브넷 Primary ranges `subnet-dev-an3-a`
    - 의도: dev 환경 워크로드/노드가 실제로 붙는 1차 IP 공간
    - 핵심 설정
        - CIDR: 10.10.0.0/24
        - 리전: asia-northeast3
        - Private Google Access: 외부 IP 없이 GCS/Registry 접근

3. 서브넷 Secondary ranges `pods-dev` `svcs-dev`(GKE VPC-네이티브용)
    - 의도: GKE에서 Pod/Service IP를 분리해 관리
    - 핵심 설정
        - CIDR
            - pods-dev: 10.20.0.0/16 (Pod CIDR)
            - svcs-dev: 10.30.0.0/20 (ClusterIP/Service CIDR)
    
4. Cloud Router `cr-seoul` -> Cloud NAT `nat-seoul`
    - 의도: 외부 IP가 없는 VM/GKE 노드의 아웃바운드 인터넷 접속 (패키지 설치, 이미지 pull 등)

5. 방화벽
    1) `fw-allow-iap-ssh-dev` 
    - 의도: IAP(35.235.240.0/20)에서 22/tcp로만 SSH 허용(대상 VM에 allow-iap-ssh 태그).

    2) `fw-egress-any-dev`
    - 의도: 초기 부트스트랩 편의를 위한 모든 Egress 허용(개발 후 목적지/포트 기반 룰로 축소).

추가로 아키텍처에 표기되진 않았지만 Shared VPC Host로 승격하기 위한 처리가 필요하다.

---

이와 같은 초기 아키텍처를 그렸으니 이제 이후에는 본격적으로 인프라 구성을 완성하는 코드를 작성하고자 한다. 해당 아키텍처 이미지를 계속 Gemini에 먹여서 잘 만들었는지 확인했지만 CA는 아니라.. 혹시 틀렸다면 댓글을 부탁드립니다..   
다음은 해당 프로젝트를 진행하는 구체적인 액션 즉 TODO를 작성하는 과정을 담아보려고 한다. 끝!