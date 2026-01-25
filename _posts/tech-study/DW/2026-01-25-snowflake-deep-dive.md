---
title: Snowflake 사용 실험
description: Insert 로 데이터 추가하기 vs Copy 로 데이터 추가하기
author: annmunju
date: 2026-01-25 15:20:10 +0900
categories: [기술 공부 기록, DW]
tags: [snowflake, dw]
pin: false
math: true
mermaid: false
comments: false
---

업무를 진행하며 데이터 웨어하우스에 로그를 효율적으로 적재하는 방법에 대해 고민하게 되었다.  
이에 Snowflake 환경에서 2분 주기로 데이터를 배치 적재할 때 batch INSERT 방식과 PUT + COPY INTO 방식을 각각 적용해보며, 로그와 메트릭 데이터를 적재하는 데 어떤 방식이 성능과 비용 측면에서 더 적합한지 직접 실험을 진행해보았다.

---

### 실험 목표

동일 데이터량을 **2분 배치 단위**로 적재하는 두 가지 방식을 비교하고자 했다.
- **A안:** batch INSERT
- **B안:** PUT to Stage + COPY INTO

### 측정 항목

- **총 소요 시간** : 동일 데이터량 대비 처리 지연 및 파이프라인 병목 가능성 판단
- **쿼리 수 / 쿼리 시간** : DML 부하 증가 여부 및 Snowflake 내부 실행 패턴 비교
- **웨어하우스 사용량** : 장시간 실행으로 인한 간접적 비용 증가 가능성 확인 (INFORMATION_SCHEMA.QUERY_HISTORY 기반)

### 실험 환경 구성

실험용 DB, 스키마, 테이블을 다음과 같이 생성했다.

```sql
-- 1) 실험용 warehouse 
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;

-- 2) 실험용 DB/스키마
CREATE OR REPLACE DATABASE OBS_EXP_DB;
CREATE OR REPLACE SCHEMA OBS_EXP_DB.PUBLIC;

-- 3) 메트릭 테이블
CREATE OR REPLACE TABLE METRICS_INSERT (
  window_start TIMESTAMP_NTZ,
  window_end   TIMESTAMP_NTZ,
  source       STRING,
  metric_name  STRING,
  value        DOUBLE,
  labels       VARIANT
);

CREATE OR REPLACE TABLE METRICS_COPY LIKE METRICS_INSERT;

-- 4) 로그 테이블
CREATE OR REPLACE TABLE LOGS_INSERT (
  window_start TIMESTAMP_NTZ,
  window_end   TIMESTAMP_NTZ,
  source       STRING,
  service      STRING,
  level        STRING,
  message      STRING,
  payload      VARIANT
);

CREATE OR REPLACE TABLE LOGS_COPY LIKE LOGS_INSERT;

-- 5) 내부 스테이지 + 파일포맷
CREATE OR REPLACE STAGE OBS_EXP_STAGE;

CREATE OR REPLACE FILE FORMAT FF_METRICS_CSV
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"';

CREATE OR REPLACE FILE FORMAT FF_LOGS_JSON
  TYPE = JSON;
```

### 실험 조건

- 동일 Warehouse / 스키마 / 테이블 구조 사용
- 2분 Window 단위 데이터 생성
- 로그 데이터 스케일: 1,000 / 5,000 / 10,000 / 20,000 / 50,000 rows per 2분

---

### 결과 비교

#### 전체 결과 요약

- 동일한 조건(2분 배치, 동일 row 수, 동일 warehouse)에서 두 방식의 처리 시간을 비교했다.
- 소량 로그 구간에서는 INSERT 방식의 처리 시간이 더 짧게 측정되었다.
- 로그량이 증가할수록 COPY 방식의 상대적 처리 시간이 짧게 측정되었다.
- 비용은 웨어하우스 활성 시간과 클라우드 서비스 사용량이 합산되어 집계되며, 해당 실험에서는 INSERT 구간의 총 크레딧이 COPY 구간보다 크게 측정되었다.

#### 실험 소요 시간

| **METHOD** | **START_TIME (UTC)** | **END_TIME (UTC)** | **실험 소요 시간** |
| --- | --- | --- | --- |
| **INSERT** | 2026-01-08 13:23:44 | 2026-01-08 13:32:11 | 약 **8분 27초** |
| **COPY** | 2026-01-08 14:02:02 | 2026-01-08 14:05:57 | 약 **3분 55초** |

#### 로그량별 처리 시간 비교 (2분 배치 기준)

| **로그 rows / 2분** | **INSERT 총 소요 시간(초)** | **COPY 총 소요 시간(초)** | **INSERT / COPY** |
| --- | --- | --- | --- |
| 1,000 | 11.9 | 17.4 | 0.68 |
| 5,000 | 25.7 | 19.9 | 1.29 |
| 10,000 | 43.6 | 21.8 | 2.00 |
| 20,000 | 83.3 | 27.6 | 3.02 |
| 50,000 | 250.9 | 42.4 | 5.92 |

#### 비용 비교

`SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY`에서 실험 구간동안 소요된 비용을 확인했다. (WAREHOUSE_METERING_HISTORY는 1시간 단위 집계만 제공하기 때문에 다른 시간대로 분리하여 실험)

| **METHOD** | **WAREHOUSE_NAME** | **CREDITS_USED_TOTAL** | **CREDITS_USED_CLOUD_SERVICES** |
| --- | --- | --- | --- |
| **INSERT** | SNOWFLAKE_LEARNING_WH | 0.778 | 0.109 |
| **COPY** | SNOWFLAKE_LEARNING_WH | 0.723 | 0.017 |

---

### 결론

실험 결과, 2분 배치 기준 로그량이 **대부분 5,000 rows 미만으로 유지되는 경우**에는 batch INSERT 방식이 처리 시간과 운영 복잡도 측면에서 충분히 효율적이었다.  

반면 **일상적으로 로그가 5,000 rows 이상인 구간**에서는 INSERT의 처리 시간이 급격히 증가했으며, 이 경우 대량 적재에 최적화된 COPY INTO 방식이 더 안정적인 성능과 비용 특성을 보였다.

→ 따라서 **발생하는 로그량 수준**을 확인하고, 로그량이 많아지는 경우 INSERT에서 COPY 방식으로 전환하는 것이 합리적이다.

### 배운 것

#### Snowflake의 과금 체계

Snowflake는 크게 두 가지 방식으로 과금된다.

1. **컴퓨트 크레딧** : 웨어하우스가 실행 중인 시간 X 웨어하우스 크기
2. **Cloud Services 크레딧** : 메타데이터/파일 처리 등 일부 작업

비용 차이가 발생하는 이유는 다음과 같다.
- INSERT는 매번 트랜잭션 시작/종료, 테이블 메타데이터 갱신, 마이크로 파티션 관리, 통계/카탈로그 업데이트가 발생한다.
- COPY는 파일 여러 개를 한 번의 로드 작업으로 처리하고, 마이크로 파티션 생성도 bulk 단위로 수행되며, 메타데이터 반영도 상대적으로 한 번에 이루어진다.

즉, Cloud Services 비용은 파일 I/O보다 **트랜잭션 및 메타데이터 관리 횟수**에 더 크게 영향을 받으며, 고빈도 batch INSERT는 이 비용이 누적되어 COPY보다 크게 측정될 수 있다.

#### PURGE 옵션

PUT을 통해 스테이지에 올린 파일이 성공적으로 COPY 되면 즉시 삭제하는 옵션이 있다.

```sql
COPY INTO table_name
FROM @stage_name
PURGE = TRUE
```

---

이 글에서는 Snowflake에서 로그/메트릭 데이터를 2분 배치로 적재할 때 batch INSERT와 PUT + COPY INTO 방식을 직접 비교 실험한 결과를 정리했다.

요점은 다음과 같다.
- **소량 데이터(5,000 rows 미만)** : batch INSERT가 처리 시간 및 운영 복잡도 면에서 유리
- **대량 데이터(5,000 rows 이상)** : COPY INTO가 성능 및 비용 면에서 유리
- Snowflake의 비용 구조상 **고빈도 INSERT는 Cloud Services 비용이 누적**될 수 있음

실제 운영 환경에서는 로그량 추이를 모니터링하고, 임계치를 넘으면 COPY 방식으로 전환하는 전략을 고려해볼 수 있겠다. 끝!


ps. 관련 소스코드는 [github TIL](https://github.com/annmunju/annmunju/tree/main/TIL/2026/snowflake_test)에 정리해두었다. 