---
title: Oracle database 19c 설치
description: GCP 인스턴스에 직접 DB 설치하기
author: annmunju
date: 2025-06-30 20:25:00 +0900
categories: [Hands On, DB]
tags: [Oracle, DB]
pin: false
math: true
mermaid: true
comments: true
---

> 인스턴스 생성 후 오라클 설치. 영구 디스크 사용해서 /opt/oracle 마운트

### 사전 조건
1. 외부 IP 할당 받아서 설치, 아니면 NAT GW 사용해서 프라이빗으로 설치? 
    - 퍼블릭 설치
2. 필요한 OS? 
    - 설치 가이드 보고 가장 적합한 OS 설치 -> Oracle Linux 8
3. 디스크 용량 얼마나? 
    - 50G
4. 지정된 파일시스템 형식이나 VM 사양?
    - 최소 사양의 vm 사용
5. OS 설치된 디스크 백업 필요한지?
    - 불필요


## 진행 순서 요약

1. VM 생성 후 오라클 파일 업로드
2. DB 영구 디스크 마운트
3. 해당 디스크에 설치하고 확인하기
4. 디스크 분리 후 다른 VM에 이전 하기