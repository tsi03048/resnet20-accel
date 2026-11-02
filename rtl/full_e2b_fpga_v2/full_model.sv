`timescale 1ns/1ps
// Fixed ResNet20 E2-B: 19 Conv + 9 Add + GAP + FC, three feature banks.
// Sequential native loader; no Golden, readmemh, host intermediate writes.
module full_model(
    input logic clk,rst,load_begin,cfg_valid,
    output logic cfg_ready,
    input logic [2:0] cfg_kind,
    input logic [18:0] cfg_addr,
    input logic [31:0] cfg_data,
    output logic load_error,prepared,
    output logic [12:0] input_count,
    output logic [18:0] weight_count,
    output logic [9:0] bias_count,n_count,shift_count,
    input logic start,
    output logic start_ready,start_rejected,busy,done,fault,
    output logic [2:0] fault_code,
    input logic compute_ready,
    output logic step_valid,mac_fire,gap_fire,
    output logic trace_valid,
    input logic trace_ready,
    output logic [4:0] trace_op,
    output logic [13:0] trace_addr,
    output logic signed [31:0] trace_acc,trace_code,
    output logic signed [7:0] trace_skip,
    output logic signed [63:0] trace_wide,
    output logic trace_skip_from_x,
    output logic [13:0] trace_skip_addr,
    output logic rsp_valid,result_valid,
    input logic rsp_ready,
    output logic [3:0] prediction,
    input logic [3:0] score_read_addr,
    output logic signed [31:0] score_read_data
);
    typedef enum logic [4:0] {IDLE,FETCH,INIT,PARAM_LATCH,READ_PAIR,READ_LATCH,MAC,
        MUL_START,MUL_WAIT,ROUND_START,ROUND_WAIT,TRACE_HOLD,ADD_READ,ADD_LATCH,RESP,FAILED,PARAM_WAIT,READ_WAIT,PRODUCT,ADDRESS,ADD_ADDRESS} state_t;
    state_t state;
    typedef struct packed {
        logic [1:0] kind,src,dst,skip;
        logic relu,stride2,option_a;
        logic [2:0] ilog,olog;
        logic [5:0] ih;
        logic [6:0] ci;
        logic [9:0] terms,mask;
        logic [13:0] last;
        logic [30:0] main_n,skip_n;
        logic [4:0] r;
    } descriptor_t;
    descriptor_t decoded,op;
    logic [9:0] decoded_pbase;
    logic [18:0] decoded_wbase;
    logic [4:0] op_id;
    `include "control_rom.svh"
    logic armed,clear_load,cfg_fire,input_we,weight_we,bias_we,n_we,shift_we;
    logic input_pending,weight_pending,bias_pending,n_pending,shift_pending;
    logic [18:0] load_address;
    logic [31:0] load_data;
    logic [15:0] read_a_address,read_b_address;
    logic read_a_inside,read_b_inside;
    logic [18:0] read_weight_address;
    logic [13:0] out_idx,x_address,skip_address;
    logic [9:0] term_idx,param_address;
    logic [18:0] channel_wbase,w_address;
    logic [6:0] oc;
    logic [4:0] skip_channel;
    logic [4:0] oy,ox;
    logic [5:0] ic;
    logic [1:0] ky,kx;
    logic signed [6:0] iy,ix;
    logic inside_input,skip_inside,channel_last;
    logic signed [7:0] pair_x,pair_w,weight_q,ram_a_q,ram_b_q;
    logic signed [15:0] product;
    logic signed [31:0] acc,bias_q,n_q,scores[0:9];
    logic [30:0] active_n;
    logic [4:0] active_r,shift_q;
    logic signed [32:0] acc_next;
    logic ram_a_en,ram_a_we,ram_b_en,weight_re,coeff_re;
    logic [15:0] ram_a_addr,ram_b_addr;
    logic signed [7:0] ram_data;
    logic mul_ready,unused_mul_busy,mul_valid,round_ready,unused_round_busy,round_valid;
    logic signed [31:0] main_value,skip_value,mul_lhs1,mul_lhs2,round_code,unused_best;
    logic [30:0] mul_n1,mul_n2;
    logic signed [63:0] mul_result,wide_value,unused_rounded;
    logic [4:0] round_shift;
    logic [1:0] round_mode;

    feature_ram feature_mem(.clk(clk),.a_en(ram_a_en),.a_we(ram_a_we),.b_en(ram_b_en),
        .a_addr(ram_a_addr),.b_addr(ram_b_addr),.a_data(ram_data),.a_q(ram_a_q),.b_q(ram_b_q));
    weight_bram weights(.clk(clk),.we(weight_pending && !rst && !clear_load),.re(weight_re),.waddr(load_address),.raddr(read_weight_address),.data(load_data[7:0]),.q(weight_q));
    sync_bram #(.WIDTH(32),.AW(10),.DEPTH(1024)) biases(.clk(clk),.we(bias_pending && !rst && !clear_load),.re(coeff_re),.waddr(load_address[9:0]),.raddr(param_address),.data(load_data),.q(bias_q));
    sync_bram #(.WIDTH(32),.AW(10),.DEPTH(1024)) multipliers(.clk(clk),.we(n_pending && !rst && !clear_load),.re(coeff_re),.waddr(load_address[9:0]),.raddr(param_address),.data(load_data),.q(n_q));
    sync_bram #(.WIDTH(5),.AW(10),.DEPTH(1024)) shifts(.clk(clk),.we(shift_pending && !rst && !clear_load),.re(coeff_re),.waddr(load_address[9:0]),.raddr(param_address),.data(load_data[4:0]),.q(shift_q));
    mul_serial multiply(.clk(clk),.clear(rst || clear_load),.start(state==MUL_START),.ready(mul_ready),.busy(unused_mul_busy),.valid(mul_valid),
        .take(state==MUL_WAIT),.add_second(op.kind==1),.lhs1(mul_lhs1),.lhs2(mul_lhs2),.n1(mul_n1),.n2(mul_n2),.result(mul_result));
    rne_serial rounding(.clk(clk),.clear(rst || clear_load),.start(state==ROUND_START),.ready(round_ready),.busy(unused_round_busy),.valid(round_valid),
        .take(state==ROUND_WAIT),.wide(wide_value),.shift(round_shift),.mode(round_mode),.rounded(unused_rounded),.code(round_code));
    argmax10 maximum(.clk(clk),.clear(rst || clear_load || (start && start_ready)),
        .fire(trace_valid && trace_ready && op.kind==3),.index(out_idx[3:0]),.score(trace_code),.prediction(prediction),.best_score(unused_best));

    always_comb begin
        oc=0;oy=0;ox=0;
        case(op.olog)
            5:begin oc={3'd0,out_idx[13:10]};oy=out_idx[9:5];ox=out_idx[4:0];end
            4:begin oc={2'd0,out_idx[12:8]};oy={1'd0,out_idx[7:4]};ox={1'd0,out_idx[3:0]};end
            3:begin oc={1'd0,out_idx[11:6]};oy={2'd0,out_idx[5:3]};ox={2'd0,out_idx[2:0]};end
            default:oc=out_idx[6:0];
        endcase
        iy=($signed({2'd0,oy}) <<< op.stride2)+$signed({5'd0,ky})-7'sd1;
        ix=($signed({2'd0,ox}) <<< op.stride2)+$signed({5'd0,kx})-7'sd1;
        inside_input=iy>=0 && iy<$signed({1'd0,op.ih}) && ix>=0 && ix<$signed({1'd0,op.ih});
        case(op.ilog)
            5:x_address={ic[3:0],iy[4:0],ix[4:0]};
            4:x_address={1'd0,ic[4:0],iy[3:0],ix[3:0]};
            default:x_address={2'd0,ic,iy[2:0],ix[2:0]};
        endcase
        if(op.kind==2) begin x_address={2'd0,oc[5:0],term_idx[5:0]};inside_input=1;end
        if(op.kind==3) begin x_address={8'd0,term_idx[5:0]};inside_input=1;end
        skip_channel=5'(oc-(op.ci>>1));
        skip_inside=!op.option_a || (oc>=(op.ci>>1) && oc<op.ci+(op.ci>>1));
        if(!op.option_a) skip_address=out_idx;
        else if(op.ilog==5) skip_address={skip_channel[3:0],oy[3:0],1'b0,ox[3:0],1'b0};
        else skip_address={1'd0,skip_channel[4:0],oy[2:0],1'b0,ox[2:0],1'b0};
        channel_last=(out_idx[9:0] & op.mask)==op.mask;
        w_address=channel_wbase+{9'd0,term_idx};
        acc_next={acc[31],acc}+(op.kind==2?{{25{pair_x[7]}},pair_x}:{{17{product[15]}},product});
        mul_lhs1=op.kind==1?main_value:acc;mul_lhs2=op.kind==1?skip_value:32'sd0;
        mul_n1=op.kind==1?op.main_n:active_n;mul_n2=op.kind==1?op.skip_n:31'd0;
        round_shift=op.kind==1?op.r:active_r;
        round_mode=op.kind==3?2'd2:(op.relu?2'd1:2'd0);
        clear_load=load_begin && (state==IDLE || state==FAILED);
        prepared=armed && input_count==3072 && weight_count==268336 && bias_count==698 && n_count==698 && shift_count==698;
        cfg_ready=!rst && state==IDLE && !load_begin && !start;
        start_ready=!rst && state==IDLE && prepared && !load_begin && !cfg_valid;
        cfg_fire=cfg_valid && cfg_ready;
        input_we=cfg_fire && cfg_kind==0 && cfg_addr==19'(input_count) && cfg_addr<3072 && cfg_data[31:8]==0;
        weight_we=cfg_fire && cfg_kind==1 && cfg_addr==weight_count && cfg_addr<268336 && cfg_data[31:8]==0 && cfg_data[7:0]!=8'h80;
        bias_we=cfg_fire && cfg_kind==2 && cfg_addr==19'(bias_count) && cfg_addr<698;
        n_we=cfg_fire && cfg_kind==3 && cfg_addr==19'(n_count) && cfg_addr<698 && !cfg_data[31];
        shift_we=cfg_fire && cfg_kind==4 && cfg_addr==19'(shift_count) && cfg_addr<698 && cfg_data<=31;
        coeff_re=!rst && state==INIT && (op.kind==0 || op.kind==3);
        weight_re=!rst && state==READ_PAIR && op.kind!=2 && read_weight_address<268336;
        busy=state!=IDLE && state!=FAILED;
        step_valid=!rst && state==MAC;mac_fire=step_valid && compute_ready && op.kind!=2;gap_fire=step_valid && compute_ready && op.kind==2;
        trace_valid=!rst && state==TRACE_HOLD;trace_op=op_id;trace_addr=out_idx;rsp_valid=!rst && state==RESP;
        score_read_data=score_read_addr<10?scores[score_read_addr]:32'sd0;
        ram_a_en=0;ram_a_we=0;ram_b_en=0;ram_a_addr=0;ram_b_addr=0;ram_data=0;
        if(!rst) begin
            if(input_pending && !clear_load) begin ram_a_en=1;ram_a_we=1;ram_a_addr={2'd0,load_address[13:0]};ram_data=load_data[7:0];end
            else if(state==TRACE_HOLD && trace_ready && op.kind!=3) begin ram_a_en=1;ram_a_we=1;ram_a_addr={op.dst,out_idx};ram_data=trace_code[7:0];end
            else if(state==READ_PAIR && read_a_inside) begin ram_a_en=1;ram_a_addr=read_a_address;end
            else if(state==ADD_READ) begin
                ram_a_en=1;ram_a_addr=read_a_address;
                if(read_b_inside) begin ram_b_en=1;ram_b_addr=read_b_address;end
            end
        end
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;op<='0;armed<=0;input_count<=0;weight_count<=0;bias_count<=0;n_count<=0;shift_count<=0;
            input_pending<=0;weight_pending<=0;bias_pending<=0;n_pending<=0;shift_pending<=0;load_address<=0;load_data<=0;
            read_a_address<=0;read_b_address<=0;read_a_inside<=0;read_b_inside<=0;read_weight_address<=0;
            op_id<=0;out_idx<=0;term_idx<=0;param_address<=0;channel_wbase<=0;ic<=0;ky<=0;kx<=0;
            pair_x<=0;pair_w<=0;product<=0;acc<=0;active_n<=0;active_r<=0;main_value<=0;skip_value<=0;wide_value<=0;
            trace_acc<=0;trace_code<=0;trace_skip<=0;trace_wide<=0;trace_skip_from_x<=0;trace_skip_addr<=0;
            load_error<=0;start_rejected<=0;done<=0;fault<=0;fault_code<=0;result_valid<=0;
            for(integer i=0;i<10;i=i+1) scores[i]<=0;
        end else begin
            load_error<=0;start_rejected<=0;done<=0;
            input_pending<=input_we;weight_pending<=weight_we;bias_pending<=bias_we;n_pending<=n_we;shift_pending<=shift_we;
            if(input_we || weight_we || bias_we || n_we || shift_we) begin load_address<=cfg_addr;load_data<=cfg_data;end
            if(start && !start_ready) start_rejected<=1;
            if(clear_load) begin state<=IDLE;armed<=1;input_count<=0;weight_count<=0;bias_count<=0;n_count<=0;shift_count<=0;fault<=0;fault_code<=0;result_valid<=0;end
            else begin
                if(cfg_fire) begin
                    if(input_we) input_count<=input_count+1;
                    else if(weight_we) weight_count<=weight_count+1;
                    else if(bias_we) bias_count<=bias_count+1;
                    else if(n_we) n_count<=n_count+1;
                    else if(shift_we) shift_count<=shift_count+1;
                    else load_error<=1;
                end
                case(state)
                    IDLE:if(start && start_ready) begin armed<=0;op_id<=0;out_idx<=0;result_valid<=0;state<=FETCH;end
                    FETCH:begin
                        if(op_id>=30) begin fault<=1;fault_code<=3;state<=FAILED;end
                        else begin op<=decoded;out_idx<=0;channel_wbase<=decoded_wbase;param_address<=decoded_pbase;state<=decoded.kind==1?ADD_ADDRESS:INIT;end
                    end
                    INIT:begin
                        term_idx<=0;ic<=0;ky<=0;kx<=0;trace_skip<=0;trace_skip_from_x<=0;trace_skip_addr<=0;
                        state<=PARAM_WAIT;
                    end
                    PARAM_WAIT:state<=PARAM_LATCH;
                    PARAM_LATCH:begin
                        if(op.kind==2) begin acc<=0;active_n<=op.main_n;active_r<=op.r;end
                        else begin acc<=bias_q;active_n<=n_q[30:0];active_r<=shift_q;end
                        if(op.kind!=2 && (param_address>=698 || n_q[31])) begin fault<=1;fault_code<=2;state<=FAILED;end
                        else state<=ADDRESS;
                    end
                    ADDRESS:begin read_a_address<={op.src,x_address};read_a_inside<=inside_input;read_weight_address<=w_address;state<=READ_PAIR;end
                    READ_PAIR:begin
                        if(op.kind!=2 && read_weight_address>=268336) begin fault<=1;fault_code<=2;state<=FAILED;end
                        else state<=READ_WAIT;
                    end
                    READ_WAIT:state<=READ_LATCH;
                    READ_LATCH:begin pair_x<=read_a_inside?ram_a_q:8'sd0;pair_w<=op.kind==2?8'sd0:weight_q;state<=PRODUCT;end
                    PRODUCT:begin product<=pair_x*pair_w;state<=MAC;end
                    MAC:if(compute_ready) begin
                        if(acc_next>33'sd2147483647 || acc_next< -33'sd2147483648) begin fault<=1;fault_code<=1;state<=FAILED;end
                        else begin
                            acc<=acc_next[31:0];
                            if(term_idx==op.terms-1) state<=MUL_START;
                            else begin
                                term_idx<=term_idx+1;
                                if(kx==2) begin kx<=0;if(ky==2) begin ky<=0;ic<=ic+1;end else ky<=ky+1;end else kx<=kx+1;
                                state<=ADDRESS;
                            end
                        end
                    end
                    ADD_ADDRESS:begin read_a_address<={op.src,out_idx};read_b_address<={op.skip,skip_address};read_b_inside<=skip_inside;state<=ADD_READ;end
                    ADD_READ:state<=ADD_LATCH;
                    ADD_LATCH:begin
                        main_value<={{24{ram_a_q[7]}},ram_a_q};skip_value<=read_b_inside?{{24{ram_b_q[7]}},ram_b_q}:32'sd0;
                        trace_skip<=read_b_inside?ram_b_q:8'sd0;trace_skip_from_x<=read_b_inside;trace_skip_addr<=read_b_inside?read_b_address[13:0]:14'd0;state<=MUL_START;
                    end
                    MUL_START:if(mul_ready) state<=MUL_WAIT;
                    MUL_WAIT:if(mul_valid) begin wide_value<=mul_result;trace_acc<=op.kind==1?32'sd0:acc;state<=ROUND_START;end
                    ROUND_START:if(round_ready) state<=ROUND_WAIT;
                    ROUND_WAIT:if(round_valid) begin trace_code<=round_code;trace_wide<=wide_value;state<=TRACE_HOLD;end
                    TRACE_HOLD:if(trace_ready) begin
                        if(op.kind==3) scores[out_idx[3:0]]<=trace_code;
                        if(out_idx==op.last) begin
                            if(op_id==29) begin state<=RESP;result_valid<=1;end else begin op_id<=op_id+1;state<=FETCH;end
                        end else begin
                            out_idx<=out_idx+1;
                            if(channel_last) begin channel_wbase<=channel_wbase+{9'd0,op.terms};param_address<=param_address+1;end
                            state<=op.kind==1?ADD_ADDRESS:INIT;
                        end
                    end
                    RESP:if(rsp_ready) begin done<=1;state<=IDLE;end
                    FAILED:begin end
                    default:begin fault<=1;fault_code<=3;state<=FAILED;end
                endcase
            end
        end
    end
endmodule
