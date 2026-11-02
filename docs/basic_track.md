# 이론을 이해하고 계산·실습으로 확인하기

**전체 흐름 → 개념 설명 → 작은 계산 → 실습 확인** 순서입니다.

## 0. 전체 흐름부터 읽기

[처음 읽는 전체 흐름](learning/theory_first.md)에서 사진이 예측이 되는 과정과 학습·Loss·Weight·가속기의 역할을 먼저 이해합니다. 여기서는 코드를 실행하지 않습니다.

## 1부. 개념 이해하기

### 모델 기본

입력·Weight·Bias·Layer.

[A0](fundamentals/A0.md) → [A1](fundamentals/A1.md) → [A2](fundamentals/A2.md) → [A3](fundamentals/A3.md)

### 학습과 평가

예측·Loss·수정·새 데이터 평가.

[A4](fundamentals/A4.md) → [A5](fundamentals/A5.md)

### CNN

필터·Channel·점수·Residual·모델 전체.

[B1](fundamentals/B1.md) → [B2](https://app.notion.com/p/407f0c4baec981eeb9d9d03b5f6df291) → [B3](https://app.notion.com/p/407f0c4baec981259881f8492bfb6a92) → [A7](fundamentals/A7.md) → [B4](https://app.notion.com/p/407f0c4baec98114b0e8fccad9a3f3a3) → [B5](https://app.notion.com/p/407f0c4baec981699098e71ca989426b)

### 정수와 회로

눈금·곱과 누산·메모리·수락과 대기.

[A6](fundamentals/A6.md) → [D1](https://app.notion.com/p/407f0c4baec981b8ae88d705e9af515b) → [D2](https://app.notion.com/p/407f0c4baec981348930d325194279c6) → [D3](https://app.notion.com/p/407f0c4baec9815eb990d04fbbcc60fa) → [D5](https://app.notion.com/p/407f0c4baec981e1b9fafb21f2519ec2)

앞쪽은 쉬운 설명과 예시입니다. 수식·세부 규약은 뒤에서 필요할 때 읽습니다. 모르는 용어를 외운 채 실습부터 할 필요는 없습니다.

## 2부. 이제 계산과 실습으로 확인하기

| 실습 | 확인할 개념 |
| --- | --- |
| [S0](learning/S0.md) | 작은 필터의 곱·합과 재사용 |
| [S1](learning/S1.md) | 이미지·클래스 점수·예측 |
| [S2](learning/S2.md) | Weight 갱신·Residual |
| [S3](learning/S3.md) | 정수 눈금·반올림 |
| [S4](learning/S4.md) | MAC·메모리·대기 |
| [선택 S5](learning/S5.md) | 실제 모델 계수 연결 |
| [S6](learning/S6.md) | 보드 결과와 기준 비교 |

개념을 짚고 → 손으로 계산하고 → 코드를 실행해 비교합니다. 필수 실습은 S0→S1→S2→S3→S4→S6이며 S5는 선택입니다.

[짧은 기록](learning/worksheet.md) · [현재 진행 상태](project_status.md)

S5를 선택했다면 [Stem](stem_e2b_rtl.md) → [Residual 단위](residual_e2b_rtl.md) → [Stem→Residual 연속 RTL](stem_residual_e2b_rtl.md) 순서로 확인합니다. 연속 실행은 시작 한 번으로 실제 Stem 출력을 전달하며, 실제 입력5회·합성0 입력1회에서 모든 경계가 일치했습니다.
