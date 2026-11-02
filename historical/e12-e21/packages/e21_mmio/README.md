# E21. Loader를 레지스터로 제어하기

E20의 native Loader 앞에 custom 32-bit MMIO endpoint를 붙였다. **같은 clock의 단일 outstanding request/response 계약**이다. 실제 CPU·APB·AXI·SoC·FPGA 연결은 후속 범위다. 출력 tensor는 기존 ready/valid stream으로 전달한다. CPU가 출력 tensor를 read32로 꺼내는 장치는 이번에 구현하지 않았다.

## 1. 레지스터를 왜 두는가?

CPU 프로그램은 `begin_valid` 같은 RTL 신호를 직접 조작하지 않는다. 특정 주소에 숫자를 쓰면 회로가 설정을 보관하거나 명령을 실행하도록 만든다. 이를 Memory-Mapped I/O(MMIO)라고 부른다. 여기서는 그 주소 공간의 내부 endpoint부터 검증한다.

**주소는 byte offset, 접근 단위는 32 bit, 정렬은 4 byte**다. 외부 SoC는 별도로 base address를 선택하고 상위 주소를 decode해야 한다. 입력 주소 폭은 12 bit이며 상위 CPU 주소를 잘라서 무조건 전달하면 alias 문제가 생길 수 있다.

| 개념 | 의미 | 이번 구현 |
| --- | --- | --- |
| CSR/Register | 설정·상태를 보관하는 작은 저장소 | generation, shape, digest 등 |
| Shadow | 다음 명령에 쓸 설정 | 실행 중에도 수정 가능 |
| Active | BEGIN에서 Loader가 받은 식별값 | 별도 읽기 주소 제공 |
| Doorbell | 쓰면 동작을 촉발하는 레지스터 | COMMAND |
| Readback | 보관된 값을 다시 읽음 | 설정/상태/식별값/횟수 |
| Outstanding | 요청은 받았지만 응답 소비가 끝나지 않은 작업 | 최대 1개 |

## 2. 요청과 응답은 언제 한 번인가?

상승 edge에서 `req_fire = req_valid && req_ready`일 때만 주소·쓰기 여부·데이터·strobe를 수락한다. `req_ready = !rst && !rsp_valid`다. 요청 수락 edge에서 해당 동작을 실행하고 응답 레지스터를 채운다. 다음 cycle에 `rsp_valid`가 보인다.

`rsp_valid && !rsp_ready`인 동안 응답의 data/code와 valid를 유지한다. 이 동안 req_ready=0이라 같은 요청을 계속 제시해도 명령을 다시 실행하지 않는다. 응답을 소비한 edge에는 새 요청을 받지 않는 bubble이 있다. 성능보다 경계의 명확성을 우선한 교육용 구조다.

요청자는 수락되지 않은 요청의 payload를 유지해야 한다. 응답을 받은 뒤에도 valid를 유지해 다음 req_ready에서 다시 handshake하면 **새 요청**이다. 같은 명령을 자동으로 deduplicate하는 transaction ID는 없다.

## 3. Register map

| Offset | 이름 | 접근 | 의미 |
| --- | --- | --- | --- |
| 0x000 | COMMAND | W | 1 BEGIN, 2 WRITE_ONE, 3 COMMIT, 4 START, 5 ACK_DONE |
| 0x004 | STATUS | R | bit1 prepared, bit3 busy, bit4 done, bit5 Loader error, bit8:6 Loader error_code; 나머지 0 |
| 0x008 | GENERATION | RW | BEGIN에서 사용할 generation |
| 0x00C | CMD_GENERATION | RW | START에서 비교할 generation |
| 0x010 | SHAPE | RW | bits15:0 C, bits31:16 H |
| 0x014 | HOST_VALIDATED | RW | 0 또는 1; software의 검증 주장 |
| 0x018 | WRITE_SELECTOR | RW | bits19:16 role, bits15:0 element address; 상위12 bit=0 |
| 0x01C | WRITE_DATA | RW | 32-bit raw transport word |
| 0x020 | ACTIVE_GENERATION | R | BEGIN에서 받은 identity |
| 0x024 | NATIVE_WRITE_COUNT | R | 이번 BEGIN 이후 native write handshake 횟수 |
| 0x040~0x05C | SHADOW_DIGEST[0~7] | RW | 낮은 offset이 digest의 하위32 bit |
| 0x060~0x07C | ACTIVE_DIGEST[0~7] | R | BEGIN에서 받은 digest |

모든 쓰기는 `wstrb=0xF`만 허용한다. Byte write를 합쳐주는 기능은 없다. COMMAND 읽기, R-only 쓰기는 오류다. digest가 `256'h...AABBCCDD`로 끝나면 0x040에 0xAABBCCDD를 쓴다. CPU byte endianness는 외부 bus bridge가 별도로 맞춰야 한다.

WRITE_SELECTOR의 element address는 byte address가 아니다. role0의 주소1은 두 번째 Input 원소다. role 순서와 각 role 길이는 E20과 같다: Input, Weight1, Weight2, Bias1, Bias2, N1, N2, Nm, Ns, s1, s2, sa. INT8 -2는 WRITE_DATA=0x000000FE, INT32 Bias -2는 0xFFFFFFFE다.

## 4. 오류는 두 층으로 나누어 읽는다

| rsp_code | 원인 | side effect |
| --- | --- | --- |
| 0 | endpoint가 해당 접근/명령을 수락 | native handshake가 발생할 수 있음 |
| 1 | 비정렬·미정의 주소 | 없음 |
| 2 | partial write strobe | 없음 |
| 3 | 허용하지 않는 읽기/쓰기 방향 | 없음 |
| 4 | native ready가 아닌 상태의 명령 | 없음; 기다리지 않고 거부 |
| 5 | 미정의 명령 또는 shadow 필드의 표현 범위 오류 | 없음 |

예: Input을 한 개도 적재하지 않고 COMMIT을 쓰면 LOAD 상태이므로 native Commit handshake 자체는 가능하다. 따라서 MMIO rsp_code=0이다. 하지만 Loader는 전체 role을 받지 못했으므로 STATUS.error=1, error_code=5로 전이한다. **버스 응답 성공과 의미 검증 성공은 다르다.**

Loader error_code는 E20 그대로다: 1 host claim 없음, 2 role/order, 3 element address, 4 값 범위, 5 incomplete Commit, 6 generation mismatch, 7 fixed shape mismatch. BEGIN은 오류 상태에서 새 session을 열 수 있다.

START 이전에는 prepared와 active identity를 확인한다. START 성공 뒤 prepared는 내려가고 busy가 올라간다. 최종 결과 stream을 모두 수락하고 Core 완료가 도착하면 done이 올라간다. done은 ACK_DONE 또는 reset까지 유지된다. ACK_DONE을 수락한 뒤 IDLE이며 다음 실행은 전체 재적재한다.

## 5. CPU 관점의 한 작업

1. E19 방식으로 파일을 검증하고 메모리에 정수 Snapshot을 만든다.
2. shadow에 generation·shape·host claim·digest를 쓴다.
3. BEGIN을 쓰고 MMIO response와 STATUS 오류를 모두 확인한다.
4. ACTIVE_GENERATION·ACTIVE_DIGEST를 읽어 이번 session을 확인한다.
5. 각 원소마다 SELECTOR → DATA → WRITE_ONE을 쓴다. 모든 MMIO 응답을 기다린다. STATUS로 의미 오류도 확인한다.
6. NATIVE_WRITE_COUNT를 계획한 원소 수와 비교한다.
7. COMMIT → STATUS.error=0 및 prepared=1을 확인한다.
8. CMD_GENERATION을 맞추고 START를 한 번 쓴다. 별도의 출력 stream 소비자를 동작시킨다.
9. STATUS.done을 bounded polling한 뒤 ACK_DONE을 쓴다.

`software/driver_example.py`는 이 순서의 예제이며 실제 OS MMIO backend는 제공하지 않는다. real CPU에서 필요한 ordered access·barrier·device memory mapping은 플랫폼 결정 후 추가한다. 단순한 volatile pointer가 모든 플랫폼의 순서 규약을 해결한다고 가정하지 않는다.

Timeout은 명령이 실행되지 않았다는 증거가 아니다. 요청을 받은 직후 응답을 잃을 수도 있다. 무조건 START를 재시도하지 말고 session을 조회하거나 bus와 core를 함께 reset/drain한 후 재적재한다. 이 endpoint는 transport replay protection을 제공하지 않는다.

## 6. Readback으로 확인할 수 있는 범위

Shadow readback은 설정 레지스터의 값, Active readback은 BEGIN에서 받은 identity, count는 native 수락 횟수를 확인한다. **Weight/Bias 전체 메모리 readback이나 hardware hash는 아니다.** 값이 유효 범위 안에서 다른 값으로 전송되면 이를 검출하지 못할 수 있다. Native count에는 의미 검증에서 거부된 write handshake도 포함된다.

실행 중 shadow 변경은 허용하되 현재 Loader의 active identity는 바뀌지 않는다. Begin/Write/Commit은 RUN/RESP에서 거부한다. Busy=0만 보고 새 BEGIN을 보내면 RESP에서 거부될 수 있다. done·ACK_DONE 경계를 함께 보아야 한다.

Reset은 pending MMIO response와 shadow, Loader/Core 제어를 함께 지운다. RAM 전체를 0으로 지우는 의미는 아니다. 상위 bus가 reset 이전 응답을 뒤늦게 전달하지 않도록 외부 bridge의 reset 계약도 필요하다.

## 7. 검증과 재현

`run.sh`는 C=2,H=4와 C=16,H=32의 RTL -Wall lint, elaboration, C++ build, simulation을 수행한다. Verilator가 PATH에 없으면 VERILATOR 환경변수로 지정한다.

- 작은 /4 호환·varied 두 정상 작업, Stage1→2 varied 한 작업의 Y를 E20 기준값과 index/last까지 비교한다.
- 응답 stall 동안 request를 유지하고 data/code/valid 안정성, req_ready 차단, native write count, 실제 Core Start 횟수를 확인한다.
- 주소·strobe·방향·opcode·필드·상태 오류를 거부한다.
- incomplete Commit·INT8 transport 범위 오류를 STATUS에서 확인하며, 작은 구성은 generation mismatch도 확인한다.
- 부분 session과 미소비 MMIO response가 있는 상태의 reset 후 stale 응답·shadow·active identity가 제거되는지 확인한다.
- 실행 중 shadow 변경과 active identity 분리를 확인하고 출력에 stall을 넣는다.

최종 실제 횟수는 results/summary.json과 simulation_*.log에 기록한다. E21의 새 scoreboard는 bus 경계와 최종 Y를 본다. E20의 전체 중간값 scoreboard를 그대로 재실행했다는 뜻은 아니다. 상속된 Loader/Core RTL의 동일성은 source hash로 기록한다.

Verilator의 주된 2-state simulation, 선택한 vector와 stall pattern에 대한 결과다. X 전파·CDC·실제 bus timing·FPGA 합성·STA·보드·실제 checkpoint 정확도는 미검증이다.

## 8. 다음 단계

이 endpoint를 실제 APB 또는 AXI-Lite의 주소/데이터/응답 channel로 연결한다. 특히 bridge에서 이미 수락한 요청이 native 명령으로 정확히 한 번 전달되고, bus wait/error/reset 중 완료 경계가 유지되는지 검증한다. 출력 tensor의 CPU readback 또는 DMA 경로는 제어 레지스터와 별도 data-plane 작업으로 이어간다.
