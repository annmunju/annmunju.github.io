---
title: "AutoGluon으로 시작한 AutoML과 벤치마크 실험"
description: Tabular, Time Series, OpenML 실험을 통해 AutoML의 구조를 공부한 기록
author: annmunju
date: 2026-04-22 22:17:28 +0900
categories: [기술 공부 기록, ML]
tags: [automl, autogluon, time-series, chronos, openml, benchmark]
pin: false
math: true
mermaid: true
comments: false
---
모델 선택과 튜닝을 자동화하는 AutoML을 공부했다. 오픈소스 AutoGluon의 Tabular 기능에서 시작해 시계열 예측과 OpenML 실험까지 진행했던 내용을 한 글에 이어서 적어본다.

## 1. AutoGluon으로 AutoML 시작하기

RAPIDS를 공부한 뒤에는 모델을 직접 하나씩 선택하고 튜닝하는 과정을 자동화하는 AutoML을 배웠다. 이번에는 AutoML 오픈소스 라이브러리인 AutoGluon을 이용해 Tabular 데이터에서 AutoML이 어떤 식으로 동작하는지 살펴보았다.

![AutoGluon 학습 후 출력된 leaderboard](/sources/tech-deep-dives/2026-04-22-automl-journey/autogluon-leaderboard.png)

AutoML을 처음 사용할 때는 코드가 짧다는 점만 눈에 띄었다. 내부에서 어떤 모델이 실행되었고 어떤 검증 결과를 바탕으로 최종 모델이 선택되었는지 확인하지 않으면 결과를 신뢰하기 어려울 것 같았다.

### AutoML을 사용하는 이유

일반적인 머신러닝 실험에서는 데이터 전처리, 모델 선택, 하이퍼파라미터 조정, 앙상블, 평가를 반복한다. 데이터와 모델을 이해하는 과정은 중요하지만, 매번 같은 실험 코드를 작성하는 일에는 많은 시간이 들어간다.

AutoML은 이 과정을 일정 부분 자동화한다.

- 여러 모델을 학습한다.
- 모델별 성능을 비교한다.
- 검증 결과를 바탕으로 앙상블한다.
- 제한 시간 안에서 실험을 관리한다.

### Tabular 데이터로 실행해보기

```python
from autogluon.tabular import TabularPredictor

predictor = TabularPredictor(label="Survived").fit(
    train_data,
    time_limit=300,
)

predictions = predictor.predict(test_data)
leaderboard = predictor.leaderboard(train_data)
```

사용자는 데이터와 target만 전달하지만 내부에서는 여러 모델과 앙상블이 실행된다. 처음에는 이 점이 편리하게 느껴졌지만 성능 결과를 해석하려면 어떤 모델이 선택되었고 어떤 검증 방식이 사용되었는지 확인해야 했다.

자동화는 모델을 몰라도 된다는 뜻이 아니라 모델 선택과 실험 과정을 더 체계적으로 관리한다는 의미에 가까웠다.

AutoML을 사용하면 빠르게 기준 성능을 만들 수 있다. 반면 기본 설정이 모든 데이터에 적합한 것은 아니다. 데이터 누수, 평가 지표, 시간 제한, 학습, 검증 분할은 여전히 사용자가 결정해야 한다.

### 자동화된 결과를 어떻게 읽을까

leaderboard에는 모델별 점수와 예측 시간, 학습 시간 등이 함께 표시된다. 여기서 가장 높은 점수 하나만 확인하면 안 된다. 실제 운영에서는 추론 속도와 메모리 사용량, 모델의 재현성도 중요하기 때문이다.

또한 데이터 전처리가 학습과 예측에서 동일하게 적용되었는지 확인해야 한다. AutoML이 많은 과정을 대신 처리하더라도 target 누수나 잘못된 validation split을 자동으로 해결해주는 것은 아니다.

### 편리함과 통제 사이

이 실험을 하면서 GPU 기반 AutoML을 직접 만드는 작업을 준비하기 시작했다. AutoGluon의 편리한 사용 방식과 LightAutoML의 파이프라인 구조를 참고해 RAPIDS 위에서 동작하는 구조를 고민해 오픈소스를 만들고자 했다. 자동화된 도구를 쓸수록 내부에서 어떤 일이 일어났는지 기록해두어야 한다는 것도 알게 되었다.

## 2. AutoGluon Time Series와 Chronos2 살펴보기

Tabular AutoML을 살펴본 다음에는 AutoGluon의 시계열 기능을 공부했다. 시계열 데이터는 일반적인 테이블 데이터와 달리 시간의 순서가 중요하기 때문에 학습 데이터와 검증 데이터를 나누는 방법부터 달랐다.

![AutoGluon 시계열 데이터의 과거 구간과 예측 구간](/sources/tech-deep-dives/2026-04-22-automl-journey/autogluon-timeseries-forecast.png)

특히 시계열은 데이터 행 하나만 보아서는 의미를 이해하기 어렵다. 어느 시점에 관측되었는지, 동일한 item이 어떤 주기로 기록되었는지, 예측하려는 미래 구간이 어디부터 시작하는지를 함께 보아야 한다.

### 시계열 예측에서 중요한 것

시계열 예측에서는 과거의 데이터를 이용해 미래를 예측한다. 따라서 일반적인 random split을 적용하면 미래 정보가 학습 데이터에 섞이는 문제가 생길 수 있다.

- 시간 순서를 지키는 train/validation 분리
- 예측 구간인 prediction length 설정
- 여러 시계열을 구분하는 item_id
- 시간 간격과 결측치 처리

이 네 가지가 기본적으로 필요했다.

### AutoGluon의 흐름

```python
from autogluon.timeseries import TimeSeriesPredictor

predictor = TimeSeriesPredictor(
    prediction_length=24,
    target="target",
).fit(train_data)

forecast = predictor.predict(train_data)
```

AutoGluon은 여러 예측 모델을 학습하고 결과를 비교한다. 단순 통계 모델부터 딥러닝 기반 모델까지 선택지가 넓었고 같은 데이터라도 예측 구간에 따라 결과가 달라질 수 있었다.

Chronos2도 함께 살펴보면서 사전학습 시계열 모델이 일반적인 supervised learning과는 다른 방식으로 활용될 수 있다는 점을 확인했다. 모델의 정확도만 보는 것이 아니라 데이터의 시간 해상도, 예측 목적, 운영 주기를 함께 고려해야 했다.

### 평가 지표를 따로 공부한 이유

시계열 예측은 단순히 평균 오차 하나만으로 모델을 판단하기 어렵다. MAE, RMSE, MAPE, WQL 등 지표에 따라 좋은 모델의 기준이 달라진다.

예측값이 실제값보다 작을 때 더 큰 비용이 발생하는 문제라면 대칭적인 오차 지표만으로 충분하지 않을 수 있다. 결국 지표는 모델이 아니라 문제의 목적에서 결정해야 한다.

### 예측 길이에 따른 차이

prediction length를 짧게 설정하면 가까운 미래를 맞히는 문제가 되고 길게 설정하면 계절성과 추세를 함께 고려해야 하는 문제가 된다. 같은 모델이라도 예측 길이가 바뀌면 유리한 모델이 달라질 수 있다.

그래서 단일 시점의 점수만 보기보다 여러 구간을 반복해서 평가하고 실제 서비스에서 필요한 예측 주기와 맞춰보는 것이 중요했다.

공부하면서 AutoML은 모델을 자동으로 선택해주는 도구이지만 데이터의 시간적 의미까지 대신 정해주는 도구는 아니라는 점을 알게 되었다. 다음에는 이 실험 결과를 정량적으로 비교할 수 있도록 OpenML 기반 벤치마크를 구성해보기로 했다.

## 3. OpenML 데이터로 AutoML 벤치마크 시작하기

AutoML을 공부하면서 한 가지 모델만 실행해보는 것보다 여러 데이터셋에서 반복적으로 비교해보는 과정이 필요하다고 느꼈다. 그래서 OpenML 데이터셋을 이용해 AutoGluon 실험을 정리하기 시작했다.

![데이터셋별 AutoML 모델 성능과 결과 비교표](/sources/tech-deep-dives/2026-04-22-automl-journey/autogluon-comparison-results.png)

한두 번의 실행 결과만으로 모델의 우열을 말하면 데이터셋의 특성에 결론이 종속될 수 있다. 여러 데이터셋을 같은 규칙으로 실행하고 성공한 결과뿐 아니라 실패한 실행도 남겨야 실험 자체를 신뢰할 수 있다.

### 벤치마크에서 먼저 정해야 하는 것

모델을 비교하기 전에 실험 조건을 고정해야 한다.

- 데이터셋과 target column
- train/test 또는 train/validation 분할
- 평가 지표
- 학습 시간 제한
- 사용할 모델과 앙상블 범위
- 결과를 저장할 형식

이 조건이 매번 달라지면 성능 숫자를 비교하기 어려워진다. AutoML에서는 모델이 자동으로 선택되기 때문에 더더욱 실험 조건을 문서로 남겨야 했다.

### OpenML을 선택한 이유

OpenML은 여러 공개 데이터셋을 동일한 방식으로 내려받아 실험할 수 있게 해준다. 하나의 데이터셋에서 잘 동작한 설정이 다른 데이터셋에서도 유지되는지 확인하기에 적합했다.

```python
from openml import datasets

dataset = datasets.get_dataset(dataset_id)
X, y, categorical, feature_names = dataset.get_data(
    target=target_name,
)
```

실험 결과에는 단순한 점수뿐만 아니라 데이터 크기, 실행 시간, 최종 모델, 실패 여부를 함께 저장해야 한다. 그래야 나중에 결과가 왜 달라졌는지 다시 확인할 수 있다.

### 이번 실험에서 얻은 것

벤치마크는 모델 순위를 정하는 작업이기도 하지만 실험 파이프라인의 문제를 찾는 과정이기도 했다. 데이터셋마다 결측치와 범주형 데이터가 다르고 모델마다 지원하는 입력 형식이 달랐다.

### 결과를 저장하는 방식

실험 결과에는 다음 정보를 함께 남기는 방향으로 정리했다.

| 항목 | 기록 이유 |
|---|---|
| dataset id와 target | 동일 데이터셋 재실행 |
| train/validation 방식 | 평가 조건 재현 |
| model과 preset | 결과 원인 확인 |
| score와 metric | 성능 비교 |
| 학습, 추론 시간 | 운영 비용 비교 |
| 실패 메시지 | 다음 실험의 개선점 |

이 경험은 이후 GUAM 프로젝트에서 공통 benchmark runner, 데이터 카드, 결과 리포팅 구조를 설계할 때 직접 참고가 되었다. 자동화된 실험은 기록을 남겨야 나중에 같은 조건으로 다시 확인할 수 있다는 것도 알게 되었다.

AutoML은 실험을 반복할 수 있도록 기준을 만드는 작업이었다.

---

AutoGluon으로 빠르게 실험해보면서 자동화된 도구의 편리함과 함께 결과를 확인하고 기록하는 일의 중요성도 같이 배웠다. 다음에는 이 구조를 GPU 환경에서 직접 만들어보려고 한다.

끝!
