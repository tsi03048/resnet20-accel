`timescale 1ns/1ps
// Actual E2-B Identity L1.0: C16/H32, one shared serial Conv datapath.
// A=X is preserved; B=H then Y after Conv2 drains; C=M preserves negatives.
// Native loader only; Golden/readmemh are confined to the testbench.
module residual_block(
    input logic clk, rst, load_begin, cfg_valid,
    output logic cfg_ready,
    input logic [3:0] cfg_kind,
    input logic [14:0] cfg_addr,
    input logic [31:0] cfg_data,
    output logic load_error, prepared,
    output logic [14:0] input_count,
    output logic [11:0] weight1_count, weight2_count,
    output logic [4:0] bias1_count,bias2_count,n1_count,n2_count,s1_count,s2_count,
    output logic [1:0] add_count,
    input logic start,
    output logic start_ready,start_rejected,busy,compute_error,
    output logic rsp_valid,done,
    input logic rsp_ready,mac_ready,
    output logic mac_valid,mac_fire,
    output logic conv_valid,
    input logic conv_ready,
    output logic conv_phase,
    output logic [13:0] conv_addr,
    output logic signed [31:0] conv_acc,
    output logic signed [7:0] conv_code,
    output logic y_valid,
    input logic y_ready,
    output logic [13:0] y_addr,
    output logic signed [7:0] y_code,
    output logic signed [7:0] add_main,add_skip,
    output logic signed [63:0] add_wide
);
    typedef enum logic [3:0] {IDLE,INIT,READ_PAIR,MAC,CONV_QUANT,CONV_HOLD,
                              ADD_READ,ADD_QUANT,ADD_HOLD,RESP} state_t;
    state_t state;
    logic signed [7:0] x_mem[0:16383],work_mem[0:16383],main_mem[0:16383];
    logic signed [7:0] w_mem[0:4607];
    logic signed [31:0] b_mem[0:31],n_mem[0:31];
    logic [4:0] s_mem[0:31];
    logic [16383:0] x_seen;
    logic [2303:0] w1_seen,w2_seen;
    logic [15:0] b1_seen,b2_seen,n1_seen,n2_seen,s1_seen,s2_seen;
    logic [2:0] add_seen;
    logic signed [31:0] add_nm,add_ns,active_nm,active_ns;
    logic [4:0] add_shift,active_add_shift;
    logic phase;
    logic [13:0] out_idx;
    logic [7:0] term_idx;
    logic signed [7:0] pair_x,pair_w;
    logic signed [15:0] product;
    logic signed [31:0] acc,active_n;
    logic signed [32:0] acc_next;
    logic [4:0] active_shift,post_shift;
    logic signed [63:0] post_wide,unused_rounded;
    logic signed [7:0] post_code;
    logic post_relu,inside_input;
    integer oc,ci,iy,ix;
    logic [4:0] param_idx;
    logic [13:0] x_offset;
    logic [12:0] w_offset;
    rne_clip post(.wide(post_wide),.shift(post_shift),.relu(post_relu),.rounded(unused_rounded),.code(post_code));
    always_comb begin
        oc=int'(out_idx)/1024; ci=int'(term_idx)/9;
        iy=(int'(out_idx)%1024)/32+(int'(term_idx)%9)/3-1;
        ix=int'(out_idx)%32+int'(term_idx)%3-1;
        inside_input=iy>=0 && iy<32 && ix>=0 && ix<32;
        x_offset=14'(ci*1024+iy*32+ix);
        w_offset=13'((phase?2304:0)+oc*144+int'(term_idx));
        param_idx=5'((phase?16:0)+oc);
        product=pair_x*pair_w;
        acc_next={acc[31],acc}+{{17{product[15]}},product};
        prepared=input_count==16384 && weight1_count==2304 && weight2_count==2304 &&
                 bias1_count==16 && bias2_count==16 && n1_count==16 && n2_count==16 && s1_count==16 && s2_count==16 && add_count==3;
        cfg_ready=!rst && state==IDLE && !load_begin && !start;
        start_ready=!rst && state==IDLE && prepared && !load_begin && !cfg_valid;
        busy=state!=IDLE;
        mac_valid=!rst && state==MAC; mac_fire=mac_valid && mac_ready;
        conv_valid=!rst && state==CONV_HOLD; conv_phase=phase; conv_addr=out_idx;
        y_valid=!rst && state==ADD_HOLD; y_addr=out_idx;
        rsp_valid=!rst && state==RESP;
        post_wide={{32{acc[31]}},acc}*{{32{active_n[31]}},active_n};
        post_shift=active_shift; post_relu=!phase;
        if(state==ADD_QUANT || state==ADD_HOLD) begin
            post_wide=add_wide; post_shift=active_add_shift; post_relu=1;
        end
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;phase<=0;out_idx<=0;term_idx<=0;acc<=0;active_n<=0;active_shift<=0;
            pair_x<=0;pair_w<=0;conv_acc<=0;conv_code<=0;y_code<=0;add_main<=0;add_skip<=0;add_wide<=0;
            active_nm<=0;active_ns<=0;active_add_shift<=0;
            add_nm<=0;add_ns<=0;add_shift<=0;
            done<=0;compute_error<=0;load_error<=0;start_rejected<=0;
            x_seen[8191:0]<='0;x_seen[16383:8192]<='0;w1_seen<='0;w2_seen<='0;b1_seen<='0;b2_seen<='0;n1_seen<='0;n2_seen<='0;s1_seen<='0;s2_seen<='0;add_seen<=0;
            input_count<=0;weight1_count<=0;weight2_count<=0;bias1_count<=0;bias2_count<=0;
            n1_count<=0;n2_count<=0;s1_count<=0;s2_count<=0;add_count<=0;
        end else begin
            done<=0;load_error<=0;start_rejected<=0;
            if(start && !start_ready) start_rejected<=1;
            if(load_begin && state==IDLE) begin
                x_seen[8191:0]<='0;x_seen[16383:8192]<='0;w1_seen<='0;w2_seen<='0;b1_seen<='0;b2_seen<='0;n1_seen<='0;n2_seen<='0;s1_seen<='0;s2_seen<='0;add_seen<=0;
                input_count<=0;weight1_count<=0;weight2_count<=0;bias1_count<=0;bias2_count<=0;
                n1_count<=0;n2_count<=0;s1_count<=0;s2_count<=0;add_count<=0;compute_error<=0;
            end
            if(cfg_valid && cfg_ready) case(cfg_kind)
                0: if(cfg_addr<16384 && cfg_data[31:8]==0) begin
                    x_mem[cfg_addr[13:0]]<=cfg_data[7:0];
                    if(!x_seen[cfg_addr[13:0]]) input_count<=input_count+1;
                    x_seen[cfg_addr[13:0]]<=1;
                end else load_error<=1;
                1: if(cfg_addr<2304 && cfg_data[31:8]==0 && cfg_data[7:0]!=8'h80) begin
                    w_mem[{1'b0,cfg_addr[11:0]}]<=cfg_data[7:0];
                    if(!w1_seen[cfg_addr[11:0]]) weight1_count<=weight1_count+1;
                    w1_seen[cfg_addr[11:0]]<=1;
                end else load_error<=1;
                2: if(cfg_addr<2304 && cfg_data[31:8]==0 && cfg_data[7:0]!=8'h80) begin
                    w_mem[13'(2304+int'(cfg_addr))]<=cfg_data[7:0];
                    if(!w2_seen[cfg_addr[11:0]]) weight2_count<=weight2_count+1;
                    w2_seen[cfg_addr[11:0]]<=1;
                end else load_error<=1;
                3: if(cfg_addr<16) begin
                    b_mem[{1'b0,cfg_addr[3:0]}]<=cfg_data;
                    if(!b1_seen[cfg_addr[3:0]]) bias1_count<=bias1_count+1;
                    b1_seen[cfg_addr[3:0]]<=1;
                end else load_error<=1;
                4: if(cfg_addr<16) begin
                    b_mem[{1'b1,cfg_addr[3:0]}]<=cfg_data;
                    if(!b2_seen[cfg_addr[3:0]]) bias2_count<=bias2_count+1;
                    b2_seen[cfg_addr[3:0]]<=1;
                end else load_error<=1;
                5: if(cfg_addr<16 && !cfg_data[31]) begin
                    n_mem[{1'b0,cfg_addr[3:0]}]<=cfg_data;
                    if(!n1_seen[cfg_addr[3:0]]) n1_count<=n1_count+1;
                    n1_seen[cfg_addr[3:0]]<=1;
                end else load_error<=1;
                6: if(cfg_addr<16 && !cfg_data[31]) begin
                    n_mem[{1'b1,cfg_addr[3:0]}]<=cfg_data;
                    if(!n2_seen[cfg_addr[3:0]]) n2_count<=n2_count+1;
                    n2_seen[cfg_addr[3:0]]<=1;
                end else load_error<=1;
                7: if(cfg_addr<16 && cfg_data<=31) begin
                    s_mem[{1'b0,cfg_addr[3:0]}]<=cfg_data[4:0];
                    if(!s1_seen[cfg_addr[3:0]]) s1_count<=s1_count+1;
                    s1_seen[cfg_addr[3:0]]<=1;
                end else load_error<=1;
                8: if(cfg_addr<16 && cfg_data<=31) begin
                    s_mem[{1'b1,cfg_addr[3:0]}]<=cfg_data[4:0];
                    if(!s2_seen[cfg_addr[3:0]]) s2_count<=s2_count+1;
                    s2_seen[cfg_addr[3:0]]<=1;
                end else load_error<=1;
                9: if(cfg_addr<3 && ((cfg_addr<2 && !cfg_data[31]) || (cfg_addr==2 && cfg_data<=31))) begin
                    case(cfg_addr)
                        0:add_nm<=cfg_data;
                        1:add_ns<=cfg_data;
                        2:add_shift<=cfg_data[4:0];
                        default:begin end
                    endcase
                    if(!add_seen[cfg_addr[1:0]]) add_count<=add_count+1;
                    add_seen[cfg_addr[1:0]]<=1;
                end else load_error<=1;
                default:load_error<=1;
            endcase
            case(state)
                IDLE: if(start && start_ready) begin
                    phase<=0;out_idx<=0;compute_error<=0;active_nm<=add_nm;active_ns<=add_ns;
                    active_add_shift<=add_shift;state<=INIT;
                end
                INIT: begin
                    acc<=b_mem[param_idx];active_n<=n_mem[param_idx];active_shift<=s_mem[param_idx];
                    term_idx<=0;state<=READ_PAIR;
                end
                READ_PAIR: begin
                    if(inside_input) pair_x<=phase?work_mem[x_offset]:x_mem[x_offset]; else pair_x<=0;
                    pair_w<=w_mem[w_offset];state<=MAC;
                end
                MAC: if(mac_ready) begin
                    if(acc_next>33'sd2147483647 || acc_next< -33'sd2147483648) begin
                        compute_error<=1;state<=IDLE;
                    end else begin
                        acc<=acc_next[31:0];
                        if(term_idx==143) state<=CONV_QUANT;
                        else begin term_idx<=term_idx+1;state<=READ_PAIR;end
                    end
                end
                CONV_QUANT: begin conv_acc<=acc;conv_code<=post_code;state<=CONV_HOLD;end
                CONV_HOLD: if(conv_ready) begin
                    if(phase) main_mem[out_idx]<=conv_code; else work_mem[out_idx]<=conv_code;
                    if(out_idx==16383) begin
                        out_idx<=0;
                        if(phase) state<=ADD_READ;else begin phase<=1;state<=INIT;end
                    end else begin out_idx<=out_idx+1;state<=INIT;end
                end
                ADD_READ: begin
                    add_main<=main_mem[out_idx];add_skip<=x_mem[out_idx];
                    add_wide<={{56{main_mem[out_idx][7]}},main_mem[out_idx]}*{{32{active_nm[31]}},active_nm}
                            +{{56{x_mem[out_idx][7]}},x_mem[out_idx]}*{{32{active_ns[31]}},active_ns};
                    state<=ADD_QUANT;
                end
                ADD_QUANT: begin y_code<=post_code;state<=ADD_HOLD;end
                ADD_HOLD: if(y_ready) begin
                    work_mem[out_idx]<=y_code;
                    if(out_idx==16383) state<=RESP;else begin out_idx<=out_idx+1;state<=ADD_READ;end
                end
                RESP: if(rsp_ready) begin done<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
