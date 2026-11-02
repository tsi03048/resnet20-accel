# E8-H. 패킷 끝 주소를 미리 정해 100 MHz Setup 여유 늘리기

[E8-G MAC 파이프라인](pipelined_mac.md) 다음 선택 확장입니다. 기본 이론과 작은 Conv 과제를 마친 뒤 진행하세요. 보드 없이 전체 시스템을 다시 합성·배치·배선하고 정수 회귀를 실행하는 실습입니다. 실제 PS·DDR 실행과 FPS·전력은 **NOT_RUN**입니다.

## 1. 빨라진 계산기에서 가장 느린 회로는 어디일까요?

E8-G는 계산 클록을75.92% 줄였지만, 100 MHz에서 Setup 여유가0.055 ns였습니다. 한 클록은10 ns입니다. 레지스터 사이의 계산과 배선이 너무 오래 걸리면 다음 클록에 값을 안정적으로 저장할 수 없습니다. 이 남은 시간을 Setup slack이라고 합니다.

먼저 [이전 가장 긴 경로 보고서](../results/ps_dma_pipe_system/reports/post_route_worst_setup.rpt)의 첫 경로를 읽습니다. 시작은 패킷 종류를 저장한 `stage_reg[2]`, 끝은 오류 코드의 저장 허용 신호 `error_code_reg[0]/CE`였습니다. MAC가 아닌 **DMA 패킷 끝 검사**가 가장 긴 경로였습니다. 논리12단·데이터 지연9.566 ns이고, 클록 도착 차이·Setup 요구·불확실성까지 반영한 최종 slack이0.055 ns입니다. 단순히10−9.566으로 slack을 계산하지 않습니다.

이전 회로는 매번 `현재 수신 개수 == 전체 개수 − 이번 word의 값 개수`를 계산했습니다. 종류 선택→뺄셈→비교→오류 판단이 이어졌습니다. 패킷 길이를 이미 헤더에서 알고 있으므로 **마지막 위치를 헤더 수신 때 미리 저장하고, payload 동안 같음 비교만 하도록** 바꿨습니다.

## 2. 두 종류의 마지막 위치를 구분하기

입력·Weight의32bit word 하나는 INT8 값4개입니다. bias·N·shift는 word 하나가 값1개입니다. 전송을 받은 개수 `rx_ingress`와 코어가 실제 적재한 값의 주소 `rx_index`는 다릅니다. word를 받고도 아직 꺼내지 않은 byte가 남을 수 있습니다.

| 패킷 종류 | 논리 값 개수 | word당 값 | 마지막 word 수신 직전 개수 `last_ingress` | 마지막 적재 주소 `last_scalar` |
| --- | ---: | ---: | ---: | ---: |
| 입력 | 3,072 | 4 | 3,068 | 3,071 |
| Weight | 268,336 | 4 | 268,332 | 268,335 |
| bias·N·shift 각각 | 698 | 1 | 697 | 697 |

입력의768번째 payload word가 오기 직전에는767×4=3,068개를 받은 상태입니다. 이때만 TLAST=1이어야 합니다. 그 word의 네 값을 순서대로 적재해 마지막 주소3,071까지 완료해야 다음 패킷으로 넘어갑니다. TLAST를 받았다고 즉시 마지막 세 byte를 버리면 안 됩니다.

RTL은 올바른 길이 헤더를 실제 수락한 edge에서 `last_ingress`, `last_scalar`, `packet_packed`를 저장합니다. 잘못된 헤더는 payload 상태로 가지 않습니다. BEGIN·외부 Reset·soft Reset은 이 메타데이터도 취소합니다. payload가 멈추면 끝 주소는 그대로 유지합니다.

모든 길이가 고정된 이 프로젝트의 최적화입니다. 다른 길이를 지원하려면 상수표·패킷 생성기·검증을 함께 수정해야 합니다. 임의 길이 DMA 수신기로 사용하지 않습니다.

## 3. 실제 배선 전후 비교

Vivado2025.1, XC7Z020-1CLG484, Avnet ZedBoard RevD, PS7·DDR·GP0·HP0·AXI DMA 전체 시스템입니다. 100 MHz 클록 설정·보드 정의·주소·구현 제약과 전략을 유지했습니다. false path·multicycle 예외를 새로 넣거나 클록을 늦추지 않았습니다. 네이티브 계산 코어와 RNE·정수 상수·Golden은 동일합니다.

| 배선 후 항목 | 이전 E8-G | 이번 E8-H |
| --- | ---: | ---: |
| 클록 | 100 MHz | 100 MHz |
| Setup WNS | +0.055 ns | **+0.927 ns** |
| Hold WHS | +0.018 ns | **+0.007 ns** |
| TNS / THS | 0 / 0 ns | 0 / 0 ns |
| LUT / 53,200 | 4,456 | 4,425 |
| FF / 106,400 | 5,653 | 5,655 |
| BRAM36 환산 / 140 | 87.5 | 87.5 |
| DSP / 220 | 0 | 0 |

Setup 여유는 **0.872 ns 증가**했습니다. 현재 가장 긴 Setup 경로는 Weight BRAM→곱 레지스터로 바뀌었고 논리8단·지연8.671 ns입니다. 배치·배선이 달라져 다른 경로의 지연도 달라질 수 있습니다. 위 결과를 모든 경로가0.872 ns씩 개선됐다는 뜻으로 읽지 않습니다.

**Hold 여유는0.007 ns로 작아졌습니다.** 현재 최소 Hold 경로는 DMA IP 내부의 수신 byte 개수 레지스터에서 길이 레지스터로 이어집니다. 양수여서 이번 배선에서는 통과했지만 모든 타이밍 여유가 늘었다는 뜻은 아닙니다. 기능이나 회로 배치를 바꾸면 다시 Setup·Hold·제약 검사를 수행하세요. 더 높은 주파수·여러 배치 seed의 안정성·실제 보드 동작을 보장하는 결과가 아닙니다.

시간 제약 검사12종 모두0, 배선9,361/9,361·배선 오류0, DRC Error/Critical Warning0입니다. 생성 IP Warning16건·Advisory4건은 원본에 보존합니다. [새 원본 보고서·실행 소스](../results/ps_dma_timing_system/), [배선 수집 JSON](../results/ps_dma_timing_system_actual.json), [전후 경로·자원 비교](../results/ps_dma_timing_route_comparison.json)를 함께 확인하세요.

## 4. 계산과 통신이 그대로인지 검증하기

새 수신부 `rtl/ps_dma_v3/`와 E8-G의 계산 코어 `rtl/full_e2b_fpga_v3/`를 연결합니다. [전체 RTL 실행](https://github.com/tsi03048/resnet20-accel/actions/runs/41477252578)은 정상0→1→0, Stall, 11곳 Reset 취소 후 sample1 회복을 검사합니다. 매 완료 작업61경계와 점수10개·예측을 비교하며, 완료5회의 경계 원소2,760,420개와 별도 sample0 CSV274,506행을 확인합니다. 실제 사진은 Test0/1 두 종류이고 10,000장 RTL 정확도 검사는 아닙니다.

패킷 오류8종에는 잘못된 magic·종류·길이·TKEEP·헤더 TLAST·너무 이른/늦은 payload TLAST·금지된 Weight가 들어갑니다. Golden을 고의로 바꾼4종은 실패해야 통과합니다. INT32 overflow 오류 응답, AXI-Lite 주소/데이터 도착 순서·byte strobe·응답 hold도 검사합니다. [회귀 요약](../results/ps_dma_timing_rtl_actual.json).

별도 Vivado Xsim은 byte별 외부 Reset4회, soft Reset과 데이터 수신의 동시 발생, Weight−128 오류 후 정상 길이 패킷67,087words를 끝까지 비우기, 입력3,072bytes 재적재를 검사했습니다. 관측된 payload3,095클록 동안 끝 주소 메타데이터가 헤더와 일치하는지도 확인했습니다. [추가 시험 결과](../results/ps_dma_timing_reset_actual.json). 이 인공 시험을 실제 사진 분류 작업 수에 더하지 않습니다.

정상 계산 클록은 **64,063,653클록/회**, MM2S는279,844bytes/회, S2MM은64bytes/회로 E8-G와 같습니다. 이번 개선은 클록 주기를 만족할 여유를 늘리는 작업입니다. 실행 클록 수·전송 bytes·정밀도를 줄이는 작업과 구분합니다. [실행 전후 대조](../results/ps_dma_timing_comparison.json).

## 5. 본인 환경에서 따라 하기

먼저 Python3만으로 제공된 증거와 파일 해시를 검사합니다. 이 명령은 보드나 시뮬레이터를 새로 실행하지 않습니다.

```powershell
python -m tools.check_timing_delivery
```

Windows에 Vivado2025.1을 설치했다면 저장소 루트에서 다음을 실행합니다. 기본 설치 경로는 `C:/Xilinx/2025.1/Vivado/bin/vivado.bat`이며 다른 위치는 `-VivadoPath`로 지정합니다. 스크립트는 영문 임시 경로에 소스를 복사·해시 대조한 뒤 실행하고 새 결과 폴더를 표시합니다.

```powershell
& ./board/zedboard/ps_dma_timing/run_packed_reset.ps1
python -m tools.summarize_timing_reset --run build/timing_reset_runs/표시된_실행폴더
& ./board/zedboard/ps_dma_timing/run_system.ps1
python -m tools.summarize_timing_system --run build/zedboard_ps_timing_runs/표시된_실행폴더
python -m tools.compare_timing_system
```

합성·배선·bit 생성에는 수 분 이상 걸릴 수 있습니다. 명령 종료만 보고 통과로 표시하지 말고 수집기의 verdict·Setup/Hold·자원·제약 검사와 원본 경고를 확인하세요. `compare_timing_system`은 이전 보고서와 같은100 MHz 조건인지, 계산 코어 해시가 같은지와 Setup 개선 여부까지 검사합니다. 본인 배선 수치는 위 배포 기록과 다를 수 있습니다.

Linux/WSL에서 Python+NumPy, Verilator, C++ 컴파일러·make를 준비하고 전체 정수 RTL을 재실행합니다. GPU·재학습·CIFAR 원본 다운로드는 필요 없습니다.

```bash
bash tb/ps_dma_timing/run.sh
```

원본 `results/ps_dma_timing_rtl/normal_boundaries.csv`를 Python Golden과 다시 비교하는 단계까지 포함합니다. 기능 시험·Vivado 배선의 활성 RTL10개 해시가 같아야 제공된 증거 검사를 통과합니다. 단순히 서로 다른 버전의 PASS를 모으지 않습니다.

## 6. 실습 파일과 보드 실행 준비

ZIP의 `시작.txt`에서 시작합니다. `platform_timing/output/`에는 이번 bit·XSA·배선 DCP·PS 초기화 파일, `build/ps_dma_packed_software/`에는 호환 R202 ARM ELF, `reference/ps_dma_packed/`에는 패킷6개가 있습니다. `PACKAGE_MANIFEST.json`은 모든 파일의 크기와 SHA256입니다. 제공된 ZIP을 푼 상태에서도 증거·binary 해시 검사를 수행합니다.

R202 제어 ID·주소·패킷·64byte 결과 형식과 ARM 프로그램은 그대로입니다. 기존 DMA IP loopback·ARM ELF 모델 증거는 변경하지 않은 외부 인터페이스의 이전 증거로 보존하며, 이번 새 수신부의 전체 RTL·추가 Reset·전체 시스템 배선 검증과 구분합니다.

실제 보드가 준비되면 E8-F의 revision·JTAG 부팅·전원·캐시 조건을 읽고 이번 폴더를 지정합니다. 아래 명령은 PS Reset·회로 적재·ARM 실행을 수행합니다. 현재 실물에서는 실행하지 않았습니다.

```powershell
& ./board/zedboard/ps_dma_packed/run_board.ps1 -RunDirectory ./platform_timing -Python python
```

학생 제출에는 ① 입력의3,068과3,071이 다른 이유 ② 이전 critical path의 시작·끝 ③ 새 Setup/Hold 값과 해석 ④ 정상·Stall·Reset·오류 결과 ⑤ source/bit/ELF/패킷 해시를 남기세요. 배포된 증거를 읽은 것·본인 재실행·실물 실행을 구분합니다. 기본 작은 Conv 과제와 이 선택 확장은 별도로 평가합니다. 라이선스는 팀 합의 전 보류(후보 MIT)입니다.
