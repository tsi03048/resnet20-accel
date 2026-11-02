# E12 고정 Conv v0 — 실제 실행한 source와 결과

원래 파일별로 저장할 수 있도록 각 코드 블록에 파일 이름을 적었습니다. 실제 실행 범위와 미검증 범위는 README를 따릅니다.


## README.md

````text
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

````


## rtl/read_hold.sv

````systemverilog
`timescale 1ns/1ps
`default_nettype none
module read_hold #(parameter AW=5, TW=8)(
    input wire clk, rst,
    input wire req_valid, output wire req_ready,
    input wire [AW-1:0] req_addr, input wire [TW-1:0] req_tag,
    output wire ram_en, output wire [AW-1:0] ram_addr,
    input wire [7:0] ram_data,
    output wire rsp_valid, input wire rsp_ready,
    output reg [7:0] rsp_data, output reg [TW-1:0] rsp_tag
);
    localparam IDLE=2'd0, WAIT_RAM=2'd1, HOLD=2'd2;
    reg [1:0] state;
    assign req_ready=(state==IDLE)&&!rst;
    assign ram_en=req_valid&&req_ready;
    assign ram_addr=req_addr;
    assign rsp_valid=(state==HOLD)&&!rst;
    always @(posedge clk) begin
        if(rst) begin state<=IDLE; rsp_data<=0; rsp_tag<=0; end
        else case(state)
            IDLE: if(req_valid&&req_ready) begin rsp_tag<=req_tag; state<=WAIT_RAM; end
            WAIT_RAM: begin rsp_data<=ram_data; state<=HOLD; end
            HOLD: if(rsp_valid&&rsp_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
`default_nettype wire

````


## rtl/mac_scalar.sv

````systemverilog
`timescale 1ns/1ps
`default_nettype none
module mac_scalar(
    input wire clk, rst,
    input wire term_valid, output wire term_ready,
    input wire signed [7:0] x, w,
    input wire first, last, input wire signed [31:0] bias,
    output reg acc_valid, input wire acc_ready,
    output reg signed [31:0] acc_data
);
    reg signed [31:0] psum;
    wire signed [15:0] product=x*w;
    wire signed [31:0] extended_product={{16{product[15]}},product};
    wire signed [31:0] acc_next=(first?bias:psum)+extended_product;
    assign term_ready=!acc_valid&&!rst;
    always @(posedge clk) begin
        if(rst) begin psum<=0;acc_valid<=0;acc_data<=0;end
        else begin
            if(acc_valid&&acc_ready) acc_valid<=0;
            if(term_valid&&term_ready) begin
                psum<=acc_next;
                if(last) begin acc_data<=acc_next;acc_valid<=1;end
            end
        end
    end
endmodule
`default_nettype wire

````


## rtl/postprocess4.sv

````systemverilog
`timescale 1ns/1ps
`default_nettype none
module postprocess4(
    input wire clk,rst,
    input wire acc_valid,output wire acc_ready,
    input wire signed [31:0] acc_data,
    input wire relu_mode,input wire [2:0] index_in,
    output reg y_valid,input wire y_ready,
    output reg signed [7:0] y_data,
    output reg [2:0] y_index,output reg y_last
);
    function signed [7:0] quantize4;
        input signed [31:0] a;
        input relu_en;
        reg signed [31:0] q;
        begin
            q=a>>>2;
            if((a[1:0]>2)||((a[1:0]==2)&&q[0])) q=q+1;
            if(relu_en&&(q<0)) q=0;
            if(q>127) quantize4=8'sd127;
            else if(q<(-128)) quantize4=8'sh80;
            else quantize4=q[7:0];
        end
    endfunction
    assign acc_ready=!y_valid&&!rst;
    always @(posedge clk) begin
        if(rst) begin y_valid<=0;y_data<=0;y_index<=0;y_last<=0;end
        else begin
            if(y_valid&&y_ready) y_valid<=0;
            if(acc_valid&&acc_ready) begin
                y_data<=quantize4(acc_data,relu_mode);
                y_index<=index_in;y_last<=(index_in==7);y_valid<=1;
            end
        end
    end
endmodule
`default_nettype wire

````


## rtl/conv_fixed_top.sv

````systemverilog
`timescale 1ns/1ps
`default_nettype none
module conv_fixed_top(
    input wire clk,rst,
    input wire prepared,cmd_valid,output wire cmd_ready,
    input wire relu_mode,input wire signed [31:0] bias0,bias1,
    output wire busy,rsp_valid,input wire rsp_ready,
    output wire x_ram_en,output wire [4:0] x_ram_addr,input wire [7:0] x_ram_data,
    output wire w_ram_en,output wire [5:0] w_ram_addr,input wire [7:0] w_ram_data,
    output wire y_valid,input wire y_ready,
    output wire signed [7:0] y_data,output wire [2:0] y_index,output wire y_last,
    output wire dbg_req_fire,dbg_term_fire,dbg_acc_fire,
    output wire [7:0] dbg_req_tag,dbg_term_tag,
    output wire signed [31:0] dbg_acc_data
);
    localparam IDLE=3'd0,ISSUE=3'd1,WAIT_PAIR=3'd2,WAIT_Y=3'd3,RESP=3'd4;
    reg [2:0] state,index;
    reg [4:0] k;
    reg relu_q;
    reg signed [31:0] b0_q,b1_q;
    wire [4:0] remk=(k>=5'd9)?(k-5'd9):k;
    wire ci=(k>=5'd9);
    reg [1:0] ky,kx;
    always @* begin
        case(remk)
            0: begin ky=0;kx=0;end
            1: begin ky=0;kx=1;end
            2: begin ky=0;kx=2;end
            3: begin ky=1;kx=0;end
            4: begin ky=1;kx=1;end
            5: begin ky=1;kx=2;end
            6: begin ky=2;kx=0;end
            7: begin ky=2;kx=1;end
            default: begin ky=2;kx=2;end
        endcase
    end
    wire [1:0] iy={1'b0,index[1]}+ky;
    wire [1:0] ix={1'b0,index[0]}+kx;
    wire [4:0] x_address={ci,4'b0}+{1'b0,iy,2'b0}+{3'b0,ix};
    wire [5:0] w_address=(index[2]?6'd18:6'd0)+{1'b0,k};
    wire [7:0] request_tag={index,k};
    wire xr_ready,wr_ready,xv,wv;
    wire [7:0] xd,wd,xt,wt;
    wire mac_ready,mac_valid,mac_acc_valid,post_ready;
    wire signed [31:0] acc;
    wire x_request=(state==ISSUE)&&wr_ready;
    wire w_request=(state==ISSUE)&&xr_ready;
    assign dbg_req_fire=(state==ISSUE)&&xr_ready&&wr_ready&&!rst;
    assign dbg_req_tag=request_tag;
    assign mac_valid=(state==WAIT_PAIR)&&xv&&wv&&(xt==wt);
    assign dbg_term_fire=mac_valid&&mac_ready;
    assign dbg_term_tag=xt;
    assign dbg_acc_fire=mac_acc_valid&&post_ready;
    assign dbg_acc_data=acc;
    assign cmd_ready=(state==IDLE)&&prepared&&!rst;
    assign busy=(state!=IDLE)&&(state!=RESP);
    assign rsp_valid=(state==RESP)&&!rst;

    read_hold #(.AW(5)) xr(
        .clk(clk),.rst(rst),.req_valid(x_request),.req_ready(xr_ready),
        .req_addr(x_address),.req_tag(request_tag),.ram_en(x_ram_en),.ram_addr(x_ram_addr),
        .ram_data(x_ram_data),.rsp_valid(xv),.rsp_ready((state==WAIT_PAIR)&&wv&&mac_ready),
        .rsp_data(xd),.rsp_tag(xt));
    read_hold #(.AW(6)) wr(
        .clk(clk),.rst(rst),.req_valid(w_request),.req_ready(wr_ready),
        .req_addr(w_address),.req_tag(request_tag),.ram_en(w_ram_en),.ram_addr(w_ram_addr),
        .ram_data(w_ram_data),.rsp_valid(wv),.rsp_ready((state==WAIT_PAIR)&&xv&&mac_ready),
        .rsp_data(wd),.rsp_tag(wt));
    mac_scalar mac(
        .clk(clk),.rst(rst),.term_valid(mac_valid),.term_ready(mac_ready),
        .x($signed(xd)),.w($signed(wd)),.first(k==0),.last(k==17),
        .bias(index[2]?b1_q:b0_q),.acc_valid(mac_acc_valid),.acc_ready(post_ready),.acc_data(acc));
    postprocess4 post(
        .clk(clk),.rst(rst),.acc_valid(mac_acc_valid),.acc_ready(post_ready),.acc_data(acc),
        .relu_mode(relu_q),.index_in(index),.y_valid(y_valid),.y_ready(y_ready),
        .y_data(y_data),.y_index(y_index),.y_last(y_last));

    always @(posedge clk) begin
        if(rst) begin state<=IDLE;index<=0;k<=0;relu_q<=0;b0_q<=0;b1_q<=0;end
        else case(state)
            IDLE: if(cmd_valid&&cmd_ready) begin
                relu_q<=relu_mode;b0_q<=bias0;b1_q<=bias1;index<=0;k<=0;state<=ISSUE;
            end
            ISSUE: if(dbg_req_fire) state<=WAIT_PAIR;
            WAIT_PAIR: if(dbg_term_fire) begin
                if(k==17) state<=WAIT_Y;
                else begin k<=k+1;state<=ISSUE;end
            end
            WAIT_Y: if(y_valid&&y_ready) begin
                if(index==7) state<=RESP;
                else begin index<=index+1;k<=0;state<=ISSUE;end
            end
            RESP: if(rsp_valid&&rsp_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
`default_nettype wire

````


## sim/tb_conv_fixed.sv

````systemverilog
`timescale 1ns/1ps
module tb_conv_fixed;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,prepared=0,cmd_valid=0,relu_mode=0,rsp_ready=0,y_ready=0;
    reg signed [31:0] bias0=3,bias1=-1;
    wire cmd_ready,busy,rsp_valid,x_en,w_en,y_valid,y_last;
    wire [4:0] xa;wire [5:0] wa;
    reg [7:0] xd=0,wd=0,xmem[0:31],wmem[0:35];
    wire signed [7:0] y_data;wire [2:0] y_index;
    wire req_fire,term_fire,acc_fire;wire [7:0] req_tag,term_tag;
    wire signed [31:0] acc_data;
    conv_fixed_top dut(.clk(clk),.rst(rst),.prepared(prepared),.cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),.relu_mode(relu_mode),.bias0(bias0),.bias1(bias1),
        .busy(busy),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),
        .x_ram_en(x_en),.x_ram_addr(xa),.x_ram_data(xd),
        .w_ram_en(w_en),.w_ram_addr(wa),.w_ram_data(wd),
        .y_valid(y_valid),.y_ready(y_ready),.y_data(y_data),.y_index(y_index),.y_last(y_last),
        .dbg_req_fire(req_fire),.dbg_term_fire(term_fire),.dbg_acc_fire(acc_fire),
        .dbg_req_tag(req_tag),.dbg_term_tag(term_tag),.dbg_acc_data(acc_data));
    always @(posedge clk) begin
        if(x_en) begin if(integer'(xa)>=32)$fatal(1,"input address");xd<=xmem[xa];end
        if(w_en) begin if(wa>=36)$fatal(1,"weight address");wd<=wmem[wa];end
    end

    integer exp_acc[0:7],exp_y[0:7];
    integer req_count=0,term_count=0,acc_count=0,out_count=0;
    integer jobs=0,cancels=0,total_terms=0,total_outputs=0,hold_checks=0;
    reg active=0,old_hold=0,old_rsp_hold=0;
    reg [11:0] held_y;
    integer o,k,ci,ky,kx,oy,ox,ex,ew;
    function automatic integer signed8(input reg [7:0] v);
        signed8=v[7]?integer'(v)-256:integer'(v);
    endfunction
    function automatic integer rne_ref(input integer a);
        longint signed mag;integer q,r;
        begin
            mag=longint'(a);if(mag<0)mag=-mag;
            q=integer'(mag/4);r=integer'(mag%4);
            if(r>2||(r==2&&(q%2)!=0))q=q+1;
            rne_ref=a<0?-q:q;
        end
    endfunction
    function automatic integer post_ref(input integer a,input reg relu_en);
        integer q;
        begin q=rne_ref(a);if(relu_en&&q<0)q=0;
            if(q>127)q=127;if(q<(-128))q=-128;post_ref=q;end
    endfunction

    always @(posedge clk) begin
        if(rst) begin
            if(active)cancels=cancels+1;
            active=0;req_count=0;term_count=0;acc_count=0;out_count=0;
            old_hold=0;old_rsp_hold=0;
        end else begin
            if(old_hold) begin
                if(!y_valid||{y_last,y_index,y_data}!==held_y)$fatal(1,"unstable y payload");
                hold_checks=hold_checks+1;
            end
            if(old_rsp_hold&&!rsp_valid)$fatal(1,"response vanished");
            old_hold=y_valid&&!y_ready;held_y={y_last,y_index,y_data};
            old_rsp_hold=rsp_valid&&!rsp_ready;
            if(cmd_valid&&cmd_ready) begin
                if(active)$fatal(1,"overlapping command");
                active=1;req_count=0;term_count=0;acc_count=0;out_count=0;
            end
            if(req_fire) begin
                if(!active||req_count>=144)$fatal(1,"unexpected request");
                o=req_count/18;k=req_count%18;ci=k/9;ky=(k%9)/3;kx=k%3;
                oy=(o%4)/2;ox=o%2;
                ex=(ci*4+oy+ky)*4+ox+kx;ew=(o/4)*18+k;
                if(integer'(xa)!=ex||integer'(wa)!=ew||integer'(req_tag)!=(o*32+k))
                    $fatal(1,"request mismatch %0d x=%0d/%0d w=%0d/%0d",req_count,xa,ex,wa,ew);
                req_count=req_count+1;
            end
            if(term_fire) begin
                if(!active||term_count>=144)$fatal(1,"unexpected term");
                if(integer'(term_tag)!=((term_count/18)*32+term_count%18))$fatal(1,"term tag mismatch");
                term_count=term_count+1;total_terms=total_terms+1;
            end
            if(acc_fire) begin
                if(acc_count>=8||$signed(acc_data)!=exp_acc[acc_count])
                    $fatal(1,"wide acc mismatch %0d actual=%0d expected=%0d",acc_count,$signed(acc_data),exp_acc[acc_count]);
                acc_count=acc_count+1;
            end
            if(y_valid&&y_ready) begin
                if(!active||out_count>=8||integer'(y_index)!=out_count||integer'($signed(y_data))!=exp_y[out_count]||y_last!=(out_count==7))
                    $fatal(1,"output mismatch %0d actual=%0d expected=%0d",out_count,$signed(y_data),exp_y[out_count]);
                if(jobs<2)$display("OUTPUT job=%0d index=%0d code=%0d last=%0d",jobs,out_count,$signed(y_data),y_last);
                out_count=out_count+1;total_outputs=total_outputs+1;
            end
            if(rsp_valid) begin
                if(!active||out_count!=8||acc_count!=8||req_count!=144||term_count!=144)
                    $fatal(1,"early/missing completion");
                if(cmd_ready)$fatal(1,"command accepted before response consumed");
            end
            if(rsp_valid&&rsp_ready) begin jobs=jobs+1;active=0;end
        end
    end

    task automatic prepare_case(input integer mode);
        integer i,j,co,yy,xx,a;
        begin
            for(i=0;i<32;i=i+1) begin
                if(mode==0)xmem[i]=8'(i<16?i+1:2);
                else if(mode==1)xmem[i]=8'($urandom_range(0,24)-12);
                else xmem[i]=8'h7f;
            end
            for(i=0;i<36;i=i+1) begin
                if(mode==0)wmem[i]=8'(i<18?(i<9?1:-1):(i<27?-1:2));
                else if(mode==1)wmem[i]=8'($urandom_range(0,8)-4);
                else wmem[i]=8'h7f;
            end
            bias0=mode==1?32'($urandom_range(0,64)-32):3;
            bias1=mode==1?32'($urandom_range(0,64)-32):-1;
            for(co=0;co<2;co=co+1)for(yy=0;yy<2;yy=yy+1)for(xx=0;xx<2;xx=xx+1)begin
                a=co==0?bias0:bias1;
                for(i=0;i<2;i=i+1)for(j=0;j<9;j=j+1)
                    a=a+signed8(xmem[(i*4+yy+j/3)*4+xx+j%3])*signed8(wmem[co*18+i*9+j]);
                exp_acc[co*4+yy*2+xx]=a;
                exp_y[co*4+yy*2+xx]=post_ref(a,relu_mode);
            end
            prepared=1;
        end
    endtask
    task automatic launch;
        begin
            @(negedge clk);cmd_valid=1;
            while(!cmd_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);cmd_valid=0;
        end
    endtask
    task automatic finish_job;
        integer guard,last_hold;
        begin
            guard=0;last_hold=6;
            while(!rsp_valid)begin
                @(negedge clk);guard=guard+1;
                if(guard>5000)$fatal(1,"job timeout");
                // Change unpresented live configuration after command latch.
                bias0=999;bias1=-999;relu_mode=~relu_mode;
                cmd_valid=0;
                if(y_valid&&y_last&&last_hold>0)begin y_ready=0;last_hold=last_hold-1;end
                else y_ready=($urandom_range(0,3)!=0);
            end
            y_ready=0;cmd_valid=0;
            repeat(4)@(negedge clk);
            if(cmd_ready||busy)$fatal(1,"response/idle contract");
            cmd_valid=0;rsp_ready=1;
            @(posedge clk);@(negedge clk);rsp_ready=0;
            if(!cmd_ready)$fatal(1,"not idle after response");
        end
    endtask

    reg mtv=0,mfirst=0,mlast=0,mar=0;
    reg signed[7:0] mx=0,mw=0;reg signed[31:0] mbias=3;
    wire mtr,mav;wire signed[31:0] mad;
    mac_scalar mac_unit(.clk(clk),.rst(rst),.term_valid(mtv),.term_ready(mtr),
        .x(mx),.w(mw),.first(mfirst),.last(mlast),.bias(mbias),
        .acc_valid(mav),.acc_ready(mar),.acc_data(mad));
    task automatic check_mac(input integer count);
        integer j,expected,gaps;
        begin
            expected=3;
            for(j=0;j<count;j=j+1)begin
                gaps=integer'($urandom_range(0,2));repeat(gaps)@(negedge clk);
                @(negedge clk);mx=count==1?-8'sd128:8'($urandom_range(0,255));
                mw=count==1?-8'sd128:8'($urandom_range(0,255));
                expected=expected+integer'(mx)*integer'(mw);
                mfirst=(j==0);mlast=(j==count-1);mtv=1;
                while(!mtr)@(negedge clk);
                @(posedge clk);@(negedge clk);mtv=0;
            end
            while(!mav)@(negedge clk);
            repeat(3)begin if(mad!=expected)$fatal(1,"MAC gap/hold failure");@(negedge clk);end
            mar=1;@(posedge clk);@(negedge clk);mar=0;
            if(mav)$fatal(1,"MAC duplicate");
        end
    endtask

    reg urv=0,urr=0;reg [4:0] ura=3;reg[7:0] urtag=8'ha5,uram=0;
    wire urready,uren,usvalid;wire[4:0] uraddr;wire[7:0] usdata,ustag;
    read_hold read_unit(.clk(clk),.rst(rst),.req_valid(urv),.req_ready(urready),
        .req_addr(ura),.req_tag(urtag),.ram_en(uren),.ram_addr(uraddr),.ram_data(uram),
        .rsp_valid(usvalid),.rsp_ready(urr),.rsp_data(usdata),.rsp_tag(ustag));
    always @(posedge clk)if(uren)uram<=(uraddr==3)?8'hfc:8'h07;
    task automatic check_read;
        begin
            @(negedge clk);urv=1;
            @(posedge clk);if(!urready)$fatal(1,"read request not accepted");
            @(negedge clk);urv=0;
            while(!usvalid)@(negedge clk);
            repeat(4)begin
                if(usdata!==8'hfc||ustag!==8'ha5||urready)$fatal(1,"read response hold/tag");
                @(negedge clk);
            end
            urr=1;@(posedge clk);@(negedge clk);urr=0;
            if(usvalid||!urready)$fatal(1,"read response duplicate");
        end
    endtask

    // Independent postprocess module: ties, saturation and signed extremes.
    reg pav=0,prelu=0,pyr=0;reg signed[31:0] pad=0;
    wire par,pyv,pyl;wire signed[7:0] pyd;wire [2:0] pyi;
    postprocess4 post_unit(.clk(clk),.rst(rst),.acc_valid(pav),.acc_ready(par),.acc_data(pad),
        .relu_mode(prelu),.index_in(3'd7),.y_valid(pyv),.y_ready(pyr),.y_data(pyd),.y_index(pyi),.y_last(pyl));
    task automatic check_post(input integer value,input reg relu_en);
        integer expected;
        begin
            expected=post_ref(value,relu_en);
            @(negedge clk);pad=value;prelu=relu_en;pav=1;
            while(!par)@(negedge clk);
            @(posedge clk);@(negedge clk);pav=0;
            while(!pyv)@(negedge clk);
            repeat(3)begin
                if(integer'($signed(pyd))!=expected||pyi!=7||!pyl)$fatal(1,"post unit mismatch");
                @(negedge clk);
            end
            pyr=1;@(posedge clk);@(negedge clk);pyr=0;
            if(pyv)$fatal(1,"post duplicate");
        end
    endtask

    integer n,seed=2026,unused_seed,reset_case;
    initial begin
        unused_seed=$urandom(seed);
        repeat(3)@(negedge clk);rst=0;
        // Command cannot start before preload is complete.
        cmd_valid=1;repeat(3)@(negedge clk);
        if(cmd_ready||busy)$fatal(1,"started without prepared");cmd_valid=0;
        for(n=0;n<2;n=n+1)begin relu_mode=1'(n);prepare_case(0);launch();finish_job();end
        for(n=0;n<60;n=n+1)begin relu_mode=1'(n);prepare_case(1);launch();finish_job();end
        relu_mode=0;prepare_case(2);launch();finish_job();
        // A legal pending command stays valid until it is actually accepted.
        relu_mode=0;prepare_case(0);launch();
        relu_mode=1;cmd_valid=1;y_ready=1;
        while(!rsp_valid)@(negedge clk);
        prepare_case(0); // Same memories/bias, new ReLU mode; old output already checked.
        rsp_ready=1;@(posedge clk);@(negedge clk);rsp_ready=0;
        if(!cmd_ready)$fatal(1,"queued command not enabled");
        @(posedge clk);@(negedge clk);cmd_valid=0;finish_job();
        // Reset at issue, native RAM pending, mid-dot, held output, held response.
        for(reset_case=0;reset_case<5;reset_case=reset_case+1)begin
            relu_mode=0;prepare_case(0);y_ready=0;launch();
            case(reset_case)
                0: begin end
                1: while(dut.xr.state!=1)@(negedge clk);
                2: while(term_count<3)@(negedge clk);
                3: while(!y_valid)@(negedge clk);
                4: begin y_ready=1;while(!rsp_valid)@(negedge clk);y_ready=0;end
            endcase
            rst=1;prepared=0;cmd_valid=0;rsp_ready=0;
            repeat(2)@(negedge clk);rst=0;
            repeat(4)begin @(negedge clk);if(y_valid||rsp_valid||cmd_ready)$fatal(1,"old result after reset");end
            relu_mode=0;prepare_case(0);launch();finish_job();
        end
        check_post(10,0);check_post(14,0);check_post(-10,0);check_post(-14,0);
        check_post(512,0);check_post(-516,0);check_post(32'sh7fffffff,0);check_post(32'sh80000000,0);
        check_post(-14,1);check_post(512,1);check_post(0,1);
        check_mac(1);check_mac(18);check_mac(18);check_read();
        if(jobs!=70||cancels!=5)$fatal(1,"unexpected test counts %0d %0d",jobs,cancels);
        $display("PASS jobs=%0d cancelled=%0d accepted_terms=%0d accepted_outputs=%0d hold_checks=%0d post_cases=11 mac_cases=3 read_cases=1",jobs,cancels,total_terms,total_outputs,hold_checks);
        $finish;
    end
    initial begin
        if($test$plusargs("TRACE"))begin $dumpfile("results/conv_fixed.vcd");$dumpvars(0,tb_conv_fixed);end
        #10000000;$fatal(1,"global timeout");
    end
endmodule

````


## reference/make_vectors.py

````python
"""Generate the E3/E11 diagnostic fixture; standard Python only."""
import json
from pathlib import Path

def rne4(n):
    sign=-1 if n<0 else 1
    q,r=divmod(abs(n),4)
    return sign*(q+int(r>2 or (r==2 and q%2!=0)))

root=Path(__file__).resolve().parent
x=list(range(1,17))+[2]*16
w=[1]*9+[-1]*9+[-1]*9+[2]*9
b=[3,-1]
acc=[]
for co in range(2):
    for oy in range(2):
        for ox in range(2):
            value=b[co]
            for ci in range(2):
                for ky in range(3):
                    for kx in range(3):
                        value+=x[(ci*4+oy+ky)*4+ox+kx]*w[co*18+ci*9+ky*3+kx]
            acc.append(value)
assert acc==[39,48,75,84,-19,-28,-55,-64]
qy=[max(-128,min(127,rne4(v))) for v in acc]
assert qy==[10,12,19,21,-5,-7,-14,-16]
for name,values in [('input.hex',x),('weight.hex',w)]:
    (root/name).write_text(''.join(f'{v&255:02x}\n' for v in values))
(root/'expected.json').write_text(json.dumps({'contract':'DIAG_2X4X4_VALID_V0_PROPOSAL',
    'x_chw':[2,4,4],'weight_oihw':[2,2,3,3],'output_chw':[2,2,2],
    'terms':144,'bias':b,'acc':acc,'relu_off':qy,'relu_on':[max(0,v) for v in qy]},indent=2)+'\n')
print('REFERENCE PASS: 144 terms, 8 outputs')

````


## run.sh

````sh
#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
mkdir -p results sim/obj_dir
python3 reference/make_vectors.py > results/reference.log
E12_VERILATOR="${VERILATOR:-verilator}"
"$E12_VERILATOR" --lint-only --top-module conv_fixed_top -Wall \
  rtl/conv_fixed_top.sv rtl/read_hold.sv rtl/mac_scalar.sv rtl/postprocess4.sv \
  > results/lint.log 2>&1
"$E12_VERILATOR" --cc --main --exe --timing --trace --top-module tb_conv_fixed \
  -CFLAGS -std=c++20 --Mdir sim/obj_dir \
  rtl/conv_fixed_top.sv rtl/read_hold.sv rtl/mac_scalar.sv rtl/postprocess4.sv sim/tb_conv_fixed.sv \
  > results/elaboration.log 2>&1
make -C sim/obj_dir -f Vtb_conv_fixed.mk CFG_CXXFLAGS_PCH_I=-include -j2 > results/build.log 2>&1
./sim/obj_dir/Vtb_conv_fixed +TRACE > results/simulation.log 2>&1
cat results/reference.log results/simulation.log

````


## results/simulation.log

````text
OUTPUT job=0 index=0 code=10 last=0
OUTPUT job=0 index=1 code=12 last=0
OUTPUT job=0 index=2 code=19 last=0
OUTPUT job=0 index=3 code=21 last=0
OUTPUT job=0 index=4 code=-5 last=0
OUTPUT job=0 index=5 code=-7 last=0
OUTPUT job=0 index=6 code=-14 last=0
OUTPUT job=0 index=7 code=-16 last=1
OUTPUT job=1 index=0 code=10 last=0
OUTPUT job=1 index=1 code=12 last=0
OUTPUT job=1 index=2 code=19 last=0
OUTPUT job=1 index=3 code=21 last=0
OUTPUT job=1 index=4 code=0 last=0
OUTPUT job=1 index=5 code=0 last=0
OUTPUT job=1 index=6 code=0 last=0
OUTPUT job=1 index=7 code=0 last=1
PASS jobs=70 cancelled=5 accepted_terms=10245 accepted_outputs=568 hold_checks=603 post_cases=11 mac_cases=3 read_cases=1
- sim/tb_conv_fixed.sv:262: Verilog $finish
- S i m u l a t i o n   R e p o r t: Verilator 5.49
- Verilator: $finish at 332us; walltime 0.029 s; speed 11.358 ms/s
- Verilator: cpu 0.029 s on 1 threads; allocated 7 MB

````


## results/summary.json

````json
{
  "normal_jobs": 70,
  "reset_cancelled_jobs": 5,
  "normal_outputs": 560,
  "accepted_outputs_including_cancelled": 568,
  "accepted_terms_including_cancelled": 10245,
  "payload_hold_checks": 603,
  "post_unit_cases": 11,
  "mac_unit_cases": 3,
  "read_unit_cases": 1,
  "rtl_simulation": "PASS for selected cases",
  "fpga_implementation": "NOT_RUN"
}

````


## results/toolchain.json

````json
{
  "distribution": "verilator PyPI 5.48.0",
  "version_stdout": "rev vUNKNOWN-built20260516-4e853d8",
  "simulation_banner": "Verilator 5.49",
  "python": "3.12.14",
  "cxx": "g++ (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0",
  "testbench_seed": 2026,
  "target_device": null,
  "timing_constraints_verified": false,
  "run": "VERILATOR=/path/to/verilator bash run.sh"
}

````


## results/source_sha256.json

````json
{
  "rtl/conv_fixed_top.sv": "d2c5096cc32a2e4c22d0dc84509a4113dbf89b2fbd37eb16f1236f559ae51505",
  "rtl/mac_scalar.sv": "7bb89a2f9e92758933ac84741144fe5c155dba144e136d59db5ed6f9f554fafa",
  "rtl/postprocess4.sv": "aec417ad409b63a9c72616aeea83cd9538f68bf69bc70fca2a6055a04a752078",
  "rtl/read_hold.sv": "9c15b5b603cb0eec1878eccc92721dec7a4e0073628a971bae58782fd3d7658d",
  "sim/tb_conv_fixed.sv": "53cf12b5f71d366d9bf339b371dbb82ca3cb542593eab5c8b4b77b67ccf52c82",
  "reference/make_vectors.py": "1da81d43c050ef3777a3463e3913c5ed89873df09c624b530121a48bdcdba785",
  "run.sh": "51d7a0431f3dc0609a90be0e63db6c69ac9f24d5bdad1aca35a359ac4df6a8ef"
}

````
