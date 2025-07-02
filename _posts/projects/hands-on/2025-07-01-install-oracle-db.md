---
title: Oracle database 19c 설치
description: GCP 인스턴스에 직접 DB 설치하기
author: annmunju
date: 2025-07-01 20:45:00 +0900
categories: [Hands On, DB]
tags: [Oracle, DB]
pin: false
math: true
mermaid: true
comments: true
---

Oracle Linux 8 기반의 GCP VM에 Oracle Database 19c를 수동 설치하고,  
이를 영구 디스크로 마운트하여 다른 인스턴스에서도 재사용 가능한 구조로 구성하는 실습을 진행했다.

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

## 전체 진행 순서

1. VM 생성 + Oracle 설치 파일 업로드
2. 디스크 마운트 + 초기 환경 설정 (setup.sh)
3. DB 생성 및 리스너 실행 (dbca, start_db.sh)
4. 디스크 분리 및 다른 VM으로 이전

---

### 1. VM 생성 + Oracle 파일 업로드

- VM 구성 정보

| 항목 | 내용 |
| --- | --- |
| 머신 이름 | mjahn-vm-test-db |
| 리전 | asia-northeast3 (zone : c) |
| 머신 유형 | e2-medium |
| OS | Oracle Linux 8 |
| 디스크 이름 | mjahn-disk-test-db |
| 라벨 | user:mjahn |

위 조건에 맞춰서 VM 인스턴스를 생성했다. 디스크는 영구적으로 사용할 수 있도록 백업 설정한다. 

#### a. vm에 ssh 키 등록 (gcloud cli)

> 로컬 PC는 윈도우 기반이고, gcloud CLI가 설치되어 있다는 전제하에 작성

```
setlocal enabledelayedexpansion

set "pubKeyPath=%USERPROFILE%\.ssh\gcp-test-key.pub"

set "pubKeyContent="
for /f "usebackq tokens=* delims=" %A in ("%pubKeyPath%") do (
    set "pubKeyContent=%A"
)

set "sshKeyEntry=ahnmunju:%pubKeyContent%"

gcloud compute instances add-metadata mjahn-vm-test-db-02 --metadata "ssh-keys=%sshKeyEntry%"
```

!변수! 형식은 루프 안에서 변수 값을 동적으로 쓸 수 있도록 설정한 것.
username:publicKey 형식으로 메타데이터에 SSH 키를 등록한다.

#### b. 오라클 파일 다운로드 및 업로드 (MobaXterm 이용)

로컬에서 클라우드로 전송. 
[공식 사이트](https://www.oracle.com/kr/database/technologies/oracle19c-linux-downloads.html)에서 19c용 RPM 파일을 받아서 업로드한다.

```shell
GCP_IP=
RPM_FILE="oracle-database-ee-19c-1.0-1.x86_64.rpm"
FNAME=~/Downloads/$RPM_FILE

cd ~/.ssh
scp -i gcp-test-key $FNAME \
	 ahnmunju@$GCP_IP:/tmp
```

나는 맥을 주로 쓰지만 윈도우 PC로 작업해야해서 MobaXterm 설치해 사용했다. (유닉스 명령어 사용 가능)

사실 gcloud CLI에서도 바로 전송 가능하긴 하다:

```
gcloud compute scp ~/Downloads/oracle-database-ee-19c-1.0-1.x86_64.rpm mjahn-vm-test-db:/tmp 
```

---

### 2. 디스크 마운트 및 환경 초기화 (setup.sh)

#### a. 디스크 포맷 및 마운트
```bash
sudo mkdir -p "$MOUNT_POINT"
sudo mkfs.ext4 "$DISK_DEVICE"  # 최초 1회만
```

#### b. 환경 초기화 스크립트 `setup.sh`

> 반복 작업 방지를 위해 한 번에 마운트, 사용자, 권한, fstab 등록까지 처리하는 스크립트

```bash
#!/bin/bash
# Oracle 19c 설치용 환경 초기화 스크립트
# 1. oracle-database-preinstall-19c 설치
# 2. /opt/oracle 마운트 및 UUID 기반 fstab 등록
# 3. oracle 유저/그룹 생성
# 4. 권한 설정 및 .bash_profile 환경 변수 지정

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

---

### 3. DB 생성 및 초기 실행

#### a. Oracle DB 생성 (dbca)

```bash
dbca -silent -createDatabase \
  -templateName General_Purpose.dbc \
  -gdbname ORCLCDB -sid ORCLCDB \
  -createAsContainerDatabase true \
  -pdbName ORCLPDB1 \
  -characterSet AL32UTF8 \
  -totalMemory 1024 \
  -emConfiguration NONE \
  -sysPassword [비밀번호] \
  -systemPassword [비밀번호]
```

#### b. 리스너 및 DB 실행 스크립트 `start_db.sh`

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

리스너만 시작해주고, sqlplus로 DB를 startup 해주면 끝.

---

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

이렇게 하면 되고 나는 그냥 VM 통째로 삭제했다.

#### b. 다른 VM에 이전 하기

gcp에 콘솔에서 vm 인스턴스 생성할 때 영구 디스크 선택하면 (물론 리전이 동일해야함!) 알아서 zone 맞춰서 생성된다. 
OS 동일하게 설정하고 생성하면 attach된 상태로 새로운 vm 인스턴스가 생긴다.

그리고 2. b. `setup.sh` 스크립트와 3. b. `start_db.sh`를 vi로 작성하고 sudo 권한으로 실행하면 된다.

---

## 다음 단계 (예정)

- ORCLPDB1에 샘플 테이블 생성
- SQL Developer 또는 APEX를 통해 GUI로 접속해보기
- 디스크 스냅샷 및 백업 실험

… 그리고 고민 중 😅

---

## 마무리

VM 이전까지 문제 없이 붙고 실행되는 것을 확인했다. 실습이 생각보다 꽤 디테일하고 삽질도 있었지만 영구 디스크 구조를 잡고 재활용 가능한 스크립트를 만든 덕분에 다음 작업이 한결 편해졌다.

꽤 고전했던 부분은 12 버전부터 있었다는 CDB, PDB 개념을 명확하게 몰라서 DB 초기 생성할 때 startup; 하면 뚝딱 DB 만들어주지 않고 에러난 부분이었다.
기존처럼 init.ora만 수정해서 인스턴스를 띄우면 될 줄 알았는데, 제어파일과 데이터파일이 실제로 존재해야 mount/open 단계까지 넘어가는 구조였고 게다가 CDB 모드에서는 PDB가 구성되어 있어야만 제대로 기동된다는 것도 뒤늦게 파악했다.

처음에는 뭔가 빠졌다는 걸 모르고 로그만 계속 뒤지다가 결국 구조 자체가 CDB/PDB 기반임을 이해하고 나서야 dbca를 활용한 정석 생성 흐름으로 전환했다.
이후로는 각 구성 요소의 경로와 목적을 명확히 인식하면서 adump, audit, diag, oradata 등 Oracle이 요구하는 디렉토리들을 순서대로 만들어주고 환경 변수까지 정확히 세팅하니 이전보다 훨씬 빠르고 안정적으로 재설치 재기동이 가능해졌다.

특히 Oracle은 기본적으로 많은 디렉토리와 파일 경로를 하드코딩처럼 참조하는데 하나라도 누락되거나 권한이 부족하면 startup조차 되지 않고 에러 로그도 불친절해서 초보자에게는 진입장벽이 높다... 예를 들어 audit_file_dest, db_recovery_file_dest, control_files 등 경로 설정이 존재하더라도 디렉토리가 실제로 없으면 곧바로 에러가 발생하고 SQL*Plus 연결 자체가 끊기는 식이다.

그 와중에도 어떤 파일이 필요하고 어떤 순서로 생성되어야 하는지를 체계적으로 파악하면서 Oracle이 어떤 구조로 작동하는지 감을 잡게 된 실습이었다. 이후에는 CDB/PDB 개념을 정리해보겠다. 끝!
