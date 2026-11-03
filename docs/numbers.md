# 수치 기준표 (Notion R0와 같은 내용)

Notion: R0. 수치 기준표 · 2026-11-02
다른 문서의 크기·자원·FPS 수치가 이 표와 다르면 이 표를 따른다.
조건: CIFAR-10 32×32, BasicBlock(post-activation), 채널 16/32/64, Option A, batch=1.
모델 수치는 `python -m model.resnet20_plan`(→ `results/resnet20_plan.json`)으로 재현한다.

## 1. 단위

- KiB = 1,024 B, kB/MB = 1,000 / 1,000,000 B. 크기는 **KiB + 포함 범위**를 함께 적는다.
- "0.85MB" = "829 KiB" = ResNet-56 Conv+FC W8 848,944 B. "828 KiB"는 Stem·FC를 뺀 Conv 54개(847,872 B).

## 2. 모델

| 모델 | Conv / Block | Conv+FC weight | W8 | W4(이상치) | MAC/이미지 | 최대 activation |
|---|---|---|---|---|---|---|
| **ResNet-20 (기준)** | 19 / 9 | 268,336 | **262.05 KiB** | 131.02 KiB | **40.551 M** | 16 KiB |
| ResNet-32 | 31 / 15 | 461,872 | 451.05 KiB | 225.5 KiB | 68.863 M | 16 KiB |
| ResNet-56 (확장) | 55 / 27 | 848,944 | 829.05 KiB | 414.52 KiB | 125.486 M | 16 KiB |

포함: Conv weight + FC 640. 제외: bias·BN·재양자화 계수·정렬·metadata. 가장 큰 단일 층(3×3 64→64) 36 KiB.

## 3. ZedBoard (XC7Z020)

| 자원 | 값 | 쓰는 법 |
|---|---|---|
| BRAM36 | 140개 | 1개 = 32 Kb 데이터 + 4 Kb parity |
| BRAM raw | 630 KiB | parity 포함. 데이터 용량으로 쓰지 않는다 |
| BRAM 데이터 | **560 KiB** | fit 판단 기준. 실사용은 banking·복제·다른 IP 차감 후 더 작다 |
| DSP48E1 | 220개 (25×18) | 1 MAC/DSP 기본. WP486의 INT8 2개/DSP packing은 DSP48E2 기준이라 미검증 |
| LUT / FF | 53,200 / 106,400 | |

## 4. 저장 fit (데이터 560 KiB 기준)

| 구성 | payload | 판단 |
|---|---|---|
| ResNet-20 W8 + activation 3 slot | 262 + 48 ≈ 310 KiB | 검토 가능 (합성 전 보장 아님) |
| ResNet-56 W8 + 3 slot | 829 + 48 ≈ 877 KiB | 불가 → DDR weight 공급 |
| ResNet-56 W4 + 층 파이프라인 활성 | 414 + 123 ≈ 537 KiB | 거의 꽉 참 → 실사용 불가에 가까움 |

48 KiB는 activation 3 slot(X·H·M)의 INT8 payload만이다. weight·INT32 psum·line buffer·FIFO·DMA 버퍼는 별도.

## 5. 첫 연산 엔진

| 후보 | MAC/cycle | DSP(1 MAC/DSP) | 상태 |
|---|---|---|---|
| 8×8 | 64 | 64 | 첫 엔진 후보 |
| 8×16 | 128 | 128 | 첫 엔진 후보 |
| 16×16 | 256 | 256 > 220 | 비교군. DSP48E1 packing·LUT 곱셈기 검증 뒤에만 |

## 6. 이상적 처리량 (U=1 상한, 실측 아님)

FPS_max = P·f / N_MAC

| P | f | ResNet-20 | ResNet-56 |
|---|---|---|---|
| 64 | 100 MHz | 158 img/s (6.34 ms) | 51 img/s |
| 128 | 150 MHz | 473 img/s (2.11 ms) | 153 img/s |
| 256 (packing 전제) | 150 MHz | 947 img/s | 306 img/s |
