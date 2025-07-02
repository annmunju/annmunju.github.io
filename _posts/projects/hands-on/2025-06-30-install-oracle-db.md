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

사전 조건에 맞춰 Oracle Database를 설치하는 과정을 정리해보려고 한다.

## 진행 순서

1. VM 생성 후 오라클 파일 업로드
2. Oracle 19c 설치를 위한 디스크 마운트 및 환경 초기화 스크립트
3. DB 생성 및 초기 실행
4. 디스크 분리 후 다른 VM에 이전 하기

---

### 1. VM 생성 후 오라클 파일 업로드

- 조건에 따른 설정 정보 정리

| 항목 | 내용 |
| --- | --- |
| 머신 이름 | mjahn-vm-test-db |
| 리전 | asia-northeast3 (zone : c) |
| 머신 유형 | e2-medium |
| OS | Oracle Linux 8 |
| 디스크 이름 | mjahn-disk-test-db |
| 라벨 | user:mjahn |

우선 위 조건에 맞춰서 VM 인스턴스를 생성했다. 디스크는 영구적으로 사용할 수 있도록 백업 설정한다. 

#### a. vm에 ssh 키 등록 (gcloud cli 이용)

gcloud cli가 설치되었다는 것을 전제로 한다. 로컬 PC는 윈도우 기반이다. 

```cmd
setlocal enabledelayedexpansion

set "pubKeyPath=%USERPROFILE%\.ssh\gcp-test-key.pub"

set "pubKeyContent="
for /f "usebackq tokens=* delims=" %A in ("%pubKeyPath%") do (
    set "pubKeyContent=%A"
)

set "sshKeyEntry=ahnmunju:%pubKeyContent%"

gcloud compute instances add-metadata mjahn-vm-test-db-02 --metadata "ssh-keys=%sshKeyEntry%"
```

구문 간단하게 설명하자면 루프 안에서 !변수! 형식으로 변수 값을 동적으로 쓸 수 있게 설정했고, 공개 키 위치 `pubKeyPath`를 기반으로 해당 파일에 있는 내용 전체를를 `pubKeyContent`에 담았았다.
그리고 키를 username:publicKey 형식으로 조합해서 `sshKeyEntry`에 넣고 메타데이터로 등록한다.

#### b. 오라클 파일 다운로드 및 업로드 (MobaXterm 이용)

로컬에서 클라우드로 전송할거다. gcp 콘솔에서 ssh 접속해서 수동으로 업로드 하려다가 숨넘어가는줄 알았다... 그래서 scp로 보낸다.
[공식 사이트](https://www.oracle.com/kr/database/technologies/oracle19c-linux-downloads.html)에서 19c 버전으로 설치했다. rpm 파일을 받고 전송할거다.

```shell
GCP_IP=
RPM_FILE="oracle-database-ee-19c-1.0-1.x86_64.rpm"
FNAME=~/Downloads/$RPM_FILE

cd ~/.ssh
scp -i gcp-test-key $FNAME \
	 ahnmunju@$GCP_IP:/tmp
```

나는 맥을 주로 사용했기 때문에 유닉스 명령어 사용이 훨~씬 편해서 MobaXterm을 작업하는 윈도우 PC에 설치해 사용했다.

하지만 찾아보니까 gcloud cli에도 scp를 사용하는 코드가 있다고 한다 ^^...

```cmd
gcloud compute scp ~/Downloads/oracle-database-ee-19c-1.0-1.x86_64.rpm mjahn-vm-test-db:/tmp 
```

아무튼 rpm 파일이 서버 내에 보내진다.

### 2. Oracle 19c 설치를 위한 디스크 마운트 및 환경 초기화 스크립트

#### a. DB 설치용 디스크 초기화
```bash
sudo mkdir -p "$MOUNT_POINT"
sudo mkfs.ext4 "$DISK_DEVICE"  # 최초 1회만
```

#### b. `setup.sh` 스크립트 작성

패키지도 설치하고 디스크도 마운트 하고, 
사용자/그룹과 권한 설정도 해주고 
껐다 켜도 인식 될 수 있게 변수 설정 & fstab 등록까지 하는 전체 스크립트를 작성했다.

```bash
#!/bin/bash

DISK_DEVICE="/dev/sdb"
MOUNT_POINT="/opt/oracle"
ORACLE_USER="oracle"
ORACLE_GROUP="oinstall"
ORACLE_SID="ORCLCDB"
ORACLE_VERSION="19c"
ORACLE_HOME="$MOUNT_POINT/product/$ORACLE_VERSION/dbhome_1"
ORACLE_BASE="$MOUNT_POINT"

LOG_FILE="/var/log/oracle_setup.log"
exec &> >(tee -a "$LOG_FILE")

echo "[$(date)] Oracle 환경 설정 시작"

# 의존 패키지 설치
sudo dnf install -y oracle-database-preinstall-19c

# 디스크 확인
if [ ! -b "$DISK_DEVICE" ]; then
  echo "[$(date)] 디스크 $DISK_DEVICE 가 존재하지 않습니다. 종료합니다."
  exit 1
fi

# 마운트
echo "[$(date)] 디스크 마운트 중..."
sudo mkdir -p "$MOUNT_POINT"
sudo mount "$DISK_DEVICE" "$MOUNT_POINT"

df -h | grep "$MOUNT_POINT" || {
  echo "[$(date)] 디스크 마운트 실패"
  exit 1
}

# 사용자 및 그룹
echo "[$(date)] 사용자 및 그룹 생성 중..."
sudo groupadd -f "$ORACLE_GROUP"
sudo groupadd -f dba
if ! id "$ORACLE_USER" &>/dev/null; then
  sudo useradd -m -g "$ORACLE_GROUP" -G dba "$ORACLE_USER"
  echo "[$(date)] $ORACLE_USER 계정이 생성됨. 비밀번호 설정 필요."
  sudo passwd "$ORACLE_USER"
fi

# 권한 설정
echo "[$(date)] 디렉토리 권한 설정 중..."
sudo chown -R "$ORACLE_USER:$ORACLE_GROUP" "$MOUNT_POINT"
sudo chmod 775 "$MOUNT_POINT"
sudo usermod -aG wheel oracle

# 환경 변수 설정
echo "[$(date)] .bash_profile 환경 변수 설정 중..."
ORACLE_PROFILE="/home/$ORACLE_USER/.bash_profile"
sudo bash -c "cat >> $ORACLE_PROFILE" <<EOF

# Oracle 환경 설정
export ORACLE_BASE=$ORACLE_BASE
export ORACLE_HOME=$ORACLE_HOME
export ORACLE_SID=$ORACLE_SID
export PATH=\$ORACLE_HOME/bin:\$PATH
EOF

# fstab 등록
echo "[$(date)] fstab 설정 중..."
UUID=$(sudo blkid -s UUID -o value "$DISK_DEVICE")
if [ -z "$UUID" ]; then
  echo "[$(date)] UUID 조회 실패"
  exit 1
fi
FSTAB_ENTRY="UUID=$UUID  $MOUNT_POINT  ext4  defaults,nofail  0  2"
grep -q "$UUID" /etc/fstab || echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab

echo "[$(date)] Oracle 환경 설정 완료"
```

> 너무 길지만 다른 VM에 이식할 때도 필요한 작업이라 스크립트 작성 해뒀다. 귀찮음 방지

### 3. DB 생성 및 초기 실행

#### a. 데이터베이스 생성

```bash
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \        # 일반적인 목적의 템플릿 사용
  -gdbname ORCLCDB -sid ORCLCDB \            # 전체 DB 이름과 SID를 ORCLCDB로 설정 (CDB)
  -createAsContainerDatabase true \          # 컨테이너 데이터베이스(CDB)로 생성
  -pdbName ORCLPDB1 \                        # 기본 PDB 이름 설정 → ORCLPDB1 생성됨
  -characterSet AL32UTF8 \                   # 문자셋 설정
  -totalMemory 1024 \                        # 메모리 1024MB 할당
  -emConfiguration NONE \                    # Enterprise Manager는 설정 안함
  -sysPassword <비밀번호> \                   # SYS 계정 비밀번호
  -systemPassword <비밀번호>                  # SYSTEM 계정 비밀번호
```

#### b. `start_db.sh` 스크립트 작성

이것도 다른 VM에 새롭게 마운트하면 실행시켜야 하는 내용이라 스크립트로 작성했다.

```bash
#!/bin/bash

ORACLE_USER="oracle"

LOG_FILE="/var/log/oracle_start.log"
exec &> >(tee -a "$LOG_FILE")

echo "[$(date)] Oracle DB 시작 스크립트 실행"

# oracle 사용자로 전환하여 실행
sudo su - "$ORACLE_USER" -c "source ~/.bash_profile && {
  echo \"[$(date)] Listener 시작 중...\"
  lsnrctl start

  echo \"[$(date)] DB 시작 중...\"
  echo -e 'startup\nexit' | sqlplus / as sysdba
}"

```

리스너 시작하고 startup 하는게 전부다.

### 4. 디스크 분리 후 다른 VM에 이전 하기

#### a. 디스크 분리

```bash
sqlplus / as sysdba
> shutdown;
> exit;

sudo lsnrctl stop

sudo umount /opt/oracle
```

프로세스 끄고 마운트 해제하면 된다. 그리고 gcloud에 있는 디스크도 분리하면 되는데 

```
gcloud compute instances detach-disk <INSTANCE_NAME> \
    --disk <DISK_NAME> --zone=<ZONE>
```

이렇게 하면 되고 나는 그냥 vm 지워버렸다. 

#### b. 다른 VM에 이전 하기

gcp에 콘솔에서 vm 인스턴스 생성할 때 영구 디스크 선택하면 (물론 리전이 동일해야함!) 알아서 zone 맞춰서 생성된다. 
OS 동일하게 설정하고 생성하면 attach된 상태로 새로운 vm 인스턴스가 생긴다.

