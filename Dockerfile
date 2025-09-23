FROM node:22-alpine

# bash 설치
RUN apk add --no-cache bash
RUN apk add --no-cache ruby-bundler

# 소스 코드 복사 (단, _posts 폴더는 복사하지 않음. 볼륨으로 연결)
WORKDIR /app
COPY . . 
RUN rm -rf /app/_posts

# 볼륨 마운트 (_posts 폴더)
VOLUME ["/app/_posts"]

# 실행 권한 부여
RUN chmod +x tools/run.sh
RUN apk add --no-cache build-base ruby-dev 
RUN bundle install
RUN apk add --no-cache git

# 4000번 포트 오픈
EXPOSE 4000

# 컨테이너 시작 시 run.sh 실행
CMD ["bash", "tools/run.sh", "--host", "0.0.0.0"]

# _posts 폴더는 반드시 볼륨으로 연결해서 사용하세요.
# 예시: docker run -it --rm -p 4000:4000 -v $(pwd)/_posts:/app/_posts --name annmunju-blog-container annmunju-blog