---
title: solvesql 문제 풀이
description: 문제 풀이 목록
author: annmunju
date: 2025-06-26 17:31:00 +0900
categories: [기술 공부 기록, DE]
tags: [sql]
pin: false
math: true
mermaid: false
comments: false
---

> solvesql 공개된 문제로 SQL 쿼리 연습하기

난이도 2, 난이도 3 문제 전체 푸는 것을 목표로 25~26일 진행. 문제 중 쉬운 문제 / 풀이 유사한 문제 제외하고 정리했다.

### 난이도 2

1. [언더스코어 포함되지 않은 데이터 찾기](https://solvesql.com/problems/data-without-underscore/)

```sql
select distinct page_location
from ga
where page_location not like "%\_%" escape "\"
order by page_location;
```

- 특수문자의 경우 이스케이프 문자 포함해서 찾고, escape 작성해주기

2. [게임 10개 이상 발매한 배급사 찾기](https://solvesql.com/problems/publisher-with-many-games/)

- 제출한 답 (직관성과 가독성 떨어짐짐)
```sql
select name
from (select publisher_id
    from games
    group by publisher_id
    HAVING count(game_id) >= 10) g
inner join companies c
on g.publisher_id = c.company_id;
```

- 개선한 답
```sql
select c.name
from games g
join companies c on g.publisher_id = c.company_id
group by c.name
having count(g.game_id) >= 10;
```

3. [기증품 비율 계산하기](https://solvesql.com/problems/ratio-of-gifts/)

```sql
select round((count(*) * 100.0 / a.a_cnt), 3)
from artworks as g join (select count(*) as a_cnt from artworks) as a
where credit like "%gift%";
```

- 정수 계산시 소수점 나타나지 않음 -> 실수 계산을 위해 100.0 곱셈 한 후 계산

4. [3년간 들어온 소장품 집계하기](https://solvesql.com/problems/summary-of-artworks-in-3-years/)

```sql
with year_artworks as (
  select substring(acquisition_date, 1, 4) as year, *
  from artworks
)
select 
  classification, 
  count(artwork_id) filter (where year = '2014') as "2014",
  count(artwork_id) filter (where year = '2015') as "2015",
  count(artwork_id) filter (where year = '2016') as "2016"
from year_artworks
group by classification
order by classification;
```

- 비슷한 다른 풀이

```sql
  count(case when year = '2014' then artwork_id end) as '2014',
  count(case when year = '2015' then artwork_id end) as '2015',
  count(case when year = '2016' then artwork_id end) as '2016'
```

- pivot 테이블 만들듯 컬럼에 해당 조건 넣어서 그에 맞는 열 생성

### 난이도 3

1. [복수 국적 메달 수상한 선수 찾기](https://solvesql.com/problems/multiple-medalist/)

```sql
with tmp as (select DISTINCT athlete_id, game_id, team_id, name
from records r 
  join teams t on r.team_id = t.id
  join games g on r.game_id = g.id
  join athletes a on r.athlete_id = a.id
where (year >= 2000) and (medal is not null))

select name
from tmp
group by athlete_id
having count(DISTINCT team_id) >= 2
order by name;
```

2. [배송 예정일 예측 성공과 실패](https://solvesql.com/problems/estimated-delivery-date/)

```sql
with tmp_tb as (
  select date(order_purchase_timestamp) as purchase_date, 
    order_id, 
    order_delivered_customer_date as delivered_date, 
    order_estimated_delivery_date as estimated_date
  from olist_orders_dataset
  where (order_purchase_timestamp BETWEEN '2017-01-01' and '2017-02-01') 
    and (order_delivered_customer_date and order_estimated_delivery_date is not null))

select purchase_date,
  count(order_id) filter (where delivered_date <= estimated_date) as success,
  count(order_id) filter (where delivered_date > estimated_date) as fail
from tmp_tb
group by purchase_date
order by purchase_date;
```

- 사실상 문제에서 요구사항만 잘 짚으면 쉬운 문제. 

3. [쇼핑몰의 일일 매출액과 ARPPU](https://solvesql.com/problems/daily-arppu/)

```sql
with tmp_tb as (select 
  date(order_purchase_timestamp) as dt,
  customer_id,
  sum(payment_value) as payment_sum
from olist_orders_dataset as od
  join olist_order_payments_dataset as opd
  on od.order_id = opd.order_id
where order_purchase_timestamp >= '2018-01-01'
group by dt, customer_id)

select dt, 
  count(customer_id) as pu, 
  round(sum(payment_sum), 2) as revenue_daily,
  round(sum(payment_sum)/count(customer_id), 2) as arppu
from tmp_tb
group by dt
order by dt;
```

- order_purchase_timestamp 필터링을 where절로 쓰냐 having절로 쓰냐
  - 언제 동작하냐의 차이. group by 이후 동작 having, 이전 동작 where.
  - 본 문제의 경우에는 행 필터링이니까 where 사용하는 것이 유리.

4. [멘토링 짝꿍 리스트](https://solvesql.com/problems/mentor-mentee-list/)

- 제출 쿼리
```sql
select mentee_id, mentee_name, mentor_id, mentor_name
from (select employee_id as mentee_id, name as mentee_name, department as mentee_department
  from employees
  where join_date between '2021-10-01' and '2021-12-31') mentee_tb
left join (select employee_id as mentor_id, name as mentor_name, department as mentor_department
  from employees
  where join_date <= '2019-12-31') mentor_tb
where mentee_department != mentor_department
order by mentee_id, mentor_id;
```

- 개선 쿼리
```sql
select mentee_id, mentee_name, mentor_id, mentor_name
from (
  select employee_id as mentee_id, name as mentee_name, department as mentee_department
  from employees
  where join_date between '2021-10-01' and '2021-12-31'
) mentee_tb
left join (
  select employee_id as mentor_id, name as mentor_name, department as mentor_department
  from employees
  where join_date <= '2019-12-31'
) mentor_tb
on mentee_tb.mentee_department != mentor_tb.mentor_department
order by mentee_id, mentor_id;
```
  - 변경된 내용: where절로 작성하면 멘토가 없는 멘티 결과는 누락됨. join ... on 조인 조건으로 작성하면 멘토가 없는 경우도 유지됨.

5. [작품이 없는 작가 찾기](https://solvesql.com/problems/artists-without-artworks/)

- 제출 쿼리

```sql
with pick_tb as (
  select *
  from artists
  left join artworks_artists
    on (artists.artist_id = artworks_artists.artist_id) 
  where death_year is not null)

select artist_id, name
from pick_tb
where artwork_id is null
order by artist_id;
```

- 대안 (가독성 높이기)

```sql
select a.artist_id, a.name
from artists a
left join artworks_artists aa
  on a.artist_id = aa.artist_id
where (a.death_year is not null) and (aa.artwork_id is null)
order by a.artist_id;
```

6. [온라인 쇼핑몰의 월 별 매출액 집계](https://solvesql.com/problems/shoppingmall-monthly-summary/)

```sql
with tmp_tb as (
  select substring(order_date, 1, 7) as order_month, o.order_id, price*quantity as total_price
  from orders o
  join order_items oi
    on o.order_id = oi.order_id)

select order_month, 
  sum(total_price) filter (where order_id not like 'C%') as ordered_amount,
  sum(total_price) filter (where order_id like 'C%') as canceled_amount,
  sum(total_price) as total_amount
from tmp_tb
group by order_month
order by order_month;
```

7. [게임 평점 예측하기 1](https://solvesql.com/problems/predict-game-scores-1/)

```sql
with genre_tb as (select genre_id, 
  round(avg(critic_score), 3) as critic_score,
  ceil(avg(critic_count)) as critic_count,
  round(avg(user_score), 3) as user_score,
  ceil(avg(user_count)) as user_count
from games
group by genre_id)

select a.game_id, a.name,
  case WHEN a.critic_score is null THEN e.critic_score
    else a.critic_score end as critic_score,
  case WHEN a.critic_count is null THEN e.critic_count
    else a.critic_count end as critic_count,
  case WHEN a.user_score is null THEN e.user_score
    else a.user_score end as user_score,
  case WHEN a.user_count is null THEN e.user_count
    else a.user_count end as user_count
from games a
join genre_tb e
  on a.genre_id = e.genre_id
where (a.year >= '2015') and ((a.critic_score is null) or (a.critic_count is null)
  or (a.user_score is null) or (a.user_count is null));
```

- 올림 하라는 요구사항을 제대로 못보고 round로 반올림 처리해서 처음에 오답나옴. 이후 수정 (ceil : 올림, trunc : 버림)

8. [서울숲 요일별 대기오염도 계산하기](https://solvesql.com/problems/weekday-stats-airpollution/)

```sql
select 
  case STRFTIME('%u', measured_at)
    when '1' then '월요일'
    when '2' then '화요일'
    when '3' then '수요일'
    when '4' then '목요일'
    when '5' then '금요일'
    when '6' then '토요일'
    when '7' then '일요일' end
  as weekday, 
  round(avg(no2), 4) as no2, 
  round(avg(o3), 4) as o3, 
  round(avg(co), 4) as co, 
  round(avg(so2), 4) as so2, 
  round(avg(pm10), 4) as pm10, 
  round(avg(pm2_5), 4) as pm2_5
from measurements
group by STRFTIME('%u', measured_at)
order by STRFTIME('%u', measured_at);
```

- STRFTIME : 요일로 변환해주는 함수. 첫번째 인자에 '%u' 작성하면 월~일요일을 1~7 번호로 할당해줌.
- 처음에 case when (조건식) then (값) ... 이렇게 적었는데 조건이 계속 중복됨 -> case (조건) when (조건에 해당하는 값) then (값)으로 수정하니 중복 줄어듦.


우선 오늘은 여기까지. 조금 더 어려운 문제로 난이도 3~4 풀이 이어하기.