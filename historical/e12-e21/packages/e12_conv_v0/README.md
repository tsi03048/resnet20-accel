# E12: 고정 Conv v0 RTL 실행 패키지

E3/E11의 작은 진단 Conv를 실제 SystemVerilog로 구현한 교육용 코드입니다.
ResNet-56 전체 가속기 또는 FPGA 보드 구현이 아닙니다.

| 항목 | 구현 범위 |
| --- | --- |
| 입력 / weight / 출력 | CHW [2,4,4] / OIHW [2,2,3,3] / CHW [2,2,2] |
| 연산 | 3×3, stride 1, padding 0, groups 1, dilation 1 |
| 수치 | signed INT8 x/w, 16-bit product, 32-bit acc, bias 한 번 |
| 후처리 | /4 RNE ties-to-even, 선택 ReLU, signed INT8 포화 |
| 순서 | co→oy→ox, 같은 출력 내부 ci→ky→kx |
| 메모리 | 같은 clock에서 request edge에 읽는 native 동기 RAM, Adapter 보관 뒤 전달 |
| 제어 | 한 job, 한 term 요청 쌍, 한 output씩; 마지막 y 수락 뒤 응답 |
| Reset | 동기 active-high, pending/valid 취소; prepared와 preload는 wrapper/testbench 책임 |

## 파일

| 파일 | 역할 |
| --- | --- |
| rtl/read_hold.sv | 동기 RAM read 결과·tag 보관 |
| rtl/mac_scalar.sv | signed 곱·누산·결과 HOLD |
| rtl/postprocess4.sv | /4 RNE·ReLU·clip·출력 HOLD |
| rtl/conv_fixed_top.sv | 고정 주소·pairing·명령/응답 제어 |
| sim/tb_conv_fixed.sv | 실제 RTL driver·RAM 모델·독립 score/주소 monitor·reset 시험 |
| reference/make_vectors.py | 기본 vector·hex·JSON 생성, Python 표준 라이브러리만 사용 |
| run.sh | lint→elaboration→C++ build→RTL simulation·VCD |
| results/ | 실행 로그·파형·도구·source hash 기록 |

## 실행

Verilator의 timing/trace 지원과 GCC C++20, make, Python 3가 필요합니다.

```sh
bash run.sh
```

Verilator 경로를 지정하려면 다음처럼 실행합니다.

```sh
VERILATOR=/path/to/verilator bash run.sh
```

검증한 빌드 경로는 GCC입니다. `-std=c++20`과 make의
`CFG_CXXFLAGS_PCH_I=-include`를 명시했습니다. 사용한 Python wheel에서
C++ 표준/PCH include 기본값이 비어 있어 필요한 설정이었습니다.
다른 compiler·설치본에서는 해당 설정을 확인하세요.
로그의 실패 종료를 무시하거나 warning을 일괄 숨기는 옵션은 사용하지 않습니다.

`results/conv_fixed.vcd`는 GTKWave 등으로 확인할 수 있습니다.
10 ns testbench clock은 이벤트 시뮬레이션의 시간 단위 설정이며 FPGA Fmax 증거가 아닙니다.

## 실제 실행 결과

기본 fixture: acc `[39,48,75,84,-19,-28,-55,-64]`;
ReLU off `[10,12,19,21,-5,-7,-14,-16]`, ReLU on `[10,12,19,21,0,0,0,0]`.

통합 시험은 기본 두 mode 2회, 무작위 60회, 포화 pattern 1회,
정상 대기 command 2회, reset 후 재시작 5회로 정상 완료 70회입니다.
추가로 5개 job을 reset으로 취소했습니다.
RAM 대기·중간 누산·출력 HOLD·응답 HOLD 등을 포함해 reset 시점을 바꿨습니다.
Standalone post 11개, MAC 3개(K=1과 gap을 둔 K=18), Read Adapter 1개도 실행했습니다.

PASS line의 accepted_terms=10245와 accepted_outputs=568에는
reset 취소 job의 이미 수락된 token도 들어 있습니다.
정상 완료 job의 출력은 70×8=560개이고, 나머지 8개는
마지막 응답 소비 전에 reset으로 취소한 job의 출력입니다.
cancel은 성공 완료 수에 더하지 않았습니다.

Source·도구 식별자는 `results/toolchain.json`, `results/source_sha256.json`에 있습니다.
도구 distribution 버전과 실행 banner가 달라 둘 다 기록했습니다.

## 확인하지 않은 범위

- 실제 FPGA 합성·target RAM/DSP 매핑·STA·배치배선·보드 실측
- 4-state X/Z propagation 검증(Verilator의 실행 모델 한계 포함)
- 임의 read latency·여러 outstanding 요청·CDC·DMA·cache·AXI
- 실제 Stem shape/padding, Residual Block, ResNet checkpoint·정확도·FPS
- 지원 범위 밖/overflow를 일으키는 bias의 제품 오류 처리
- E11 모든 directed/random 조합의 포괄적 coverage 또는 formal proof

입력/weight/bias는 job 중 변경하지 않는 계약입니다.
prepared는 외부 wrapper가 preload·reset 상태에 맞게 관리해야 합니다.
완료는 Core의 y sink 경계이며 외부 메모리/DMA/CPU 가시성 완료가 아닙니다.
현재 통과 범위만 RTL 실행 증거로 사용하고 전체 제품 완료로 확대하지 마세요.
