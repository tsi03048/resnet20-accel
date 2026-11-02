# ZedBoard 기본 보드 실습 — 작은 Conv를 JTAG로 확인

기준 part는 **XC7Z020-1CLG484**, Vivado 표기는 `xc7z020clg484-1`이다.
현재 자료는 실행 준비용이며 **실제 Vivado 합성·배치배선·보드 프로그래밍은 미실행**이다.
보드 wrapper의 시뮬레이션은 실제 VIO IP·JTAG·핀·timing 검증을 대체하지 않는다.

## 1. 준비

- ZedBoard와 전원, JTAG USB 연결, 해당 장치를 지원하는 Vivado.
- 저장소 최상위에서 `vivado -mode batch -source board/zedboard/build_basic.tcl`.
- 스크립트가 RTL·Y9 100 MHz 입력 제약·VIO IP를 구성하고 bitstream·보고서를 생성한다.
- 현재 Vivado에서 IP 구성 오류가 나면 그 메시지를 기록하고 멈춘다. 확인 없이 PASS로 적지 않는다.

핀 근거는 [Digilent Zedboard-Master.xdc](https://github.com/Digilent/digilent-xdc/blob/master/Zedboard-Master.xdc)의 GCLK(Y9)다.
Arty Z7-20은 동일 PL 계열이어도 이 XDC·보드 프로젝트를 그대로 사용하지 않는다.

## 2. 데이터와 실행

이번 X/W는 `conv_toy.sv`의 고정 ROM 예제다. PS·DDR·DMA와 외부 파일 적재가 필요 없다.
`basic_vio_top.sv`가 y_valid/y_ready에서 4개 32-bit 결과를 저장한다.

Vivado Hardware Manager에서 장치를 연결하고 생성된 **동일 빌드의 .bit와 .ltx**를 선택한다.
VIO 창을 열고 아래 신호를 추가한다. 표시 이름이 번호이면 폭과 연결을 확인한다.

| VIO 신호 | 의미·사용법 |
|---|---|
| probe_out1 | reset_request. 1을 commit한 뒤 0으로 commit |
| probe_out0 | start. 0→1을 commit한 뒤 0으로 commit; busy 중 시작 금지 |
| probe_in0~3 | result0~3. signed decimal로 표시하면 10,9,8,6 |
| probe_in4 | {busy,completed}. 완료 후 binary 01 |
| probe_in5 | stored mask. 완료 후 binary 1111 |

처음 start=0/reset=0인지 확인한다. 초기 전원 reset이 끝난 후 start의 상승을 준다.
네 값이 보여도 mask·완료를 함께 확인한다. reset 후 mask·완료가 0이 되고 재실행되는지 확인한다.

## 3. 제출·통과 기준

- 실행자·날짜·소스 hash·Vivado 버전·실제 part·보드 revision.
- Hardware Manager의 4개 결과·mask·완료 캡처와 텍스트 기록.
- utilization.rpt·timing.rpt, unconstrained path와 setup/hold·pulse-width 위반 검토.
- 같은 빌드의 bit/ltx, reset→재실행 결과.

출력 10,9,8,6·mask1111·완료01이 맞고 timing·미제약 경로 문제가 해소되어야 S6 통과다.
100 MHz는 제약 목표이며 실측 성능이 아니다. 전체 CNN·CIFAR 정확도·DMA 성능을 입증하지 않는다.

## 4. 범위

기본 보드는 ROM fixture를 사용한다. 실제 모델 Block으로 확장할 때는 E2-B 상수·입력 적재·주소 범위·출력 회수 규약을 추가한다.
[기존 E12~E21 자료](../docs/historical/e12-e21/README.md)는 원본 ZIP·소스·로그 이관을 완료했다. 전체 모델·실물 보드 실행은 별도 미완료 항목이다.

