# E13 RTL·Testbench·실행 근거

실제 Stem shape·padding1의 진단용 RTL이다. 전체 vector/VCD는 ZIP에 있으며 이 첨부는 source와 핵심 로그를 담는다.

## README.md

````
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

````

## rtl/conv3x3_core.sv

````
`timescale 1ns/1ps
`default_nettype none
// Static shape only: stride1, dilation1, groups1, symmetric integer zero point0.
// No runtime divider/modulo. ci/ky/kx and co/oy/ox are nested counters.
module conv3x3_core #(
    parameter integer CIN=3,COUT=16,H=32,W=32,PAD=1,
    parameter integer OH=H+2*PAD-2,OW=W+2*PAD-2
)(
    input wire clk,rst,prepared,cmd_valid,output wire cmd_ready,
    input wire relu_mode,input wire signed [31:0] bias_cfg [0:COUT-1],
    output wire busy,rsp_valid,input wire rsp_ready,
    output wire x_ram_en,output wire [15:0] x_ram_addr,input wire [7:0] x_ram_data,
    output wire w_ram_en,output wire [15:0] w_ram_addr,input wire [7:0] w_ram_data,
    output wire y_valid,input wire y_ready,output wire signed [7:0] y_data,
    output wire [15:0] y_index,output wire y_last,
    output wire dbg_req_fire,dbg_req_pad,dbg_term_fire,dbg_term_pad,dbg_acc_fire,
    output wire [31:0] dbg_req_tag,dbg_term_tag,output wire signed [31:0] dbg_acc_data
);
    localparam integer NOUT=COUT*OH*OW,K=CIN*9;
    localparam integer CIW=(CIN>1)?$clog2(CIN):1,COW=(COUT>1)?$clog2(COUT):1;
    localparam integer YW=(OH>1)?$clog2(OH):1,XW=(OW>1)?$clog2(OW):1;
    localparam IDLE=3'd0,ISSUE=3'd1,WAIT_PAIR=3'd2,WAIT_Y=3'd3,RESP=3'd4;
    reg [2:0] state;
    reg [CIW-1:0] ci;
    reg [COW-1:0] co;
    reg [YW-1:0] oy;reg [XW-1:0] ox;
    reg [1:0] ky,kx;
    reg [15:0] index,k;
    reg relu_q,pad_q;
    reg signed [31:0] bias_q [0:COUT-1];
    wire signed [31:0] iy=32'(oy)+32'(ky)-PAD;
    wire signed [31:0] ix=32'(ox)+32'(kx)-PAD;
    wire padding=(iy<0)||(iy>=H)||(ix<0)||(ix>=W);
    // The cast of an out-of-range address is never used for a RAM read.
    wire [15:0] x_address=16'(32'(ci)*H*W+iy*W+ix);
    wire [15:0] w_address=16'(32'(co)*K+32'(k));
    wire [31:0] request_tag={index,k};
    wire xr_ready,wr_ready,xv,wv;
    wire [7:0] xd,wd;wire [31:0] xt,wt;
    wire mac_ready,mac_valid,acc_valid,post_ready;
    wire signed [31:0] acc;
    wire pair_ok=pad_q||(xv&&(xt==wt));
    wire x_request=(state==ISSUE)&&!padding&&wr_ready;
    wire w_request=(state==ISSUE)&&(padding||xr_ready);
    assign dbg_req_fire=(state==ISSUE)&&wr_ready&&(padding||xr_ready)&&!rst;
    assign dbg_req_pad=padding;assign dbg_req_tag=request_tag;
    assign mac_valid=(state==WAIT_PAIR)&&wv&&pair_ok;
    assign dbg_term_fire=mac_valid&&mac_ready;
    assign dbg_term_pad=pad_q;assign dbg_term_tag=wt;
    assign dbg_acc_fire=acc_valid&&post_ready;assign dbg_acc_data=acc;
    assign cmd_ready=(state==IDLE)&&prepared&&!rst;
    assign busy=(state!=IDLE)&&(state!=RESP);
    assign rsp_valid=(state==RESP)&&!rst;
    read_hold #(.AW(16),.TW(32)) xr(
        .clk(clk),.rst(rst),.req_valid(x_request),.req_ready(xr_ready),
        .req_addr(x_address),.req_tag(request_tag),.ram_en(x_ram_en),.ram_addr(x_ram_addr),
        .ram_data(x_ram_data),.rsp_valid(xv),
        .rsp_ready((state==WAIT_PAIR)&&wv&&mac_ready&&pair_ok&&!pad_q),
        .rsp_data(xd),.rsp_tag(xt));
    read_hold #(.AW(16),.TW(32)) wr(
        .clk(clk),.rst(rst),.req_valid(w_request),.req_ready(wr_ready),
        .req_addr(w_address),.req_tag(request_tag),.ram_en(w_ram_en),.ram_addr(w_ram_addr),
        .ram_data(w_ram_data),.rsp_valid(wv),
        .rsp_ready((state==WAIT_PAIR)&&mac_ready&&pair_ok),.rsp_data(wd),.rsp_tag(wt));
    mac_scalar mac(.clk(clk),.rst(rst),.term_valid(mac_valid),.term_ready(mac_ready),
        .x(pad_q?8'sd0:$signed(xd)),.w($signed(wd)),.first(k==0),.last(k==16'(K-1)),
        .bias(bias_q[co]),.acc_valid(acc_valid),.acc_ready(post_ready),.acc_data(acc));
    postprocess_index #(.NOUT(NOUT)) post(.clk(clk),.rst(rst),
        .acc_valid(acc_valid),.acc_ready(post_ready),.acc_data(acc),.relu_mode(relu_q),
        .index_in(index),.y_valid(y_valid),.y_ready(y_ready),.y_data(y_data),
        .y_index(y_index),.y_last(y_last));
    always @(posedge clk)begin
        if(rst)begin
            state<=IDLE;ci<=0;co<=0;oy<=0;ox<=0;ky<=0;kx<=0;index<=0;k<=0;
            relu_q<=0;pad_q<=0;
            for(integer b=0;b<COUT;b=b+1)bias_q[b]<=0;
        end else case(state)
            IDLE:if(cmd_valid&&cmd_ready)begin
                relu_q<=relu_mode;index<=0;k<=0;ci<=0;co<=0;oy<=0;ox<=0;ky<=0;kx<=0;
                for(integer b=0;b<COUT;b=b+1)bias_q[b]<=bias_cfg[b];
                state<=ISSUE;
            end
            ISSUE:if(dbg_req_fire)begin pad_q<=padding;state<=WAIT_PAIR;end
            WAIT_PAIR:if(dbg_term_fire)begin
                if(k==16'(K-1))state<=WAIT_Y;
                else begin
                    k<=k+1;
                    if(kx==2)begin
                        kx<=0;
                        if(ky==2)begin ky<=0;ci<=ci+1;end
                        else ky<=ky+1;
                    end else kx<=kx+1;
                    state<=ISSUE;
                end
            end
            WAIT_Y:if(y_valid&&y_ready)begin
                if(index==16'(NOUT-1))state<=RESP;
                else begin
                    index<=index+1;k<=0;ci<=0;ky<=0;kx<=0;
                    if(ox==XW'(OW-1))begin
                        ox<=0;
                        if(oy==YW'(OH-1))begin oy<=0;co<=co+1;end
                        else oy<=oy+1;
                    end else ox<=ox+1;
                    state<=ISSUE;
                end
            end
            RESP:if(rsp_valid&&rsp_ready)state<=IDLE;
            default:state<=IDLE;
        endcase
    end
endmodule
`default_nettype wire

````

## rtl/mac_scalar.sv

````
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

## rtl/postprocess_index.sv

````
`timescale 1ns/1ps
`default_nettype none
module postprocess_index #(parameter integer NOUT=16384)(
    input wire clk,rst,acc_valid,output wire acc_ready,
    input wire signed [31:0] acc_data,input wire relu_mode,
    input wire [15:0] index_in,
    output reg y_valid,input wire y_ready,
    output reg signed [7:0] y_data,output reg [15:0] y_index,output reg y_last
);
    function automatic signed [7:0] quantize4(input signed [31:0] a,input relu_en);
        reg signed [31:0] q;
        begin
            q=a>>>2;
            if((a[1:0]>2)||((a[1:0]==2)&&q[0]))q=q+1;
            if(relu_en&&(q<0))q=0;
            if(q>127)quantize4=8'sd127;
            else if(q<(-128))quantize4=8'sh80;
            else quantize4=q[7:0];
        end
    endfunction
    assign acc_ready=!y_valid&&!rst;
    always @(posedge clk)begin
        if(rst)begin y_valid<=0;y_data<=0;y_index<=0;y_last<=0;end
        else begin
            if(y_valid&&y_ready)y_valid<=0;
            if(acc_valid&&acc_ready)begin
                y_valid<=1;y_data<=quantize4(acc_data,relu_mode);
                y_index<=index_in;y_last<=(index_in==16'(NOUT-1));
            end
        end
    end
endmodule
`default_nettype wire

````

## rtl/read_hold.sv

````
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

## sim/tb_stem.sv

````
`timescale 1ns/1ps
module tb_stem;
    parameter integer TINY=0;
    localparam integer CIN=(TINY!=0)?2:3,COUT=(TINY!=0)?2:16,H=(TINY!=0)?4:32,W=H,PAD=(TINY!=0)?0:1;
    localparam integer OH=H+2*PAD-2,OW=W+2*PAD-2,K=CIN*9,NOUT=COUT*OH*OW;
    localparam integer NX=CIN*H*W,NW=COUT*K,NC=(TINY!=0)?2:4;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,prepared=0,cmd_valid=0,relu_mode=0,y_ready=0,rsp_ready=0;
    reg signed [31:0] bias_cfg[0:COUT-1];
    wire cmd_ready,busy,rsp_valid,xe,we,yv,yl,rf,rp,tf,tp,af;
    wire [15:0] xa,wa,yi;wire [31:0] rt,tt;
    wire signed [7:0] yd;wire signed [31:0] ad;
    reg [7:0] xd=0,wd=0,xmem[0:NX-1],wmem[0:NW-1],gold_y[0:NOUT-1];
    reg [31:0] gold_acc[0:NOUT-1],bias_mem[0:COUT-1];
    conv3x3_core #(.CIN(CIN),.COUT(COUT),.H(H),.W(W),.PAD(PAD)) dut(
        .clk(clk),.rst(rst),.prepared(prepared),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),
        .relu_mode(relu_mode),.bias_cfg(bias_cfg),.busy(busy),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),
        .x_ram_en(xe),.x_ram_addr(xa),.x_ram_data(xd),.w_ram_en(we),.w_ram_addr(wa),.w_ram_data(wd),
        .y_valid(yv),.y_ready(y_ready),.y_data(yd),.y_index(yi),.y_last(yl),
        .dbg_req_fire(rf),.dbg_req_pad(rp),.dbg_term_fire(tf),.dbg_term_pad(tp),
        .dbg_acc_fire(af),.dbg_req_tag(rt),.dbg_term_tag(tt),.dbg_acc_data(ad));
    always @(posedge clk)begin
        if(xe)begin if(integer'(xa)>=NX)$fatal(1,"input address OOB");xd<=xmem[integer'(xa)];end
        if(we)begin if(integer'(wa)>=NW)$fatal(1,"weight address OOB");wd<=wmem[integer'(wa)];end
    end
    integer reqs=0,terms=0,accs=0,outs=0,reads=0,pads=0,jobs=0,cancelled=0;
    longint total_terms=0,total_outputs=0,total_pads=0,total_reads=0;
    integer holds=0,corner=0,edge_count=0,interior=0;
    reg active=0,held=0,rsp_held=0;reg [24:0] payload;
    integer o,k,co,oy,ox,ci,ky,kx,iy,ix,expected_pad,expected_addr;
    always @(posedge clk)begin
        if(rst)begin
            if(active)cancelled=cancelled+1;
            active=0;reqs=0;terms=0;accs=0;outs=0;reads=0;pads=0;held=0;rsp_held=0;
        end else begin
            if(held)begin
                if(!yv||{yl,yi,yd}!==payload)$fatal(1,"output hold");holds=holds+1;
            end
            if(rsp_held&&!rsp_valid)$fatal(1,"response hold");
            held=yv&&!y_ready;payload={yl,yi,yd};rsp_held=rsp_valid&&!rsp_ready;
            if(cmd_valid&&cmd_ready)begin
                if(active)$fatal(1,"overlapping command");
                active=1;reqs=0;terms=0;accs=0;outs=0;reads=0;pads=0;
                corner=0;edge_count=0;interior=0;
            end
            if(xe&&!rf)$fatal(1,"stray input request");
            if(we!=rf)$fatal(1,"weight request missing/duplicate");
            if(rf)begin
                if(!active||reqs>=NOUT*K)$fatal(1,"unexpected logical request");
                o=reqs/K;k=reqs%K;co=o/(OH*OW);oy=(o/OW)%OH;ox=o%OW;
                ci=k/9;ky=(k%9)/3;kx=k%3;iy=oy+ky-PAD;ix=ox+kx-PAD;
                expected_pad=(iy<0||iy>=H||ix<0||ix>=W)?1:0;
                expected_addr=(ci*H+iy)*W+ix;
                if(rt!={16'(o),16'(k)}||integer'(wa)!=co*K+k||integer'(rp)!=expected_pad)
                    $fatal(1,"request tag/weight/padding mismatch term=%0d",reqs);
                if(xe==1'(expected_pad))$fatal(1,"RAM read on padding or missing real read");
                if(xe)begin
                    if(integer'(xa)!=expected_addr)$fatal(1,"input address mismatch");
                    reads=reads+1;total_reads=total_reads+1;
                end else begin pads=pads+1;total_pads=total_pads+1;end
                reqs=reqs+1;
            end
            if(tf)begin
                if(!active||terms>=NOUT*K||tt!={16'(terms/K),16'(terms%K)})$fatal(1,"term tag/order");
                o=terms/K;k=terms%K;oy=(o/OW)%OH;ox=o%OW;
                iy=oy+(k%9)/3-PAD;ix=ox+k%3-PAD;
                if(tp!=(iy<0||iy>=H||ix<0||ix>=W))$fatal(1,"term pad tag");
                if(tp&&dut.mac.x!==8'sd0)$fatal(1,"padding is not integer zero");
                terms=terms+1;total_terms=total_terms+1;
            end
            if(af)begin
                if(accs>=NOUT||ad!==gold_acc[accs])$fatal(1,"wide acc index=%0d got=%0d expected=%0d",accs,ad,$signed(gold_acc[accs]));
                accs=accs+1;
            end
            if(yv&&y_ready)begin
                if(!active||outs>=NOUT||integer'(yi)!=outs||yd!==gold_y[outs]||yl!=(outs==NOUT-1))
                    $fatal(1,"output mismatch index=%0d got=%0d expected=%0d",outs,yd,$signed(gold_y[outs]));
                oy=(outs/OW)%OH;ox=outs%OW;
                if((oy==0||oy==OH-1)&&(ox==0||ox==OW-1))corner=corner+1;
                else if(oy==0||oy==OH-1||ox==0||ox==OW-1)edge_count=edge_count+1;
                else interior=interior+1;
                outs=outs+1;total_outputs=total_outputs+1;
            end
            if(rsp_valid)begin
                if(!active||reqs!=NOUT*K||terms!=NOUT*K||accs!=NOUT||outs!=NOUT||reads+pads!=NOUT*K)
                    $fatal(1,"completion boundary");
                if((TINY==0)&&(pads!=18240||reads!=424128||corner!=64||edge_count!=1920||interior!=14400))
                    $fatal(1,"geometry coverage");
                if(cmd_ready||busy)$fatal(1,"response state");
            end
            if(rsp_valid&&rsp_ready)begin
                $display("JOB PASS tiny=%0d job=%0d terms=%0d outputs=%0d valid_reads=%0d padding=%0d corners=%0d edges=%0d interior=%0d",TINY,jobs,terms,outs,reads,pads,corner,edge_count,interior);
                active=0;jobs=jobs+1;
            end
        end
    end
    task automatic require_file(input string name);
        integer fd;
        begin
            fd=$fopen(name,"r");
            if(fd==0)$fatal(1,"missing reference file: %s",name);
            $fclose(fd);
        end
    endtask
    task automatic prepare_case(input integer j);
        string path;
        begin
            path=$sformatf("reference/%s/job%0d/",(TINY!=0)?"tiny":"stem",j);
            require_file({path,"input.hex"});$readmemh({path,"input.hex"},xmem);require_file({path,"weight.hex"});$readmemh({path,"weight.hex"},wmem);
            require_file({path,"bias.hex"});$readmemh({path,"bias.hex"},bias_mem);require_file({path,"acc.hex"});$readmemh({path,"acc.hex"},gold_acc);require_file({path,"output.hex"});$readmemh({path,"output.hex"},gold_y);
            for(integer i=0;i<COUT;i=i+1)bias_cfg[i]=$signed(bias_mem[i]);
            relu_mode=(TINY!=0)?1'(j):1'(j==2);prepared=1;
        end
    endtask
    task automatic launch;
        begin
            @(negedge clk);cmd_valid=1;
            while(!cmd_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);cmd_valid=0;
        end
    endtask
    reg [31:0] rng=32'h13a513a5;
    task automatic finish_job;
        integer guard,last_hold;
        begin
            guard=0;last_hold=7;
            while(!rsp_valid)begin
                @(negedge clk);guard=guard+1;
                if(guard>NOUT*(K*4+25))$fatal(1,"timeout");
                rng=(rng<<1)^((rng[31])?32'h04c11db7:32'd0);
                // Alter live inputs after command latch; no new command is pending.
                for(integer i=0;i<COUT;i=i+1)bias_cfg[i]=9999;
                relu_mode=~relu_mode;
                if(yv&&yl&&last_hold>0)begin y_ready=0;last_hold=last_hold-1;end
                else y_ready=rng[0]||rng[3];
            end
            y_ready=0;
            repeat(4)@(negedge clk);
            rsp_ready=1;@(posedge clk);@(negedge clk);rsp_ready=0;
            if(!cmd_ready)$fatal(1,"not idle");
        end
    endtask
    task automatic reset_cancel;
        begin
            rst=1;prepared=0;cmd_valid=0;y_ready=0;rsp_ready=0;
            repeat(2)@(negedge clk);rst=0;
            repeat(4)begin @(negedge clk);if(yv||rsp_valid||cmd_ready)$fatal(1,"stale valid after reset");end
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        cmd_valid=1;repeat(3)@(negedge clk);
        if(cmd_ready||busy)$fatal(1,"prepared gate");cmd_valid=0;
        for(integer j=0;j<NC;j=j+1)begin prepare_case(j);launch();finish_job();end
        if((TINY==0))begin
            // Cancel padded read pending, valid read pending, middle dot, held y, held response.
            for(integer r=0;r<5;r=r+1)begin
                prepare_case(1);y_ready=0;launch();
                case(r)
                    0:while(!(dut.wr.state==1&&dut.pad_q))@(negedge clk);
                    1:while(!(dut.xr.state==1&&!dut.pad_q))@(negedge clk);
                    2:while(terms<14)@(negedge clk);
                    3:while(!yv)@(negedge clk);
                    4:begin y_ready=1;while(!rsp_valid)@(negedge clk);end
                endcase
                reset_cancel();
            end
            prepare_case(1);launch();finish_job();
        end
        if(jobs!=((TINY!=0)?2:5)||cancelled!=((TINY!=0)?0:5))$fatal(1,"test count");
        $display("PASS tiny=%0d jobs=%0d cancelled=%0d accepted_terms=%0d accepted_outputs=%0d real_reads=%0d padding_terms=%0d hold_checks=%0d",TINY,jobs,cancelled,total_terms,total_outputs,total_reads,total_pads,holds);
        $finish;
    end
    initial begin
        if($test$plusargs("TRACE"))begin
            $dumpfile((TINY!=0)?"results/tiny.vcd":"results/stem_first_window.vcd");$dumpvars(0,tb_stem);
            #40000;$display("TRACE WINDOW ONLY: not a full regression");$finish;
        end
    end
    initial begin #2000000000;$fatal(1,"global timeout");end
endmodule

````

## reference/make_vectors.py

````
#!/usr/bin/env python3
"""Independent integer golden: loop over coordinates, explicit zero extension."""
from pathlib import Path
import json, random
ROOT=Path(__file__).resolve().parent
def rne4(a):
    q,r=divmod(abs(a),4)
    q+=r>2 or (r==2 and q%2==1)
    return -q if a<0 else q
def quant(a,relu):
    q=rne4(a)
    return max(-128,min(127,max(0,q) if relu else q))
def hexfile(path,values,bits):
    path.write_text(''.join(f'{v&((1<<bits)-1):0{bits//4}x}\n' for v in values))
def make(name,cin,cout,h,w,pad,jobs):
    oh,ow=h+2*pad-2,w+2*pad-2
    rng=random.Random(13013)
    summary=[]
    for job in range(jobs):
        relu=job%2 if name=='tiny' else int(job==2)
        if name=='tiny':
            x=list(range(1,17))+[2]*16
            wt=[1]*9+[-1]*9+[-1]*9+[2]*9
            bias=[3,-1]
        elif job==0:
            x=[1]*(cin*h*w);wt=[1]*(cout*cin*9);bias=[0]*cout
        elif job in (1,2):
            # Same signed vector in two modes, using a fresh identical RNG.
            r=random.Random(13131)
            x=[r.randint(-8,8) for _ in range(cin*h*w)]
            wt=[r.randint(-4,4) for _ in range(cout*cin*9)]
            bias=[r.randint(-63,63) for _ in range(cout)]
        else:
            x=[-128 if i%2 else 127 for i in range(cin*h*w)]
            wt=[-128 if (i//9)%2 else 127 for i in range(cout*cin*9)]
            bias=[(-31 if i%2 else 17) for i in range(cout)]
        acc=[];out=[];pads=0;valid=0
        for co in range(cout):
            for oy in range(oh):
                for ox in range(ow):
                    a=bias[co]
                    for ci in range(cin):
                        for ky in range(3):
                            for kx in range(3):
                                iy,ix=oy+ky-pad,ox+kx-pad
                                if 0<=iy<h and 0<=ix<w:
                                    a+=x[(ci*h+iy)*w+ix]*wt[((co*cin+ci)*3+ky)*3+kx]
                                    valid+=1
                                else:pads+=1
                    assert -(1<<31)<=a<(1<<31)
                    acc.append(a);out.append(quant(a,relu))
        d=ROOT/name/f'job{job}';d.mkdir(parents=True,exist_ok=True)
        for filename,values,bits in [('input.hex',x,8),('weight.hex',wt,8),('bias.hex',bias,32),('acc.hex',acc,32),('output.hex',out,8)]:
            hexfile(d/filename,values,bits)
        samples={str(i):{'acc':acc[i],'code':out[i]} for i in sorted({0,1,ow+1,oh*ow-1,len(out)-1})}
        summary.append(dict(job=job,relu=relu,outputs=len(out),terms=cout*oh*ow*cin*9,
                            valid_reads=valid,padding_terms=pads,samples=samples))
        if name=='tiny':assert out==([10,12,19,21,0,0,0,0] if relu else [10,12,19,21,-5,-7,-14,-16])
        if name=='stem' and job==0:
            assert (out[0],out[1],out[33])==(3,4,7)
            assert pads==18240 and valid==424128
    (ROOT/name/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'REFERENCE PASS {name}: jobs={jobs} outputs/job={cout*oh*ow} K={cin*9} valid/job={valid} padding/job={pads}')
if __name__=='__main__':
    make('stem',3,16,32,32,1,4)
    make('tiny',2,2,4,4,0,2)

````

## run.sh

````
#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
mkdir -p results
python3 reference/make_vectors.py > results/reference.log
TASK_VERILATOR="${VERILATOR:-verilator}"
for tiny in 0 1; do
  build_dir="sim/obj_$tiny"
  mkdir -p "$build_dir"
  "$TASK_VERILATOR" --lint-only --top-module conv3x3_core -Wall \
    -GCIN=$([ "$tiny" = 1 ] && echo 2 || echo 3) -GCOUT=$([ "$tiny" = 1 ] && echo 2 || echo 16) \
    -GH=$([ "$tiny" = 1 ] && echo 4 || echo 32) -GW=$([ "$tiny" = 1 ] && echo 4 || echo 32) \
    -GPAD=$([ "$tiny" = 1 ] && echo 0 || echo 1) rtl/*.sv > "results/lint_$tiny.log" 2>&1
  "$TASK_VERILATOR" --cc --main --exe --timing --trace --top-module tb_stem \
    -GTINY="$tiny" -CFLAGS -std=c++20 --Mdir "$build_dir" \
    rtl/*.sv sim/tb_stem.sv > "results/elaboration_$tiny.log" 2>&1
  make -C "$build_dir" -f Vtb_stem.mk CFG_CXXFLAGS_PCH_I=-include -j2 > "results/build_$tiny.log" 2>&1
  "./$build_dir/Vtb_stem" > "results/simulation_$tiny.log" 2>&1
done
./sim/obj_0/Vtb_stem +TRACE > results/trace_window.log 2>&1
python3 verify_missing_reference.py sim/obj_1/Vtb_stem reference/tiny/job0/input.hex > results/negative_test_report.log
python3 record_results.py > results/report.log
cat results/reference.log results/simulation_0.log results/simulation_1.log

````

## verify_missing_reference.py

````
#!/usr/bin/env python3
"""Exercise a real failure path; restore the vector even when simulation fails."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parent
exe=(ROOT/sys.argv[1]).resolve();p=ROOT/sys.argv[2]
temporary=p.with_suffix('.negative_test_hidden')
assert p.is_file() and not temporary.exists()
p.rename(temporary)
try:
    r=subprocess.run([str(exe)],cwd=ROOT,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
finally:
    temporary.rename(p)
assert r.returncode!=0 and 'missing reference file' in r.stdout,r.stdout
(ROOT/'results/missing_reference_negative.log').write_text(
    'NEGATIVE TEST PASS: missing reference aborts before simulation comparison\n'+r.stdout)
print('NEGATIVE TEST PASS: missing reference guard')

````

## record_results.py

````
#!/usr/bin/env python3
"""Record final logs, tool identity and source/vector hashes. Never infer PASS."""
from pathlib import Path
import hashlib,json,os,platform,re,subprocess
ROOT=Path(__file__).resolve().parent
def version(argv):
    r=subprocess.run(argv,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=True)
    return r.stdout.strip()
def main():
    results=[]
    for i in range(2):
        p=ROOT/f'results/simulation_{i}.log';s=p.read_text()
        assert not re.search(r'%Warning|%Error|%Fatal|Assertion failed',s),p
        rows=re.findall(r'^PASS (.+)$',s,re.M)
        assert len(rows)==1,p
        counts={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',rows[0])}
        results.append({'log':str(p.relative_to(ROOT)),**counts})
    summary={'scope':ROOT.name,'results':results,
             'trace':'separate partial-window run, not full regression evidence',
             'negative_reference_guard':'PASS' if 'NEGATIVE TEST PASS' in (ROOT/'results/missing_reference_negative.log').read_text() else 'FAIL'}
    (ROOT/'results/summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    paths=sorted(p for p in ROOT.rglob('*') if p.is_file() and
                 ('rtl' in p.relative_to(ROOT).parts or 'reference' in p.relative_to(ROOT).parts or
                  p.parent==ROOT or p.parent==ROOT/'sim') and '__pycache__' not in p.parts)
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    (ROOT/'results/source_sha256.json').write_text(json.dumps(hashes,indent=2)+'\n')
    tool={'verilator_distribution':'5.48.0 (used environment PyPI metadata)',
          'verilator_version':version([os.environ.get('VERILATOR','verilator'),'--version']),
          'simulation_banner':'Verilator 5.49 (see full simulation logs)',
          'python':platform.python_version(),'cxx':version(['c++','--version']).splitlines()[0]}
    (ROOT/'results/toolchain.json').write_text(json.dumps(tool,indent=2)+'\n')
    print(json.dumps(summary,indent=2))
if __name__=='__main__':main()

````

## results/summary.json

````
{
  "scope": "e13_stem",
  "results": [
    {
      "log": "results/simulation_0.log",
      "tiny": 0,
      "jobs": 5,
      "cancelled": 5,
      "accepted_terms": 2654253,
      "accepted_outputs": 98304,
      "real_reads": 2544786,
      "padding_terms": 109469,
      "hold_checks": 27832
    },
    {
      "log": "results/simulation_1.log",
      "tiny": 1,
      "jobs": 2,
      "cancelled": 0,
      "accepted_terms": 288,
      "accepted_outputs": 16,
      "real_reads": 288,
      "padding_terms": 0,
      "hold_checks": 19
    }
  ],
  "trace": "separate partial-window run, not full regression evidence",
  "negative_reference_guard": "PASS"
}

````

## results/toolchain.json

````
{
  "verilator_distribution": "5.48.0 (used environment PyPI metadata)",
  "verilator_version": "rev vUNKNOWN-built20260516-4e853d8",
  "simulation_banner": "Verilator 5.49 (see full simulation logs)",
  "python": "3.12.14",
  "cxx": "c++ (Ubuntu 13.3.0-6ubuntu2~24.04) 13.3.0"
}

````

## results/simulation_0.log

````
JOB PASS tiny=0 job=0 terms=442368 outputs=16384 valid_reads=424128 padding=18240 corners=64 edges=1920 interior=14400
JOB PASS tiny=0 job=1 terms=442368 outputs=16384 valid_reads=424128 padding=18240 corners=64 edges=1920 interior=14400
JOB PASS tiny=0 job=2 terms=442368 outputs=16384 valid_reads=424128 padding=18240 corners=64 edges=1920 interior=14400
JOB PASS tiny=0 job=3 terms=442368 outputs=16384 valid_reads=424128 padding=18240 corners=64 edges=1920 interior=14400
JOB PASS tiny=0 job=4 terms=442368 outputs=16384 valid_reads=424128 padding=18240 corners=64 edges=1920 interior=14400
PASS tiny=0 jobs=5 cancelled=5 accepted_terms=2654253 accepted_outputs=98304 real_reads=2544786 padding_terms=109469 hold_checks=27832
- sim/tb_stem.sv:172: Verilog $finish
- S i m u l a t i o n   R e p o r t: Verilator 5.49
- Verilator: $finish at 82ms; walltime 3.626 s; speed 22.596 ms/s
- Verilator: cpu 3.623 s on 1 threads; allocated 7 MB

````

## results/simulation_1.log

````
JOB PASS tiny=1 job=0 terms=144 outputs=8 valid_reads=144 padding=0 corners=8 edges=0 interior=0
JOB PASS tiny=1 job=1 terms=144 outputs=8 valid_reads=144 padding=0 corners=8 edges=0 interior=0
PASS tiny=1 jobs=2 cancelled=0 accepted_terms=288 accepted_outputs=16 real_reads=288 padding_terms=0 hold_checks=19
- sim/tb_stem.sv:172: Verilog $finish
- S i m u l a t i o n   R e p o r t: Verilator 5.49
- Verilator: $finish at 9us; walltime 0.000 s; speed 19.101 ms/s
- Verilator: cpu 0.000 s on 1 threads; allocated 6 MB

````

## results/missing_reference_negative.log

````
NEGATIVE TEST PASS: missing reference aborts before simulation comparison
[60000] %Fatal: tb_stem.sv:101: Assertion failed in tb_stem.require_file: missing reference file: reference/tiny/job0/input.hex
%Error: sim/tb_stem.sv:101: Verilog $stop
Aborting...

````
