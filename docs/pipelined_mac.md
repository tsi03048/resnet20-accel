# E8-G. MAC 파이프라인 — 계산을 겹쳐 기다리는 클록 줄이기

[E8-F 묶음 DMA](packed_dma.md) 다음 선택 확장입니다. 작은 Conv 기본 과제를 마친 뒤 읽으세요. 이번에는 같은 정수 계산을 여러 단계에 걸쳐 겹쳐 진행합니다. 보드 없이 수행했으며 실제 PS·DDR 실행과 FPS·전력은 **NOT_RUN**입니다.

## 1. 먼저 네 출력으로 이해하기

MAC는 `부분합 ← 부분합 + 입력 × Weight`입니다. Stem 출력 한 개는 3채널×3×3=27항을 순서대로 더합니다. 기존 회로는 한 항을 처리하는 여섯 단계를 모두 마친 뒤 다음 항을 시작했습니다. 새 회로는 주소·메모리 읽기·곱셈·누산 단계를 겹칩니다. 파이프라인이 찬 뒤에는 매 클록 다음 곱을 더할 수 있습니다.

| 단계 | 하는 일 | 함께 전달하는 정보 |
| --- | --- | --- |
| A | 입력·Weight 주소 만들기 | padding 안쪽 여부, 마지막 항 여부 |
| B | BRAM 읽기 요청 | 유효 여부, 마지막 항 여부 |
| C | 입력과 Weight 읽기 시점 맞추기 | padding이면 입력0 |
| D | signed INT8×INT8 → signed16 곱 | 마지막 항 여부 |
| E | 곱을 signed32 부분합에 순서대로 더하기 | INT32 범위 확인, 마지막 합 뒤 후처리 시작 |

단계가 다섯 개여도 항당 다섯 클록씩 직렬 실행하는 것은 아닙니다. K항 출력 하나의 MAC 구간은 기존 `6K`에서 **`K+4`클록**으로 바뀝니다. 27항은 162→31클록입니다. 계수 읽기·RNE·결과 저장·Add 등의 시간은 별도로 남습니다. 모델 전체가 여섯 배 빨라진다고 계산하면 안 됩니다.

## 2. 가장 작은 실습

Python 3과 Vivado 2025.1이 있는 Windows PowerShell에서 저장소 루트를 현재 폴더로 엽니다. 이 시험에는 GPU·PyTorch·CIFAR 다운로드가 필요 없습니다.

```powershell
python -m tools.pipe_probe_vectors --export
& ./board/zedboard/ps_dma_pipe/run_probe.ps1 -Python python
```

스크립트 마지막에 표시된 `build/pipe_probe_runs/probe_...` 폴더를 확인합니다. `mac.csv`의 열은 출력 번호·항 번호·곱·더하기 전 부분합·더하기 후 부분합입니다. 입력은 `i%8−4`, Weight는 `i%7−3`, bias=7, N=3, shift=2인 **인공 예제**입니다. 실제 사진 분류 시험과 구분합니다.

| Stem의 맨 윗줄 출력 위치 | 0 | 1 | 2 | 3 |
| --- | ---: | ---: | ---: | ---: |
| bias를 포함한 마지막 부분합 | 17 | 14 | 11 | 8 |
| RNE(부분합×3/4), ReLU 후 code | 13 | 10 | 8 | 6 |

출력0은 `17×3/4=12.75→13`, 출력1은 `14×3/4=10.5→10`입니다. 정확히 중간이면 짝수로 반올림합니다. 독립 Python 정수·Fraction 기준으로 **108개의 곱과 순서별 부분합 전부**를 비교했습니다. compute Stall27회·trace Stall4회와 정지한30개 edge도 확인했습니다. [시험 결과](../results/pipe_probe_actual.json), [원본 CSV](../results/pipe_probe/mac.csv)를 읽어보세요. 재실행 CSV는 아래처럼 다시 비교합니다.

```powershell
python -m tools.pipe_probe_vectors --trace build/pipe_probe_runs/probe_날짜_시간/mac.csv
```

## 3. 숫자가 같도록 지킬 규칙

발행 번호 `issue_idx`는 주소를 만든 항, 완료 번호 `term_idx`는 실제 누산한 항입니다. 파이프라인 안에 진행 중인 항이 있으므로 두 번호는 다릅니다. 마지막 주소 발행 후에도 마지막 곱이 누산될 때까지 기다립니다. padding의 곱0도 원래 순서의 한 항으로 통과시킵니다.

곱셈은 `$signed(pair_x)*$signed(weight_q)`로 명시합니다. GAP의 부호 확장 concat과 곱셈을 하나의 조건식에 섞으면 조건식의 unsigned 문맥이 음수 곱에 영향을 줄 수 있습니다. 실제 첫 정수 비교에서 발견한 문제를 분기별 대입으로 수정했고, 위 음수·부분합 시험과 전체 경계 비교로 확인합니다.

부분합은 항마다 33bit로 계산해 INT32 범위를 검사하고, 통과한 값만 저장합니다. 병렬로 합치는 순서를 바꾸거나 중간 overflow를 숨기지 않습니다. Conv2의 ReLU 생략, stride2·Option A, GAP 평균을 포함한 계수, FC signed32 점수와 동점 시 작은 class 선택은 E2-B 기준 그대로입니다.

Stall은 누산기만 멈추면 안 됩니다. 주소·valid·마지막 항·padding 여부·feature BRAM 출력·Weight BRAM 두 단계와 bank 선택까지 같은 CE로 멈춥니다. 메모리 출력만 움직이면 다시 시작할 때 다른 항을 곱할 수 있습니다. 별도 시험은 Conv 중간·마지막 항 drain·GAP에서 이 전체 상태를 비교합니다. Reset은 파이프라인 valid를 취소하고, 다음 BEGIN 뒤 전부 재적재합니다. BRAM payload를 Reset으로 지우지는 않습니다.

## 4. 전체 모델 검증과 클록 비교

전체 실행은 30작업을 실제 입력·Weight·계수 적재부터 64byte 점수 응답까지 이어갑니다. Linux/WSL에서 Python+NumPy, Verilator, C++ 컴파일러와 make를 준비하고 실행합니다.

```bash
bash tb/ps_dma_v3/run.sh
```

정상0→1→0, Stall 작업, Reset 취소 후 sample1 회복 작업을 검사합니다. 각각61경계, 총2,760,420개 경계 원소와 최종 점수10개·예측을 비교합니다. 별도 Python으로 sample0 CSV274,506행도 Golden과 다시 비교합니다. 실제 입력은 Test0/1 두 종류이며 10,000장 RTL 정확도 검사는 아닙니다. sample0은 class3(cat), sample1은 class8(ship)입니다.

Reset 취소 위치는 partial header·partial Weight·계수 읽기·pipeline fill/full/drain·순차 곱셈·RNE·Stem·Transition·partial S2MM의11곳입니다. 잘못된 Golden4종은 실패해야 통과하며, INT32 overflow·잘못된 패킷8종·AXI-Lite 주소/데이터 도착 순서와 응답 hold도 확인합니다. [실제 실행](https://github.com/tsi03048/resnet20-accel/actions/runs/41463318569)의 summary 성공과 [수집 결과](../results/ps_dma_pipe_rtl_actual.json)를 함께 확인하세요.

| 실제 정상 실행 3회의 계산 클록 | 이전 E8-F | 이번 E8-G |
| --- | ---: | ---: |
| sample0 → sample1 → sample0, 각각 | 266,085,373 | **64,063,653** |
| 감소 클록 / 감소율 | — | **202,021,720 / 75.92%** |
| 이전 클록 ÷ 새 클록 | — | **4.15345** |

예측값과 실제 정상3회가 모두 정확히 일치합니다. 이는 같은100 MHz에서 코어 계산 시간이 약4.15배 짧아졌다는 시뮬레이션 결과이며 보드 전체 처리량 측정이 아닙니다.

클록 모델은 각 출력의 K와 개수를 graph에서 읽어 줄어드는 MAC 구간만 계산합니다. `python -m tools.pipe_cycle_model`로 예측을 읽고 [실측 시뮬레이션 대조](../results/ps_dma_pipe_comparison.json)와 비교합니다. DMA 적재·PS 명령·결과 회수 시간이 제외된 코어 계산 클록입니다.

## 5. ZedBoard 전체 회로

Vivado 2025.1, XC7Z020-1CLG484, Avnet ZedBoard RevD 설정으로 PS7·DDR·GP0·HP0·AXI DMA 전체 회로를 다시 합성·배치·배선하고 bit/XSA를 생성했습니다.

| 배선 후 항목 | 측정값 |
| --- | ---: |
| FCLK | 100 MHz |
| LUT | 4,456 / 53,200 |
| FF | 5,653 / 106,400 |
| BRAM36 환산 | 87.5 / 140 |
| DSP | 0 / 220 |
| Setup WNS / Hold WHS | +0.055 / +0.018 ns |
| TNS / THS | 0 / 0 ns |
| 배선 완료 | 9,381 / 9,381 |

시간 제약 검사12종 모두0, DRC Error/Critical Warning0입니다. 생성 IP Warning16건·Advisory4건을 원본에 보존했습니다. Setup/Hold 여유가 작으므로 수정 후에는 반드시 다시 배선하고 확인합니다. 통과 결과를 임의의 더 높은 주파수 보장으로 해석하지 않습니다. [원본 보고서·실행 소스](../results/ps_dma_pipe_system/), [수집 JSON](../results/ps_dma_pipe_system_actual.json).

```powershell
& ./board/zedboard/ps_dma_pipe/run_system.ps1
python -m tools.summarize_pipe_system --run build/zedboard_ps_pipe_runs/표시된_실행폴더
python -m tools.check_pipe_delivery
```

마지막 명령은 제공된 증거와 현재 파일 해시를 대조하며 시뮬레이터나 보드를 새로 실행하지 않습니다. 전체 RTL과 Vivado에 사용한 **활성 RTL 해시가 같아야** 통과합니다. Golden·단위 시험·배선 결과 중 하나만 통과해서는 충분하지 않습니다.

## 6. 전송 규약과 보드 실행 준비

R202 packed DMA 인터페이스·주소·패킷·ARM 프로그램은 E8-F와 동일합니다. 이미지당 MM2S **279,844bytes**, 논리 값273,502개, 응답64bytes입니다. 이번 변경은 전송 bytes를 더 줄이는 작업이 아닙니다. 이전 DMA IP loopback·byte lane Reset·ARM ELF 모델 증거는 수정하지 않은 동일 경로의 기존 증거로 보존하고, 이번 전체 RTL 및 Vivado 검증과 구분합니다.

실습 ZIP의 `platform_pipe/output/`에 이번 bit·XSA·DCP·PS 초기화 파일, `build/ps_dma_packed_software/app.elf`에 호환 R202 프로그램, `reference/ps_dma_packed/`에 패킷6개가 있습니다. 함께 제공된 binary hash를 검사하세요. 이 저장소의 이전 `platform_packed` bit와 이번 측정값을 혼합하지 않습니다.

보드가 준비된 뒤 E8-F의 revision·부팅·전원·JTAG·캐시 조건을 확인하고 아래 명령을 실행합니다. 이 명령은 PS Reset·회로 적재·ARM 프로그램 실행을 수행합니다. 현재 보드에서는 실행하지 않았습니다.

```powershell
& ./board/zedboard/ps_dma_packed/run_board.ps1 -RunDirectory ./platform_pipe -Python python
```

처음 배우는 팀원은 ① MAC 한 항과 부호 ② 네 출력의108항 CSV ③ 파이프라인 fill/drain·Stall ④ 전체61경계 ⑤ 전체 시스템 타이밍 순서로 설명하고 재실행 결과를 제출하면 됩니다. 기본 과제의 작은 Conv와 이 선택 확장을 분리해서 평가합니다. 프로젝트 라이선스는 팀 합의 전 보류(후보 MIT)입니다.
