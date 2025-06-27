---
title: 웹 클릭스트림 수집하기 1) 판 벌리기
description: 카프카랑 하둡 써서 할만한 프로젝트 계획하기
author: annmunju
date: 2025-05-21 10:52:00 +0900
categories: [웹 클릭 로그 수집, 환경 구성 실습]
tags: [data, log, ingest]
pin: false
math: true
mermaid: true
comments: true
---

> 카프카 혼자 실습하기

혼자 실습하는데 무리가 없을 정도의 수준으로 프로젝트 단위를 **실시간 웹 클릭스트림 로그 수집·저장·배치분석 파이프라인**으로 정해 웹 로그를 실시간으로 쌓는 과정을 정리해보려고 한다.

## 실습 목표

- 개인 블로그를 통해 **클릭스트림 로그 데이터 생성**
- 해당 클릭 로그를 **Kafka에 실시간 전달**
- Kafka Connect HDFS 커넥터를 이용해 토픽에 쌓인 메시지를 일정 주기(ex. 5분)로 **파일로 저장**

## 사전 준비

1. [개인 블로그 먼저 준비](#1-%EA%B0%9C%EC%9D%B8-%EB%B8%94%EB%A1%9C%EA%B7%B8-%EB%A7%8C%EB%93%A4%EA%B8%B0): github.io 블로그
2. [클릭 로그 받아줄 Ingest 서버 띄우기](#2-ingest-%EC%84%9C%EB%B2%84-%EB%A7%8C%EB%93%A4%EA%B8%B0)
3. [github pages 프론트에 JS 스니펫 심기](#3-%ED%94%84%EB%A1%A0%ED%8A%B8%EC%97%90-js-%EC%8A%A4%EB%8B%88%ED%8E%AB-%EC%8B%AC%EA%B8%B0)

### 1. 개인 블로그 만들기

Jekyll 오픈소스 테마 chirpy를 포크해서 내 깃허브 페이지에 `annmunju.github.io` 레포지토리에 pages를 띄우는 과정 

#### 1.0 Jekyll 설치
M1 맥북을 사용하고 있어서 다음 게시글을 참고해 설치했다.
- [M1 mac - Jekyll blog 환경 세팅하기](https://danaing.github.io/etc/2022/03/14/M1-mac-jekyll-setting.html)

#### 1.1 Jekyll 테마 포크
[chirpy-starter 레포](https://github.com/cotes2020/chirpy-starter)에서 템플릿을 가져와 내 새로운 레포를 만든다.
![템플릿 레포 만들기](sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/01.png)

#### 1.2 로컬 클론 및 _config.yml 수정
```bash
git clone git@github.com:annmunju/annmunju.github.io.git
cd annmunju.github.io
```
위와 같이 경로 이동 후 _config.yml 파일에 필요한 정보를 넣어준다.
- url 추가 (깃허브 경로)
- 언어 변경: _data/locales에 ko-KR.yml 파일 추가, _config.yml 파일에 lang을 ko-KR로 수정
- timezone을 Asia/Seoul로 반영
- title, tagline, description 추가
- 트위터 삭제, github 추가, email과 링크 경로 수정
- 프리뷰 아바타 이미지 추가 (social_preview_image)
- 댓글 기능 추가 (disqus 계정 생성)
```yml
comments:
    provider: disqus 
    disqus:
        shortname: annmunju-github-blog 
```

#### 1.3 github pages 설정
chirpy-starter는 chripy라는 테마에서 가장 기본적인 사항만 적용된 버전. [github actions 메니페스토 파일](https://github.com/cotes2020/chirpy-starter/blob/main/.github/workflows/pages-deploy.yml)이 작성되어 있어 github에 push하면 **자동으로 배포(CD)할 수 있게 이미 설정**되어 있다다.

이를 적용하기 위해 github 레포 설정에 다음과 같이 **배포 소스를 github actions로 설정**해준다.
![github pages 설정](sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/02.png)

그럼 **자동으로** main 혹은 master 브랜치로 push할 때 페이지가 **배포** 되는 것을 확인할 수 있다. 
![github actions](sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/03.png)

### 2. Ingest 서버 만들기

다음은 Ingest 서버 역할을 할 **lambda를 생성**. 우선은 kafka를 사용하지 않고 단순하게 클릭스트림을 처리하도록 구성한다다.

처음에는 콘솔로 작업하고 이후에 구체적인 인프라 환경을 정의한 후 Terraform을 이용해 IaC로 관리할 계획

#### 2.1 IAM 역할
람다는 CloudWatch Logs 작성 권한이 필요하기 때문에 **필요한 권한을 추가한 역할을 생성**
<div style="display: flex; justify-content: center; gap: 2%;">
  <img src="sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/04.png" alt="역할 생성 1단계">
  <img src="sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/05.png" alt="역할 생성 2단계">
</div>

#### 2.2 Lambda 함수
함수를 생성
![github actions](sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/06.png)
함수의 내용은 다음과 같이 구성했다.
```python
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    # API Gateway HTTP API를 사용하여 event['body']에 페이로드가 들어옵니다.
    try:
        payload = json.loads(event.get('body', '{}'))
    except json.JSONDecodeError:
        payload = {"raw": event.get('body')}
    logger.info(f"Received click event: {payload}")
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"status": "ok", "received": payload})
    }
```

#### 2.3 API Gateway HTTP API 생성
이번엔 **람다로 접근하기 위한 API 게이트웨이를 생성**한다. 콘솔에서 API Gateway 검색 후 HTTP API로 api를 생성
자동 배포($default)를 적용해 람다가 수정되면 즉시 반영되도록 했다.
<div style="display: flex; justify-content: center; gap: 2%;">
  <img src="sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/07.png" alt="http api 생성">
  <img src="sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/08.png" alt="검토 및 생성">
</div>

브라우저로 다른 도메인(프론트엔드)에서 API Gateway로 직접 요청할 때 보안 정책(CORS)에 의해 차단되지 않도록 허용 설정이 필요하다. **CORS 설정**은 아래와 같이 진행했다.
![CORS](sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/09.png)

#### 2.4 curl 테스트
```bash
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{"path":"/test","tag":"A","id":null,"timestamp":"2025-05-21T12:00:00Z"}' \
   https://{주소}.execute-api.ap-northeast-2.amazonaws.com/ingest
```
Invoke URL로 테스트해본 결과 정상 응답이 출력되는 것을 확인할 수 있었다.
```
# result
{"status": "ok", "received": {"path": "/test", "tag": "A", "id": null, "timestamp": "2025-05-21T12:00:00Z"}}
```

### 3. 프론트에 JS 스니펫 심기

지킬 테마를 사용하기 위해서 올린 정적 웹사이트에 JS 코드를 사용하려면 우선 직접 **자바스크립트 코드를 _includes/ 폴더에 작성**해야한다.

#### 3.1 _includes/clickstream.html 스니펫 파일 작성
```html
<!-- _includes/clickstream.html -->
{% raw %}
{% if jekyll.environment == "production" %}
  {% assign ingest_url = "INGEST_API_GATEWAY_URL" %}
{% else %}
  {% assign ingest_url = "http://localhost:8000/ingest" %}
{% endif %}
{% endraw %}
<script>
  document.addEventListener('click', event => {
    const payload = {
      path: window.location.pathname,
      tag: event.target.tagName,
      id: event.target.id || null,
      timestamp: new Date().toISOString()
    };
    fetch("{{ ingest_url }}", {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload)
    })
    .catch(err => console.error('Ingest error:', err));
  });
</script>
```
- "**INGEST_API_GATEWAY_URL**"는 github actions을 통해 secretes로 입력된 값으로 **수정되도록 반영하기 위한 초기 값**이다.
- 개발 환경인 로컬에서 작업할 때는 **fastapi**로 작성한 코드로 테스트
- 어떤 요소가 클릭되었는지 추적하기 위해 **e.target** 정보를 사용

#### 3.2 레이아웃에 스니펫 인클루드
**_layouts/home.html에 `{% raw %}{% include clickstream.html %}{% endraw %}`를 추가!** 기존 chirpy-starter는 해당 파일이 없고 자동으로 gemfile 가져오니 [jekyll-theme-chirpy에 home.html](https://github.com/cotes2020/jekyll-theme-chirpy/blob/master/_layouts/home.html) 파일을 가져와서 해당 코드 하단에 추가-적용했다. 
```html
...
</div>
<!-- #post-list -->
{% raw %}
{% include clickstream.html %}

{% if paginator.total_pages > 1 %}
  {% include post-paginator.html %}
{% endif %}
{% endraw %}
```

#### 3.3 github actions에 Secrets 추가
_includes/clickstream.html 스니펫 파일에 적용된 "**INGEST_API_GATEWAY_URL**"는 github actions 수행시에 **수정될 수 있게** 실제 값을 변수(secrets)로 추가했다.
![github actions secrets 추가](sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/10.png)

변수로 추가한 후 기존 **github actions workflow 메니페스토 파일**에
```yml
      - name: Inject Ingest URL
        run: |
          sed -i "s#INGEST_API_GATEWAY_URL#${{ secrets.INGEST_API_URL }}#g" _includes/clickstream.html
```
sed로 문자열을 변경하도록 위 내용을 빌드 전에 추가해 반영하도록 했다.

#### 3.4 프론트엔드 검증 및 결과
블로그 준비는 **지금 보고있는 이 창**으로 모두 마쳤다. 구체적인 검증은 다음과 같다.

1. 브라우저 Network 탭 확인
GitHub Pages로 배포된 이 블로그에 접속한 뒤, 클릭 이벤트 발생 시 `/ingest`로 POST 요청이 정상적으로 전송되는지 확인  
![네트워크 요청 결과](sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/11.png)

2. Lambda 로그(CW Logs) 확인
AWS 콘솔 → CloudWatch → 로그 그룹 `/aws/lambda/clickstream-ingest` 에서 실제 페이로드가 기록되었는지 확인
![lambda logs](sources/project1_Ingest-web-click-log/2025-05-21-판-벌리기/12.png)

## 결론 및 이후 계획

**개인 블로그 클릭스트림 수집 준비**는 다음과 같은 단계로 완성되었다.

1. **Jekyll 블로그**에 JS 스니펫을 심어 클릭 이벤트를 캡처  
2. **Lambda + HTTP API**로 간단히 수집 → CloudWatch Logs에 기록  
3. **GitHub Actions + Secrets**를 활용해 프로덕션/개발 환경 분기 처리

앞으로는 이 데이터를 데이터 파이프라인으로 연결하기 위해 다음 과정을 진행할 예정

1. **Kafka 프로듀싱**  
2. **배치 저장소 구성**  
3. **분석 환경 구축**  

이 과정을 통해 클릭스트림 로그 데이터 수집 → 빅데이터 분석 흐름을 이해해보려고 한다. 끝!

## 참고 자료
- [AWS Lambda & API Gateway를 이용한 서버리스 백엔드 구축](https://docs.aws.amazon.com/lambda/latest/dg/services-apigateway.html)   
- [Jekyll Include 문서](https://jekyllrb.com/docs/includes/)  