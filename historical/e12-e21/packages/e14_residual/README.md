# E14 · Sequential Identity Residual Block

하나의 E13 Conv Core를 Conv1/Conv2에 순차 재사용하는 교육용 RTL이다. X=A, H=B, M=C, Y=B로 세 activation 영역을 사용한다. 파일 내 이름은 xmem/amem/fmem이다.

```bash
VERILATOR=/path/to/verilator bash run.sh
```

필요 도구/버전은 E13과 같다: Verilator, GCC C++20, make, Python3. PyPI distribution5.48.0, --version rev vUNKNOWN-built20260516-4e853d8, simulation banner5.49. C++20/PCH 옵션은 사용한 wheel의 GCC 환경에 맞춘 설정이다. 도구는 미포함이다.

## 수치 계약

- H = sat8(ReLU(RNE(acc1/4))), M = sat8(RNE(acc2/4)). Conv2 뒤에는 ReLU를 두지 않는다.
- Y = sat8(ReLU(signextend9(M) + signextend9(X))). Add 중간 범위 -256..254.
- X/H/M/Y는 같은 activation scale S, zero point0. Weight scale1/4, bias 단위S/4. 따라서 각 Conv acc를4로 나눈 code가 다시 activation 단위S다.
- 이는 diagnostic contract다. 실제 checkpoint/BN folded weight/perchannel multiplier·Add scale alignment를 연결한 것은 아니다. E4의 /2 예제와는 다른 /4 vector다.
- Kernel3, stride1, PAD1, groups1, dilation1. Identity와 같은 shape만 지원한다.

## 저장·제어 계약

- load_sel0=X,1=W1,2=W2. load_we && load_ready edge에서만 write한다. load_addr는 element 주소이며 유효 범위만 사용한다.
- prepared는 외부가 모든 input/weight/bias 준비 상태를 보증하는 입력이다. 내부 load-valid tracker는 없다.
- Cmd fire 때 bias1/2를 모두 latch한다. load와 cmd를 같은 edge에 수락하지 않으며 busy/response 동안 load_ready0.
- Conv1 X->B, Conv2 B->C, Add X/C->B. 각 Conv의 최종 저장과 response 수락이 끝난 뒤 다음 단계로 진행한다.
- Add는 동기 read data를 별도 register에 잡고 다음 edge에서9-bit 합/후처리를 만든다. y stall 동안 code/index/last를 보관한다.
- y fire edge에 B에Y를 저장한다. 마지막Y의 local write와 sink수락 후 response를 낸다. CPU/DDR/DMA completion이 아니다.
- Reset은 제어/valid/pending/진행 취소다. 배열 전체를 지우지 않으며 외부는 prepared를 내리고 재준비해야 한다. 취소된 부분결과를 완료tensor로 쓰지 않는다.

## 시험과 파일

small: C2 H4, N32, K18. Negative-main witness, random, Add254 saturation, Add-256/ReLU, 연속 재사용, 5위치reset, 복구를 검사한다.
full: C16 H32, N16,384, K144. Negative-main vector와random의 두 전체block을 검사한다. 각Conv2,359,296논리term, block당4,718,592항.

Python은 Conv1 acc/H, Conv2 acc/M, 최종Y를 각각 생성한다. TB는 두Conv의 주소/tag/누산/중간값, Addpair, y/index/last/hold, X보존, B의H->Y재사용, local write, response 순서까지 비교한다. 정상 완료와reset취소의 수락계수는 분리해 해석한다.

results/simulation_0/1.log는 전체 회귀다. small_block_window.vcd는 별도 실행의 처음100us로, 전체회귀PASS를 대체하지 않는다. reference에 전체정수 기대값과 vector별summary가 있다. results/source_sha256.json은 source/vector identity다.

## 제한

합성·BRAM inference/포트·read-during-write·STA·보드·실제checkpoint/accuracy·전체모델은 미검증이다. 단일clock behavioral memory를 사용한다. Static size이며 dynamic descriptor, stride2/OptionA/Transition, perchannel rescaling, 오류CSR, DMA/CDC는 미지원이다. Full size의 실험도 실제모델 정수일치 또는FPGA성능 증거가 아니다. 테스트하지 않은 조합/seed/임의32bitbias를 일반화하지 않는다.

`verify_missing_reference.py`는 기준 파일 하나를 잠시 감추고 실제 simulator가 즉시 실패하는지 검사한 뒤 반드시 복원한다. `run.sh`도 이 음성 시험과 `record_results.py`의 로그/해시 기록을 수행한다. 전체 회귀 PASS와 별도 실패경로 확인이다.
