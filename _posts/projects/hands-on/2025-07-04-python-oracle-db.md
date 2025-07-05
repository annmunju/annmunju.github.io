---
title: Oracle database 사용기
description: 유저 생성 및 파이썬 패키지 oracledb 조작
author: annmunju
date: 2025-07-04 20:45:00 +0900
categories: [Hands On, DB]
tags: [Oracle, DB]
pin: false
math: true
mermaid: true
comments: true
---

생성한 오라클 데이터베이스에서 사용할 PDB 컨테이너에 접속해 유저를 만들고 해당 유저를 기반으로 파이썬 oracle 연결 패키지를 활용해 DML 명령을 실행시켜보려고 한다.

## 진행 내용

1. 접속 및 사용자 생성
2. 테이블 생성 및 가비지 데이터 삽입
3. 다양한 쿼리문 실행

---

### 1. 접속 및 사용자 생성

오라클 데이터베이스가 설치되어있는 VM에 ssh로 접속해 진행한다.

```bash
sqlplus / as sysdba

> startup;
```

DB 정상 실행부터 확인하고 순차적으로 진행한다.

```sql
-- 현재 접속한 컨테이너 확인
SELECT SYS_CONTEXT('USERENV','CON_NAME') FROM DUAL;

-- 전체 PDB 목록 보기
SHOW PDBS;
```

이렇게 진행하면 현재 컨테이너는 ORCLCDB 일 것이고 (지난번 생성한 CDB 이름), 
만들어둔 ORCLPDB1 목록이 나타날 것이다.

PDB에서 사용할 사용자 생성하고 접속해보자.

```sql
-- 컨테이너 변경 (PDB)
ALTER SESSION SET CONTAINER=ORCLPDB1;

-- 사용자 생성
CREATE USER mjahn IDENTIFIED BY [비밀번호];
GRANT CONNECT, RESOURCE TO mjahn;

exit;
```
- `RESOURCE` role에 포함된 권한들

| 권한 | 설명 |
| --- | --- |
| CREATE TABLE | 테이블 생성 |
| CREATE SEQUENCE | 시퀀스 생성 |
| CREATE PROCEDURE | 프로시저 생성 |
| CREATE TRIGGER | 트리거 생성 |
| CREATE TYPE | 사용자 정의 타입 생성 등 |

```bash
# PDB 접속
sqlplus mjahn/[비밀번호]@[IP주소]:1521/ORCLPDB1
```

- 여기서 이 유저로 테이블을 생성해주려고 했는데 `ORA-01950: 테이블스페이스 'USERS'에 대한 권한이 없습니다.` 라는 권한 오류가 발생한다.
    - 이를 해결하기 위해 사용자 계정으로 로그인 한 뒤 `GRANT UNLIMITED TABLESPACE TO mjahn;` 해서 테이블스페이스 제한을 없애줬다.

---

### 2. 테이블 생성 및 가비지 데이터 삽입

아래 조건들을 위해서 OracleDBClient 클래스를 작성했다.

a. db connect - close 를 쿼리 실행시 매번 실행해야 함.
b. 테이블 생성시 존재 유무를 판별하고 없을 때 생성 (없을 때 생성) 
c. 테이블 사용시 존재 유무를 판별하고 있을 때 사용 (있을 때 조회/삭제 등)

그리고 마지막으로 테이블 생성 & 가비지 데이터 삽입을 실행하는 함수를 작성했다.

#### a. db connect - close를 쿼리 실행시 매번 실행해야 함.

- 구현 위치: OracleDBClient 클래스 전체 (__enter__, __exit__)

```python
class OracleDBClient:
    def __init__(self, user=DB_USER, password=DB_PASSWORD, dsn=DB_DSN):
        self.user = user
        self.password = password
        self.dsn = dsn
        self.connection = None

    def __enter__(self):
        try:
            self.connection = oracledb.connect(
                user=self.user, password=self.password, dsn=self.dsn
            )
            return self
        except Exception as e:
            logging.error(f"DB 연결 오류: {e}")
            sys.exit(1)

    def __exit__(self, exc_type, exc_value, traceback):
        if self.connection:
            self.connection.close()
```

- with OracleDBClient() as db: 구문을 사용함으로써 접속과 종료를 자동으로 관리
- `__enter__`에서 연결 생성, `__exit__`에서 연결 종료
- 예외 발생 여부와 관계없이 안전하게 리소스 정리됨

#### b. 테이블 생성 시 존재 유무를 판별하고 없을 때 생성

- 구현 위치: create_table, create_sequence, execute_if_absent 메서드

```python
def execute_dml(self, sql, params=None):
    with self.connection.cursor() as cursor:
        try:
            cursor.execute(sql, params or {})
        except Exception as e:
            logging.error(f"DML 오류: {e}")
            self.connection.rollback()
            raise
        else:
            self.connection.commit()

def execute_if_absent(self, check_sql, action_sql, action_desc):
    exists = self.select_query(check_sql)
    if not exists:
        logging.debug(f"{action_desc} 조건 충족 → 실행")
        self.execute_dml(action_sql)
    else:
        logging.debug(f"{action_desc} 조건 불충족 → 스킵")

def create_table(self, table_name, columns_str):
    check_sql = f"SELECT 1 FROM user_tables WHERE table_name = '{table_name.upper()}'"
    create_sql = f"CREATE TABLE {table_name} ({columns_str})"
    self.execute_if_absent(check_sql, create_sql, f"테이블 {table_name} 생성")
```

- create_table 함수가 동작하기 위해서 execute_if_absent(존재하지 않으면 실행)으로 판단한 뒤 execute_dml로 dml이 실행됨.

#### c. 테이블 사용시 존재 유무를 판별하고 있을 때 사용
```python
def select_query(self, query, params=None):
    with self.connection.cursor() as cursor:
        cursor.execute(query, params or {})
        return cursor.fetchall()

def drop_table(self, table_name):
    check_sql = f"SELECT 1 FROM user_tables WHERE table_name = '{table_name.upper()}'"
    drop_sql = f"DROP TABLE {table_name} PURGE"
    if self.select_query(check_sql):
        self.execute_dml(drop_sql)
```

- 존재 유무 체크 후 조건부로 drop 실행

#### d. 테이블 생성 및 가비지 데이터 삽입

- 테이블 이름 : sample_table

| 컬럼명 | 타입 | 조건 |
| --- | --- | --- |
| id | sequence |  |
| title | text |  |
| current_date | systimestamp |  |
| stand_date | timestamp | 현재시간-n분 |
| num_a | number | 0+n |
| num_b | number | 10만 1 -n |

```python
def create_sample_table():
    columns = '''
        id NUMBER PRIMARY KEY,
        title VARCHAR2(4000),
        current_date TIMESTAMP DEFAULT SYSTIMESTAMP,
        stand_date TIMESTAMP,
        num_a NUMBER,
        num_b NUMBER
    '''
    with OracleDBClient() as db:
        db.create_table("sample_table", columns)
        db.create_sequence("sample_table_seq")

```

- create_sequence는 table과 거의 유사한 방식으로 존재 유무를 확인하고 없으면 만들어지도록 코드 작성했다.


```python
    def execute_many(self, sql, data):
        with self.connection.cursor() as cursor:
            try:
                cursor.executemany(sql, data)
            except Exception as e:
                logging.error(f"여러건 실행 오류: {e}")
                self.connection.rollback()
                raise
            else:
                self.connection.commit()
...

def insert_garbage_data(n=100000, batch_size=1000):
    now = datetime.datetime.now()
    sql = """
        INSERT INTO sample_table (id, title, current_date, stand_date, num_a, num_b)
        VALUES (sample_table_seq.NEXTVAL, :title, SYSDATE, :stand_date, :num_a, :num_b)
    """
    with OracleDBClient() as db:
        data = []
        for i in range(1, n + 1):
            data.append({
                "title": f"가비지 데이터 {i}",
                "stand_date": now - datetime.timedelta(minutes=i),
                "num_a": i,
                "num_b": n + 1 - i
            })
            if i % batch_size == 0 or i == n:
                db.execute_many(sql, data)
                data = []
```

- 대량의 데이터 삽입을 위해서 executemany 함수 사용
- `sample_table_seq.NEXTVAL` 로 미리 구현한 시퀀스를 활용해 일관되게 ID를 생성했다.

---

### 3. 다양한 쿼리문 실행

해당 테이블을 이용해 다양한 방식으로 쿼리를 작성해 실행하는 예제를 풀어보려고 한다.

#### a. `sample_table` 테이블에서 `stand_date`가 현재 시간 기준으로 1개월 이전보다 이후인 데이터를 조회해서 이 데이터를 `temp1`이라는 테이블에 **복사(insert)**하기

```python
    def replicate_table(self, origin_table, replica_table):
        sql = f"""
            BEGIN
                EXECUTE IMMEDIATE '
                    CREATE TABLE {replica_table} AS
                    SELECT * FROM {origin_table} WHERE 1=0';
            EXCEPTION
                WHEN OTHERS THEN IF SQLCODE != -955 THEN RAISE; END IF;
            END;
        """
        self.execute_dml(sql)
...

def insert_recent_data_to_temp1():
    sql = """
        INSERT INTO temp1 (id, title, current_date, stand_date, num_a, num_b)
        SELECT id, title, current_date, stand_date, num_a, num_b
        FROM sample_table
        WHERE stand_date > ADD_MONTHS(SYSTIMESTAMP, -1)
    """
    with OracleDBClient() as db:
        db.replicate_table("sample_table", "temp1")
        db.execute_dml(sql)
```

#### b. `sample_table`에서 `temp1` 테이블에 존재하는 id들에 대해 해당 행의 `title` 컬럼 값을 '업데이트 된 데이터'로 **변경(update)**하기

```python
def update_temp1_title():
    sql = """
        UPDATE sample_table
        SET title = '업데이트 된 데이터'
        WHERE id IN (SELECT id FROM temp1)
    """
    with OracleDBClient() as db:
        db.execute_dml(sql)
```

#### c. `sample_table` 테이블의 데이터를 그대로 읽되, 그 중 `num_b` 컬럼의 값을 19로 나눈 나머지 값으로 변환해서 `temp2` 테이블에 **삽입(INSERT)** 하기.

```python
def insert_remainder_19_to_temp2():
    sql = """
        INSERT INTO temp2 (id, title, current_date, stand_date, num_a, num_b)
        SELECT id, title, current_date, stand_date, num_a, MOD(num_b, 19)
        FROM sample_table
    """
    with OracleDBClient() as db:
        db.replicate_table("sample_table", "temp2")
        db.execute_dml(sql)
```

#### d. `temp2` 테이블에서 `num_b` 값을 기준으로 그룹핑(Group by)한 뒤, 각 그룹에서 `num_a` 값이 가장 큰(최신) 1개의 행만 추출해서 이를 `temp3` 테이블에 저장

```python
def insert_recent_temp2_data_to_temp3():
    sql = """
        INSERT INTO temp3 (id, title, current_date, stand_date, num_a, num_b)
        SELECT id, title, current_date, stand_date, num_a, num_b
        FROM (
            SELECT a.*, ROW_NUMBER() OVER (PARTITION BY num_b ORDER BY num_a DESC) as rn
            FROM temp2 a
        )
        WHERE rn = 1
    """
    with OracleDBClient() as db:
        db.replicate_table("sample_table", "temp3")
        db.execute_dml(sql)
```

#### e. `sample_table`에서 `stand_date` 컬럼이 현재 날짜 기준 1개월 전과 같은 달인 데이터를 필터링 -> 필터링된 데이터 중에서 그 달(2025-06)에 해당하는 마지막 생성 날짜(`current_date`)를 기준으로 정렬하고 상위 10건만 추출

```python
def select_last_month_top10_rows():
    sql = """
        SELECT *
        FROM (
            SELECT *
            FROM sample_table
            WHERE TRUNC(stand_date, 'MM') = ADD_MONTHS(TRUNC(SYSDATE, 'MM'), -1)
            ORDER BY current_date DESC
        )
        WHERE ROWNUM <= 10
    """
    with OracleDBClient() as db:
        return db.select_query(sql)
```

---

## 결론

