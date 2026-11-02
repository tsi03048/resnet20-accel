`timescale 1ns/1ps
// Actual E2-B Transition L2.0 or L3.0: stride2 Conv1, stride1 Conv2, Option A.
// A=X is preserved; B=H then Y after Conv2 drains; C=M preserves negatives.
// Native loader only; Golden/readmemh are confined to the testbench.
module transition_block #(parameter integer STAGE=2)(

    input logic clk, rst, load_begin, cfg_valid,
    output logic cfg_ready,
    input logic [3:0] cfg_kind,
    input logic [15:0] cfg_addr,
    input logic [31:0] cfg_data,
    output logic load_error, prepared,
    output logic [15:0] input_count,
    output logic [15:0] weight1_count, weight2_count,
    output logic [7:0] bias1_count,bias2_count,n1_count,n2_count,s1_count,s2_count,
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
    output logic signed [63:0] add_wide,
    output logic skip_read,skip_from_x,
    output logic [13:0] skip_read_addr,skip_addr
);
    localparam integer CIN=(STAGE==2?16:32), H=(STAGE==2?32:16), COUT=2*CIN, OH=H/2;
    localparam integer NX=CIN*H*H, NY=COUT*OH*OH, K1=CIN*9, K2=COUT*9;
    localparam integer NW1=COUT*K1, NW2=COUT*K2, OAW=$clog2(NY), XAW=$clog2(NX), WAW=$clog2(NW1+NW2), PAW=$clog2(2*COUT);
    initial begin if(STAGE!=2 && STAGE!=3) $fatal(1,"Only stages 2 and 3 are supported");end
    typedef enum logic [3:0] {IDLE,INIT,READ_PAIR,MAC,CONV_QUANT,CONV_HOLD,
                              ADD_READ,ADD_QUANT,ADD_HOLD,RESP} state_t;
    state_t state;
    logic signed [7:0] x_mem[0:NX-1],work_mem[0:NY-1],main_mem[0:NY-1];
    logic signed [7:0] w_mem[0:NW1+NW2-1];
    logic signed [31:0] b_mem[0:2*COUT-1],n_mem[0:2*COUT-1];
    logic [4:0] s_mem[0:2*COUT-1];
    logic [NX-1:0] x_seen;
    logic [NW1-1:0] w1_seen;
    logic [NW2-1:0] w2_seen;
    logic [COUT-1:0] b1_seen,b2_seen,n1_seen,n2_seen,s1_seen,s2_seen;
    logic [2:0] add_seen;
    logic signed [31:0] add_nm,add_ns,active_nm,active_ns;
    logic [4:0] add_shift,active_add_shift;
    logic phase;
    logic [OAW-1:0] out_idx;
    logic [9:0] term_idx;
    logic signed [7:0] pair_x,pair_w;
    logic signed [15:0] product;
    logic signed [31:0] acc,active_n;
    logic signed [32:0] acc_next;
    logic [4:0] active_shift,post_shift;
    logic signed [63:0] post_wide,unused_rounded;
    logic signed [7:0] post_code;
    logic post_relu,inside_input;
    integer oc,ci,iy,ix,oy,ox,source_h,active_k,active_stride;
    logic [13:0] skip_offset;
    logic skip_inside;
    logic [PAW-1:0] param_idx;
    logic [XAW-1:0] x_offset;
    logic [WAW-1:0] w_offset;
    rne_clip post(.wide(post_wide),.shift(post_shift),.relu(post_relu),.rounded(unused_rounded),.code(post_code));
    always_comb begin
        oc=int'(out_idx)/(OH*OH);oy=(int'(out_idx)%(OH*OH))/OH;ox=int'(out_idx)%OH;
        active_k=phase?K2:K1;active_stride=phase?1:2;source_h=phase?OH:H;
        ci=int'(term_idx)/9;
        iy=oy*active_stride+(int'(term_idx)%9)/3-1;
        ix=ox*active_stride+int'(term_idx)%3-1;
        inside_input=iy>=0 && iy<source_h && ix>=0 && ix<source_h;
        x_offset=XAW'(ci*source_h*source_h+iy*source_h+ix);
        w_offset=WAW'((phase?NW1:0)+oc*active_k+int'(term_idx));
        param_idx=PAW'((phase?COUT:0)+oc);
        skip_inside=oc>=CIN/2 && oc<CIN/2+CIN;
        skip_offset=14'((oc-CIN/2)*H*H+(2*oy)*H+2*ox);
        skip_read=!rst && state==ADD_READ && skip_inside;
        skip_read_addr=skip_inside?14'(skip_offset):14'd0;
        product=pair_x*pair_w;
        acc_next={acc[31],acc}+{{17{product[15]}},product};
        prepared=int'(input_count)==NX && int'(weight1_count)==NW1 && int'(weight2_count)==NW2 &&
                 int'(bias1_count)==COUT && int'(bias2_count)==COUT && int'(n1_count)==COUT && int'(n2_count)==COUT && int'(s1_count)==COUT && int'(s2_count)==COUT && add_count==3;
        cfg_ready=!rst && state==IDLE && !load_begin && !start;
        start_ready=!rst && state==IDLE && prepared && !load_begin && !cfg_valid;
        busy=state!=IDLE;
        mac_valid=!rst && state==MAC; mac_fire=mac_valid && mac_ready;
        conv_valid=!rst && state==CONV_HOLD; conv_phase=phase; conv_addr=14'(out_idx);
        y_valid=!rst && state==ADD_HOLD; y_addr=14'(out_idx);
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
            pair_x<=0;pair_w<=0;conv_acc<=0;conv_code<=0;y_code<=0;add_main<=0;add_skip<=0;add_wide<=0;skip_from_x<=0;skip_addr<=0;
            active_nm<=0;active_ns<=0;active_add_shift<=0;
            add_nm<=0;add_ns<=0;add_shift<=0;
            done<=0;compute_error<=0;load_error<=0;start_rejected<=0;
            for(integer q=0;q<NX;q=q+512) x_seen[q+:512]<='0;
            for(integer q=0;q<NW1;q=q+512) w1_seen[q+:512]<='0;
            for(integer q=0;q<NW2;q=q+512) w2_seen[q+:512]<='0;
            b1_seen<='0;b2_seen<='0;n1_seen<='0;n2_seen<='0;s1_seen<='0;s2_seen<='0;add_seen<=0;
            input_count<=0;weight1_count<=0;weight2_count<=0;bias1_count<=0;bias2_count<=0;
            n1_count<=0;n2_count<=0;s1_count<=0;s2_count<=0;add_count<=0;
        end else begin
            done<=0;load_error<=0;start_rejected<=0;
            if(start && !start_ready) start_rejected<=1;
            if(load_begin && state==IDLE) begin
                for(integer q=0;q<NX;q=q+512) x_seen[q+:512]<='0;
                for(integer q=0;q<NW1;q=q+512) w1_seen[q+:512]<='0;
                for(integer q=0;q<NW2;q=q+512) w2_seen[q+:512]<='0;
                b1_seen<='0;b2_seen<='0;n1_seen<='0;n2_seen<='0;s1_seen<='0;s2_seen<='0;add_seen<=0;
                input_count<=0;weight1_count<=0;weight2_count<=0;bias1_count<=0;bias2_count<=0;
                n1_count<=0;n2_count<=0;s1_count<=0;s2_count<=0;add_count<=0;compute_error<=0;
            end
            if(cfg_valid && cfg_ready) case(cfg_kind)
                0: if(int'(cfg_addr)<NX && cfg_data[31:8]==0) begin
                    x_mem[cfg_addr[XAW-1:0]]<=cfg_data[7:0];
                    if(!x_seen[cfg_addr[XAW-1:0]]) input_count<=input_count+1;
                    x_seen[cfg_addr[XAW-1:0]]<=1;
                end else load_error<=1;
                1: if(int'(cfg_addr)<NW1 && cfg_data[31:8]==0 && cfg_data[7:0]!=8'h80) begin
                    w_mem[WAW'(cfg_addr)]<=cfg_data[7:0];
                    if(!w1_seen[int'(cfg_addr)]) weight1_count<=weight1_count+1;
                    w1_seen[int'(cfg_addr)]<=1;
                end else load_error<=1;
                2: if(int'(cfg_addr)<NW2 && cfg_data[31:8]==0 && cfg_data[7:0]!=8'h80) begin
                    w_mem[WAW'(NW1+int'(cfg_addr))]<=cfg_data[7:0];
                    if(!w2_seen[int'(cfg_addr)]) weight2_count<=weight2_count+1;
                    w2_seen[int'(cfg_addr)]<=1;
                end else load_error<=1;
                3: if(int'(cfg_addr)<COUT) begin
                    b_mem[PAW'(cfg_addr)]<=cfg_data;
                    if(!b1_seen[int'(cfg_addr)]) bias1_count<=bias1_count+1;
                    b1_seen[int'(cfg_addr)]<=1;
                end else load_error<=1;
                4: if(int'(cfg_addr)<COUT) begin
                    b_mem[PAW'(COUT+int'(cfg_addr))]<=cfg_data;
                    if(!b2_seen[int'(cfg_addr)]) bias2_count<=bias2_count+1;
                    b2_seen[int'(cfg_addr)]<=1;
                end else load_error<=1;
                5: if(int'(cfg_addr)<COUT && !cfg_data[31]) begin
                    n_mem[PAW'(cfg_addr)]<=cfg_data;
                    if(!n1_seen[int'(cfg_addr)]) n1_count<=n1_count+1;
                    n1_seen[int'(cfg_addr)]<=1;
                end else load_error<=1;
                6: if(int'(cfg_addr)<COUT && !cfg_data[31]) begin
                    n_mem[PAW'(COUT+int'(cfg_addr))]<=cfg_data;
                    if(!n2_seen[int'(cfg_addr)]) n2_count<=n2_count+1;
                    n2_seen[int'(cfg_addr)]<=1;
                end else load_error<=1;
                7: if(int'(cfg_addr)<COUT && cfg_data<=31) begin
                    s_mem[PAW'(cfg_addr)]<=cfg_data[4:0];
                    if(!s1_seen[int'(cfg_addr)]) s1_count<=s1_count+1;
                    s1_seen[int'(cfg_addr)]<=1;
                end else load_error<=1;
                8: if(int'(cfg_addr)<COUT && cfg_data<=31) begin
                    s_mem[PAW'(COUT+int'(cfg_addr))]<=cfg_data[4:0];
                    if(!s2_seen[int'(cfg_addr)]) s2_count<=s2_count+1;
                    s2_seen[int'(cfg_addr)]<=1;
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
                    if(inside_input) pair_x<=phase?work_mem[int'(x_offset)]:x_mem[x_offset]; else pair_x<=0;
                    pair_w<=w_mem[w_offset];state<=MAC;
                end
                MAC: if(mac_ready) begin
                    if(acc_next>33'sd2147483647 || acc_next< -33'sd2147483648) begin
                        compute_error<=1;state<=IDLE;
                    end else begin
                        acc<=acc_next[31:0];
                        if(int'(term_idx)==active_k-1) state<=CONV_QUANT;
                        else begin term_idx<=term_idx+1;state<=READ_PAIR;end
                    end
                end
                CONV_QUANT: begin conv_acc<=acc;conv_code<=post_code;state<=CONV_HOLD;end
                CONV_HOLD: if(conv_ready) begin
                    if(phase) main_mem[out_idx]<=conv_code; else work_mem[out_idx]<=conv_code;
                    if(int'(out_idx)==NY-1) begin
                        out_idx<=0;
                        if(phase) state<=ADD_READ;else begin phase<=1;state<=INIT;end
                    end else begin out_idx<=out_idx+1;state<=INIT;end
                end
                ADD_READ: begin
                    add_main<=main_mem[out_idx];skip_from_x<=skip_read;skip_addr<=skip_read_addr;
                    if(skip_read) begin
                        add_skip<=x_mem[skip_read_addr[XAW-1:0]];
                        add_wide<={{56{main_mem[out_idx][7]}},main_mem[out_idx]}*{{32{active_nm[31]}},active_nm}
                            +{{56{x_mem[skip_read_addr[XAW-1:0]][7]}},x_mem[skip_read_addr[XAW-1:0]]}*{{32{active_ns[31]}},active_ns};
                    end else begin
                        add_skip<=0;
                        add_wide<={{56{main_mem[out_idx][7]}},main_mem[out_idx]}*{{32{active_nm[31]}},active_nm};
                    end
                    state<=ADD_QUANT;
                end
                ADD_QUANT: begin y_code<=post_code;state<=ADD_HOLD;end
                ADD_HOLD: if(y_ready) begin
                    work_mem[out_idx]<=y_code;
                    if(int'(out_idx)==NY-1) state<=RESP;else begin out_idx<=out_idx+1;state<=ADD_READ;end
                end
                RESP: if(rsp_ready) begin done<=1;state<=IDLE;end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
