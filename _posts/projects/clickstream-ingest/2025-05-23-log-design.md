---
title: 웹 클릭스트림 수집하기 3) 수집 로그 구체화
description: 진짜 쓸모있는 로그 저장. JS 코드까지 적용하기
author: annmunju
date: 2025-05-23 15:07:00 +0900
categories: [Hands On, 웹 클릭 로그 수집]
tags: [data, log]
pin: false
math: true
mermaid: true
comments: true
---

> 뭘 쌓을 것인가 정하기

로그 수집을 시작할 때 구체적인 목적 없이 이벤트만 무작정 쌓다 보면 나중에 데이터를 어떻게 활용해야 할지 막막한 것 같다.  
이번 글에서는 **분석할 주제를 명확히 정하고** 그에 따라 꼭 필요한 클릭스트림 로그만 골라 수집하는 과정을 정리해보려고 한다.


## 이번 글 목표
1. **"블로그 유입 경로별 인기 게시글 분석"** 주제 확정
2. 수집할 로그 목록 정의  
3. 프론트엔드 코드로 로그 수집 구현

---

## 1. 확정된 주제 소개
블로그(혹은 웹페이지)를 운영하다 보면 어떤 외부 채널에서 어떤 게시글로 방문이 몰리는지 파악하는 것이 중요하다. 이 글에서는 **어떤 경로에서 어떤 게시글이 가장 많은 관심을 받았는지**를 명확하게 파악하기 위한 로그를 정의하고자 한다.

---

### 1.1 왜 이 분석이 필요한가?  
로그를 아무 목적 없이 무작정 쌓아두다 보면 나중에 데이터를 꺼내 분석할 때 도대체 무엇을 물어봐야 할지 막막해진다. 

처음에는 페이지뷰나 클릭 수 같은 단순 지표만 확인해도 충분해 보이지만 어느 순간에는 이 트래픽이 어디서 왔을지, 왜 어떤 게시글에만 반응이 몰리는 지 궁금해진다.

바로 이 지점을 짚어 분석목표를 **블로그 유입 경로별 인기 게시글 분석**이라는 명목으로 필요한 로그만 골라 수집하는 과정을 정리하려고 한다. 그래서 수집된 로그를 이후 활용까지 구체적으로 보여줄 수 있는 방법으로 정리해나갈 수 있을 것 같다!

> **핵심 주제**: **블로그 유입 경로별 인기 게시글 분석**  
> 외부 채널(referrer)별로 어떤 게시글이 얼마나 많은 방문을 기록했는지 파악할 수 있는 전반적인 로그를 수집해보자.
{: .prompt-tip}

---

## 2. 수집할 로그 목록

| 이벤트           | 내용                             | 필드                                                                 |
|------------------|-------------------------------|----------------------------------------------------------------------|
| `session_start`  | 사용자 세션 시작 시점 기록        | session_id, user_agent, referrer, timestamp                          |
| `referral_event` | 외부 채널(referrer/UTM) 정보 수집 | session_id, referrer, utm_source, utm_medium, utm_campaign, timestamp |
| `page_view`      | 페이지 진입 기록                  | page_url, referrer, session_id, timestamp                            |
| `time_on_page`   | 페이지 체류 시간 기록             | page_url, duration(ms), session_id, timestamp                        |
| `session_end`  | 사용자 세션 종료 시점 기록        | session_id, referrer, timestamp         |
| `scroll_event`   | 스크롤 깊이(%) 기록              | page_url, scroll_percentage, session_id, timestamp                   |
| `click_event`    | 클릭 발생 위치 및 대상 기록       | element_id, page_url, x_coord, y_coord, session_id, timestamp        |
| `navigation`     | 내부 링크(페이지 간 이동) 기록     | from_page, to_page, session_id, timestamp                            |
| `share_event`    | 공유 버튼 클릭 플랫폼 기록        | platform, page_url, session_id, timestamp                            |
| `comment_submit` | 댓글 제출 이벤트 기록            | post_id, session_id, timestamp                                       |
| `bounce_event`   | 비활성(바운스) 세션 기록          | page_url, session_id, timestamp                                      |

> **참고**:  
> - `referral_event`를 통해 첫 진입 시점의 UTM 파라미터나 `document.referrer` 값을 별도로 수집하면  
>   이후 `page_view`와 결합해 마케팅 캠페인의 효과를 더욱 정확히 분석할 수 있다다.  
> - 각 이벤트는 필요에 따라 추가 필드를 추가하거나 조정해 확장할 수 있다.  

---

## 3. 프론트엔드 로그 수집 코드 구현
위와 같이 적용한 로그 목록에 맞게 프론트엔드에 삽입할 자바스크립트 코드를 다음과 같이 작성했다. (코드는 GPT🤖의 도움을 받아 작성했다.)

---

### 3.1 `sendLog` 유틸리티 함수 작성  
로그 전송 기본 구조 및 UTM/Referrer 병합 로직이다. 가장 상단에는 ingest_url을 먼저 정의한다.

```javascript
  const LOG_ENDPOINT = "{{ ingest_url }}";

  // ———— 유틸리티: 로그 전송 함수 ————
  function sendLog(eventType, extra = {}) {
    const utm = JSON.parse(sessionStorage.getItem('utm') || '{}');
    const payload = {
      event: eventType,
      timestamp: new Date().toISOString(),
      path: window.location.pathname,
      referrer: document.referrer || null,
      ...utm,
      ...extra
    };
    // 언로드 시 세션 종료만 sendBeacon 사용
    if (eventType === 'session_end' && navigator.sendBeacon) {
      navigator.sendBeacon(LOG_ENDPOINT, JSON.stringify(payload));
    } else {
      fetch(LOG_ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        keepalive: true
      }).catch(err => console.error('Ingest error:', err));
    }
  }
```

---

### 3.2 외부 채널 & 세션 로그, 페이지 뷰  
- `referral_event` (utm_source/utm_medium/utm_campaign, referrer)  
- `session_start` (session_id, user_agent, timestamp)  
- `page_view` (page_url, session_id, timestamp)  

```javascript
  // ———— 1) UTM/Referrer 저장 & referral_event ————
  window.addEventListener('load', () => {
    // UTM 추출
    const params = new URLSearchParams(location.search);
    const utm = {
      utm_source: params.get('utm_source'),
      utm_medium: params.get('utm_medium'),
      utm_campaign: params.get('utm_campaign')
    };
    if (utm.utm_source) {
      sessionStorage.setItem('utm', JSON.stringify(utm));
      sendLog('referral_event', {});  
    }
    // 세션 시작 & 페이지뷰
    sendLog('session_start', { user_agent: navigator.userAgent });
    sendLog('page_view', {});
  });
```

---

### 3.3 체류 시간 & 세션 종료
- `time_on_page` (duration, session_id, timestamp)  
- `session_end` (session_id, timestamp)  

```javascript
  // ———— 2) 체류 시간 & 세션 종료 ————
  const __startTime = Date.now();
  window.addEventListener('beforeunload', () => {
    sendLog('time_on_page', { duration: Date.now() - __startTime });
    sendLog('session_end', {});
  });
```

---

### 3.4 스크롤 깊이 로깅  
- `scroll_event` (scroll_percentage, session_id, timestamp)  

```javascript
  // ———— 3) 스크롤 깊이 로깅 ————
  let __lastScroll = 0;
  window.addEventListener('scroll', () => {
    const now = Date.now();
    if (now - __lastScroll < 1000) return;
    __lastScroll = now;
    const pct = Math.round((window.scrollY / (document.body.scrollHeight - window.innerHeight)) * 100);
    sendLog('scroll_event', { scroll_percentage: pct });
  });
```

---

### 3.5 클릭 이벤트 로깅  
- `click_event` (element_id, x/y 좌표, session_id, timestamp)  

```javascript
  // ———— 4) 클릭 이벤트 로깅 ————
  document.addEventListener('click', e => {
    const tgt = e.target.closest('[data-log-click]') || e.target;
    sendLog('click_event', {
      tag: tgt.tagName,
      id: tgt.id || null,
      x: e.clientX,
      y: e.clientY
    });
  });
```

---

### 3.6 내부 내비게이션 로깅  
- `navigation` (from_page, to_page, session_id, timestamp)  

```javascript
  // ———— 5) 내부 내비게이션 ————
  document.querySelectorAll('a[href^="/"]').forEach(a => {
    a.addEventListener('click', () => {
      sendLog('navigation', {
        from: window.location.pathname,
        to: new URL(a.href).pathname
      });
    });
  });
```

---

### 3.7 인터랙션 로그  
- `share_event` (platform, session_id, timestamp)  
- `comment_submit` (post_id, session_id, timestamp)  
- `bounce_event` (session_id, timestamp)  

```javascript
  // ———— 6) 기타 인터랙션 ————
  // 공유 버튼
  document.querySelectorAll('[data-log-share]').forEach(btn => {
    btn.addEventListener('click', () => {
      sendLog('share_event', { platform: btn.dataset.platform || null });
    });
  });
  // 댓글 폼
  const commentForm = document.getElementById('comment-form');
  if (commentForm) {
    commentForm.addEventListener('submit', () => {
      sendLog('comment_submit', { post_id: commentForm.dataset.postId });
    });
  }
  // 바운스 정의: 5초 내 상호작용 없으면
  let __interacted = false;
  ['click','scroll','keydown'].forEach(evt => 
    document.addEventListener(evt, () => { __interacted = true; })
  );
  setTimeout(() => {
    if (!__interacted) sendLog('bounce_event', {});
  }, 5000);
```
목표에 필요한 로그를 각각 수집하는 코드를 위와 같이 작성했습니다.

---

## 결론 및 다음 단계

이번 글에서는 "**블로그 유입 경로별 인기 게시글 분석**"을 위한 클릭스트림 로그를 정의했다.
- **코드 작성**: UTM·referrer, 세션, 페이지뷰, 체류 시간, 스크롤, 클릭, 내비게이션, 공유·댓글·바운스까지 모든 핵심 이벤트를 수집하도록 Javascript 코드를 작성했다.
- **배포 완료**: 수집 스크립트는 `_includes/clickstream.html` 파일을 모든 페이지에서 인클루드하여 적용하였으며, 로컬·프로덕션 환경 분기까지 처리되었다  
    - 주요 변경사항은 [커밋](https://github.com/annmunju/annmunju.github.io/commit/06da10414f82269f7f5ba9b3439dff110b16a239)에서 확인할 수 있다.  

다음 글에서는 이제 이렇게 정의한 로그를 바탕으로 **AWS Lambda를 활용해 Kafka 프로듀싱**, **S3 배치 적재** 과정을 중심으로 단계별 코드 예제와 Terraform 설정을 공유할 예정이이다. 끝!

---

## 참고 자료

- [UTM 파라미터 가이드](https://ga-dev-tools.web.app/campaign-url-builder/)
- [Chirpy 테마 – Include 파일 사용법](https://chirpy.cotes.page/docs/includes/)