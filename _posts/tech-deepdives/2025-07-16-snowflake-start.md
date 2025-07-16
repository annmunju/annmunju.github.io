---
title: Snowflake Onboarding
description: 스노우플레이크 이해하기
author: annmunju
date: 2025-07-16 10:11:00 +0900
categories: [기술 공부 기록, DW]
tags: [snowflake, dw]
pin: false
math: true
mermaid: false
comments: false
---

> SnowPro Core 자격증 준비를 위한 개념 공부

오늘은 Snowflake의 전체적인 구성과 기본 개념을 정리하고자 한다.

1. 아키텍처 구성요소
2. Role-Based Access Control (RBAC)
3. 가상 웨어하우스
4. 가격 책정 모델

순으로 정리한다.


---

## 1. 아키텍처 구성요소 [(참고)](https://docs.snowflake.com/ko/user-guide/intro-key-concepts#database-storage)

스노우플레이크의 주요 특징은 MPP(대규모 병렬 처리) 컴퓨팅 클러스터를 사용하여 쿼리를 처리한다는 점과 클라우드 인프라에서 모든 것이 실행된다는 점이다.
이런 두 특징 덕분에 공유 디스크 아키텍처의 단순한 데이터 관리와 비공유 아키텍처의 성능 및 확장성 이점을 모두 활용할 수 있다.

![](https://docs.snowflake.com/ko/_images/architecture-overview.png)
아키텍처를 구성하는 주요 레이어는 다음과 같다.

### a. 데이터베이스 저장소 (database storage)
최적화 & 압축된 열 형식으로 구성된 저장소. 스노플이 관리하는 데이터 오브젝트는 별도의 SQL 쿼리 연산을 통해서만 액세스할 수 있다.

### b. 쿼리 처리 (query processing)
가상 웨어하우스를 통해 쿼리를 처리한다. 각 가상 웨어하우스는 여러 컴퓨팅 노드로 구성되는 MPP 컴퓨팅 클러스터다. 

### c. 클라우드 서비스 (cloud service)
클라우드 서비스 레이어는 클라우드 공급자로부터 Snowflake가 프로비저닝하는 컴퓨팅 인스턴스에서도 실행된다. 

- 인증
- 인프라 관리 (컴퓨트 엔진 관리, 서버리스 컴퓨트 처리)
- 메타데이터 관리
- 쿼리 구문 분석 및 최적화
- 액세스 제어
와 같은 서비스들을 관리한다.

---

## 2. Role-Based Access Control (RBAC) [(참고)](https://docs.snowflake.com/ko/user-guide/security-access-control-overview)

RBAC은 사용자가 시스템 리소스에 대한 접근을 할 수 있는 권한을 역할(role)에 기반하여 관리하는 보안 모델이다.
액세스 권한은 역할에 할당되며 이후에 사용자에게 할당된다. 역할은 권한의 집합 또는 단위.

![주요 개념 도식](sources\tech-deep-dives\2025-07-16-snowflake-start\1.png)

위 그림 가장 상위에 있는 object에는 다음과 같은 종류가 들어올 수 있다.
- Account 레벨 : user, role, warehouse, resource monitor, integration, database
- Database 레벨 : schema
- Schema 레벨 : table, external table, view, procedure, sequence, stage, file format, pipe, stream, task, UDF

그다음인 권한은 지정된 역할이 수행할 수 있는 작업이나 접근할 수 있는 자원을 정의한다.

역할은 이렇게 보유한 권한을 바탕으로 특정 작업이나 기능을 수행할 수 있다. 역할은 다른 역할에 할당하여 계층 구조로 사용할 수 있으며 여걸 권한을 보유할 수도 있다.

각 사용자는 하나 이상의 역할에 할당해 자신이 할당된 범위 내에서 오브젝트에 접근할 수 있다. 

### a. 보안 오브젝트
다음은 오브젝트 및 컨테이너의 계층 구조이다.
![보안 오브젝트](https://docs.snowflake.com/ko/_images/securable-objects-hierarchy.png)

오브젝트를 소유한다는 말은 역할이 오브젝트에 대한 OWNERSHIP 권한을 갖는다는 것이다. 이 권한을 가진 역할이 사용자에게 할당되면 사용자가 이제 오브젝트 공유를 제어할 수 있는거다. 

### b. 역할
역할은 보안 오브젝트에 대한 권한을 부여하거나 취소할 수 있는 개체다. 역할 유형의 범위는 다양하며 아래와 같이 분류된다.

- 계정 역할
- 데이터베이스 역할
- 인스턴스 역할
- 애플리케이션 역할
- 서비스 역할
- 시스템 정의 역할

분류된 역할에는 적절한 권한이 속해 있다. 이제 이 중에서도 사용자에게 할당되는 시스템 정의 역할에 대해 알아보자.
시스템 정의 역할은 아래와 같다.

![시스템 정의 역할](sources\tech-deep-dives\2025-07-16-snowflake-start\2.png)

- ORGADMIN : 조직 관리자 / GLOBALORGADMIN
- ACCOUNTADMIN : 계정 관리자. ACCOUNTADMIN은 가장 강력한 역할이므로 제한적으로 사용. 최소 인원 부여가 원칙이나 이슈 대응을 위해 2인에게는 부여하기.
- SECURITYADMIN : 보안 관리자
- USERADMIN : 사용자 및 역할 관리자
- SYSADMIN : 시스템 관리자
- Custom Role : 사용자 지정 역할
- PUBLIC : 자동 부여 역할...

### c. 권한 
Role 권한 부여에 대한 스크립트 예시다.
```sql
-- Default Role 설정
CREATE USER user1 PASSWORD='abc123' DEFAULT_ROLE = myrole ;
ALTER USER user1 SET DEFAULT_ROLE = myrole ;

-- Role 권한 부여
GRANT ROLE analyst TO USER user1 ;
GRANT ROLE engineer TO ROLE scientist ;

-- Role 전환 및 사용
USE ROLE scientist ;

-- Default Role 확인
SHOW USERS ;

-- Role 할당된 통계 
SHOW ROLES ;

-- 할당 받은 권한 
SHOW GRANTS TO USER user1 ;
SHOW GRANTS TO ROLE scientist ;
```

---

## 3. 가상 웨어하우스 [(참고)](https://docs.snowflake.com/ko/user-guide/warehouses)

웨어하우스는 리소스를 제공하는 computing layer에 있다. 쿼리 수행(DML 연산)시 활성화되고 사용하지 않으면 자동으로 중지될 수 있다. 동작할 때만 비용을 계산한다. 

웨어하우스는 크기별로 사이즈가 규정되어 있고 사이즈가 하나씩 커질수록 비용(크레딧)도 2배 가량 늘어나는데, 실행 시간을 초당 계산해서 부과하기 때문에 실제로 소비한 크레딧에 대해서만 청구한다. 참고로 웨어하우스 크기가 는다고 로딩 성능이 항상 향상되는 것은 아니고 로드되는 파일 수 및 크기에 더 많은 영향을 받는다.

```sql
-- 웨어하우스 선택
USE WAREHOUSE my_wh ;

-- 사용자 기본값 지정
ALTER USER sicentist SET DEFAULT_WAREHOUSE = 'my_wh' ;

-- 크기 변경 스케줄링
CREATE OR REPLACE TASK set_my_wh_to_large
 WAREHOUSE = my_wh
 SCHEDULE = 'USING CRON 0 18 * * * Asia/Seoul'
AS
 ALTER WAREHOUSE my_wh SET WAREHOUSE_SIZE = 'LARGE';
ALTER TASK set_my_wh_to_large RESUME;;
```

웨어하우스는 자동 중단 설정값 `AUTO_SUSPEND`이 구성되어 있다. 비용을 줄일 수 있으나 중단되면 캐시도 사라지기 때문에 이를 고려해야한다.

---

## 4. 가격 책정 모델 [(참고)](https://docs.snowflake.com/ko/guides-overview-cost)

Snowflake를 사용하는 총비용은 데이터 전송, 저장소, 컴퓨팅 리소스를 사용하는 비용의 합계이다.

### a. 컴퓨팅 리소스
- 가상 웨어하우스 컴퓨팅 (DML 작업 수행)
- 서버리스 컴퓨팅 : Snowflake 관리 컴퓨팅 리소스를 사용하는 검색 최적화 및 Snowpipe와 같은 Snowflake 기능
- 클라우드 서비스 컴퓨팅 : Snowflake 아키텍처의 클라우드 서비스 계층은 인증, 메타데이터 관리, 액세스 제어와 같은 백그라운드 작업을 수행

### b. 저장소 리소스
- 스테이징된 파일 
- Time Travel 데이터, Fail-safe, 복제본 등
- 압축이 적용되어 저장된 데이터 크기 기준으로 부과

### c. 데이터 전송 리소스
- 데이터 송신 요금만 청구 (수신요금 없음)
- 데이터 언로딩, 데이터 복제, 외부 네트워크 액세스, 외부 함수 쓰기, 클라우드 간 자동 복제

---

## 정리

오늘은 스노우플레이크의 전반적인 구조를 파악하고 세부 항목 중에서도 중요하다고 여겨지는 RBAC, 가상 웨어하우스와 가격 책정 모델 각각을 살펴봤다. 

스노우플레이크는 다른 데이터 웨어하우스 플랫폼(Google Bigquery, Amazon Redshift)과 유사하게 컴퓨팅 레이어와 스토리지 레이어를 별도로 두는 구조로 되어있다. 스토리지는 파티셔닝 되어 가상의 웨어하우스가 쿼리로 조회시 기존 파티션 별 메타데이터를 참조해 빠르게 쿼리할 수 있도록 구성되어 있다. 

이런 점들은 다른 플랫폼들과 유사하나 분명 다른 점은 이러한 클라우드 자원을 CSP 사에 의존하고 있다는 점이다. 

이 외에도 RBAC를 포함한 보안 모델과 계층화된 역할 구조. 조직 내에서 사용자, 팀, 서비스별로 필요한 만큼의 권한만 부여할 수 있다는 특징이 있다.

SnowPro Core 시험이나 실무 환경에서도 가장 많이 다루는 주제가 바로 이러한 권한 관리, 웨어하우스 설정, 비용 관리 부분이다. 
사실 어제 무턱대고 덤프만 읽다가 전체적인 흐름 파악이 부족해 문제에서 어떠한 부분을 캐치하도록 문제를 냈는지 파악이 안되어서 이렇게 내용을 한번 쭉 정리하고 덤프 공부를 시작해보려고 한다.

빠르게 SnowPro Core 취득하고 업무에 적극 활용할 수 있는 실력을 갖추고 싶다. 끝!