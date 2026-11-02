# 학습 목차

처음에는 [전체 흐름](learning/theory_first.md)을 읽고 A0부터 시작합니다. 이미 읽었다면 이어서 볼 장을 고릅니다.

문서 번호는 자료 이름입니다. 아래 순서와 각 장의 ‘다음 개념’을 따라갑니다.

## 모델의 기본

- [A0. 모델·학습·추론](fundamentals/A0.md)
- [A1. 사진을 숫자로 읽기](fundamentals/A1.md)
- [A2. 곱하는 값과 기본값](fundamentals/A2.md)
- [A3. 계산 단계 이어 붙이기](fundamentals/A3.md)

## 학습과 평가

- [A4. 예측을 채점하고 고치기](fundamentals/A4.md)
- [A5. 새 문제로 평가하기](fundamentals/A5.md)

## 이미지를 계산하는 방법

- [B1. 작은 필터로 계산하기](fundamentals/B1.md)
- [B2. 여러 채널 합치기](fundamentals/B2.md)
- [B3. 반응을 후보별 점수로 모으기](fundamentals/B3.md)
- [A7. 깊은 계산에서 값의 크기 조정하기](fundamentals/A7.md)
- [B4. 원래 값에 계산 결과 더하기](fundamentals/B4.md)
- [B5. ResNet-20 전체 따라가기](fundamentals/B5.md)

## 같은 계산을 회로로 옮기는 방법

- [A6. 정수와 눈금으로 저장하기](fundamentals/A6.md)
- [D1. 중간 합과 반올림 규칙](fundamentals/D1.md)
- [D2. 회로에서 계산 반복하기](fundamentals/D2.md)
- [D3. 계산할 값 보관하기](fundamentals/D3.md)
- [D5. 준비된 값을 전달하기](fundamentals/D5.md)

## 이론을 읽은 뒤 계산과 실습

작은 예제를 손으로 계산한 뒤 실행 결과와 비교합니다. 필수 순서는 **S0 → S1 → S2 → S3 → S4 → S6**입니다. S5는 실제 모델로 넓히고 싶을 때 고릅니다.

| 실습 | 확인할 내용 |
| --- | --- |
| [S0](learning/S0.md) | 작은 필터의 곱·합 |
| [S1](learning/S1.md) | 사진 한 장의 점수와 예측 |
| [S2](learning/S2.md) | 학습 한 번·두 경로 더하기 |
| [S3](learning/S3.md) | 정수 눈금·반올림 |
| [S4](learning/S4.md) | 회로에서 전달·대기 확인 |
| [S6](learning/S6.md) | 실제 보드에서 결과 확인 |
| [선택 S5](learning/S5.md) | 실제 모델의 계산으로 확장 |

[실습 기록 양식](learning/worksheet.md) · [현재 진행 상태](project_status.md)

<details>
<summary>선택 실습의 현재 연결 상태</summary>

S5를 선택했다면 [Stem](stem_e2b_rtl.md) → [Residual 단위](residual_e2b_rtl.md) → [Stem→Residual 연속 RTL](stem_residual_e2b_rtl.md) 순서로 확인합니다. 연속 실행은 시작 한 번으로 실제 Stem 출력을 전달하며, 실제 입력5회·합성0 입력1회에서 모든 경계가 일치했습니다.

S5 확장에서는 [실제 Transition L2.0·L3.0](transition_e2b_rtl.md)의 stride2·Option A를 확인한 뒤 [전체 모델 RTL](full_e2b_rtl.md)로 이어갑니다. 실제 sample 0→1→0, 61경계·최종 점수·예측과 Stall·Reset 재실행이 일치했습니다. 실제 보드 실행은 별도입니다.

</details>
