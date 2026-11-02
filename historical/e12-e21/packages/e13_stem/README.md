# E13 · Static Conv3×3 Stem extension

교육용 RTL이다. 목표 ResNet-56 CIFAR-10의 Stem과 같은 shape를 사용하지만 실제 checkpoint/BN folding/채널별 multiplier는 아직 연결하지 않았다.

## 실행

```bash
VERILATOR=/path/to/verilator bash run.sh
```

Verilator, GCC C++20, make, Python3가 필요하다. 표준 설치에서는 `bash run.sh`로 실행한다. 사용 환경의 PyPI distribution은 verilator 5.48.0, binary --version은 rev vUNKNOWN-built20260516-4e853d8, simulation banner는 Verilator5.49였다. E12에서 설치한 도구를 재사용했다. 배포 패키지에 도구 바이너리는 포함하지 않았다.

`reference/make_vectors.py`는 모든 출력의 INT32 acc/INT8 code를 독립적인 좌표 loop로 생성한다. 정수 RNE는 부호/절댓값/몫/나머지 방식으로 계산한다. RTL은 shift와 lowbit를 사용한다. `run.sh`는 RTL-only -Wall lint 두 구성, 생성/빌드, 전체 simulation 두 구성, 별도 첫 구간 VCD 실행을 수행한다. 경고를 전역 무시하지 않는다. C++20/PCH 옵션은 이번 wheel 환경에 맞춘 GCC 설정이다.

## 고정 계약

- N1, CHW/OIHW, signed8 input/weight, 16-bit product, INT32 acc, bias/output당1회.
- Kernel3×3, stride1, groups1, dilation1. Shape/PAD는 elaboration parameter이며 runtime descriptor가 아니다.
- 후처리 `/4 RNE ties-to-even -> optional ReLU -> signed INT8 saturation`. Overflow 없는 bias 범위가 전제다.
- 모든 zero point0. Padding MAC input은0이며 해당 input RAM read를 발행하지 않는다. Weight read와 논리 term은 유지한다.
- 같은 clock native synchronous RAM read. Adapter가 다음 edge에서 capture한다. 임의 latency/CDC 불가.
- command에서 bias 배열/ReLU latch. 입력/weight는 job 중 변경 금지. prepared는 외부가 관리한다.
- 마지막 y가 수락된 뒤 response. 응답 backpressure 동안 새 command 거부. Reset은 작업 취소, 외부 memory 초기화 아님.

## 시험

Stem [3,32,32] -> [16,32,32], PAD1, K27, 16,384output.
4개의 vector: ones/모서리, signed random, 같은 random+ReLU, signed extreme/포화.
이후5개 위치 reset 취소와 signed random 전체 재시작1회: 정상5회, 취소5회.
각 job: 442,368논리 term/weightread, 424,128실제 inputread, 18,240padding term. 모서리64·비모서리 가장자리1,920·내부14,400output.
추가 E12 [2,4,4] -> [2,2,2], PAD0, K18의 두 ReLU mode: 정상2회.

선택 시험의 주소/tag/term/acc/code/index/last/stall/response/reset을 비교한다. source revision별 실제 계수는 results/simulation_*.log와 summary.json에 보존한다. 취소된 job에서 이미 수락한 token은 전체 accepted 계수에 들어가지만 정상 완료 수에는 넣지 않는다.

## 파형

`stem_first_window.vcd`는 별도 실행의 처음40us만 담는다. TRACE WINDOW ONLY는 전체 regression PASS가 아니다. 전체 회귀는 trace 없이 실행하며 simulation_0/1.log가 그 근거다. GtkWave에서 `dut`의 state/좌표/padding/tag/adapter/mac/post를 펼쳐 볼 수 있다. 10ns testbench clock이나 Host simulation 시간은 FPGA 성능이 아니다.

## 제한

검증된 parameter 조합은 위 두 개다. 16-bit address/index/tag의 구성 범위 내 다른 조합은 별도 검증해야 한다. 동적 shape/stride2/OptionA/Residual/DMA/실제checkpoint/정확도/4-state X/Z/FPGA 합성/BRAM mode/배치배선/timing/보드는 미검증 또는 미지원이다. 이 코드는 제품용 오류 CSR·미완료 preload 검출기·안전한 bias 범위 검사기를 구현하지 않았다.

`verify_missing_reference.py`는 기준 파일 하나를 잠시 감추고 실제 simulator가 즉시 실패하는지 검사한 뒤 반드시 복원한다. `run.sh`도 이 음성 시험과 `record_results.py`의 로그/해시 기록을 수행한다. 전체 회귀 PASS와 별도 실패경로 확인이다.
