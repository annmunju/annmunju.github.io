---
title: A Neural Representation of Sketch Drawings, 2017
description: Drawing Model Review
author: annmunju
date: 2023-10-07 12:05:00 +0900
categories: [tech-deep-dives, ai]
tags: [dl, drawing, ai, rnn, paper]
pin: false
math: true
mermaid: false
comments: false
---

📖 David Ha, Douglas Eck. A Neural Representation of Sketch Drawings, 2017.

[참고] 인공 신경망의 하위 구성

![](https://blog.kakaocdn.net/dn/dO3aek/btsshvk9kiA/0H8k63iMTRFABWkKVDmjG1/img.png)

---

### 배경

- Quick Draw!는 사람이 그린 그림이 무엇인지 인공지능이 맞히는 게임이다. 구글은 이를 통해서 공개 데이터셋을 구축했다.
- Sketch-RNN은 퀵드로우 데이터를 바탕으로 사람들이 그린 순서로 그림을 학습해 그리는 과정을 예측할 수 있는 모델이다.

### 목표

- 사람이 그리는 것과 비슷하게 추상적인 개념을 일반화하여 그릴 수 있도록 기계를 훈련시키는 것

### 데이터

- 사람이 직접 그린 스케치의 과정으로 학습
    - 펜을 어느 방향으로 움직였는지
    - 언제 펜을 종이에서 띄었는지
    - 언제 멈추었는지

### 모델 구성

![](https://blog.kakaocdn.net/dn/bzgp4f/btssfGnG17t/q6REl4cW6vU4zfVOf7RCTK/img.png)

- 구조
    - sequence-to-sequence (seq2seq) autoencoder framework
        - Goal = To train a network to encode an input sequence into a vector of floating point numbers, called a **latent vector.**
        - Latent vector
            - Reconstruct an output sequence using a decoder that replicates the input sequence as closely as possible.
        - Latent space
            - **Latent vector**는 한 이미지가 가지고 있는 잠재적인 벡터 형태의 변수. 이런 latent vector들이 모여서 **latent space**가 형성됨.
- 특징
    - 디코더 모듈을 독립 실행할 수 있다.

### 조작하기 (활용하기)

- 모델에서 latent vector에 고의로 노이즈를 추가하기
    - 노이즈 추가하면 모델이 input 스케치와 똑같이 만들지 못한다.

![](https://blog.kakaocdn.net/dn/CI0PL/btssquTcrlP/k9KWdGkOButrZFvMkaupM0/img.png)

1. 인코더를 이용해서 스케치 조건을 주기
    - 입력으로 넣은 스케치와 유사한(똑같지 않은) 스케치를 생성한다.
    - 모델은 스케치의 본질을 학습함. 아래 이미지와 같이 일반적이지 않은 input도 돼지로 변환시켜줌.
2. 인코더를 생략하고 디코더만 사용하면 불완전한 스케치를 완성하도록 할 수 있다. 정해지지 않은 다양한 형태로 나타난다.
3. 몸이 없는 동물에 몸을 추가하거나 뺄 수 있을까?
    - 원래의 값에 새로운 특징을 노이즈로 추가하거나 빼버리면 입력 스케치에 없던 새로운 특징을 가진 스케치를 얻을 수 있음
    - 예) 고양이 얼굴 + (돼지 전체 - 돼지 얼굴) = 고양이 전체

![](https://blog.kakaocdn.net/dn/usIBN/btsscFCy97B/ozeao5ZlraotxnBZvO5NX0/img.png)

### 훈련 세부

![](https://blog.kakaocdn.net/dn/HM77e/btssgofIPOZ/SMICalEbraG9tOKJOXuP0K/img.png)

- - Lkl : [쿨백-라이블러(Kullback-Leibler)](https://angeloyeo.github.io/2020/10/27/KL_divergence.html) 발산 = 두 확률 분포 차이 비교. 차이 적을수록 0에 가까워짐.
        - Ls : 이동 벡터(방향+거리)에 대한 Loss
        - Lp : 펜 데이터 (상태)에 대한 Loss
        - Lr = Ls + LpLoss Function
    
    - Lr 과 Lkl은 Tradeoff 관계에 있음. wkl 값에 따라서 로스를 빨리 감소시키거나 천천히 감소시키는 역할을 한다. → 마치 Learning rate의 역할을 해준다고 판단.

![](https://blog.kakaocdn.net/dn/KkL1e/btssiguuixQ/pbfrSCLqbnzKBlG92RZrF0/img.png)

### 결론

- Sketch RNN은 기존에 완성된 이미지만을 바탕으로 분류하는 모델과는 다르게 과정으로 훈련된 모델이다.
- (Loss) 과정 중에도 **이동 벡터에 대한 로스와 펜 상태에 대한 로스의 합** ↔ **쿨백 라이블러 발산**을 로스로 정의하고 둘의 트레이드 오프 관계를 이용해 Wkl 값을 바꿔가면서 모델을 개선시킨다.
- 완성된 모델은 Encoder - Latent Vector - Decoder 구조로 되어있고, Latent Vector의 값을 변형하면 같은 대상의 그림도 다르게 표현될 수 있다.
    - 연산도 가능하다. 예를들어 돼지 얼굴 + 고양이 몸통에 해당하는 Latent Vector을 더하면 몸통이 있는 돼지 그림이 완성된다.
    - Encoder를 생략하면 Decoder만으로 미완성 그림을 완성시킬 수도 있다.
- 정리하자면, 그림의 핵심 정보를 요약한 Latent Vector을 조작해서 그림 과정에서의 변형을 일으키는 모델이라고 볼 수 있다.