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
    typedef enum logic [3:0] {IDLE,FETCH,INIT,READ_PAIR,MAC,QUANT,TRACE_HOLD,ADD_READ,RESP,FAILED} state_t;
    state_t state;
    logic armed,clear_load;
    logic signed [7:0] act_mem[0:2][0:16383],w_mem[0:268335];
    logic signed [31:0] b_mem[0:697],n_mem[0:697],scores[0:9];
    logic [4:0] r_mem[0:697];
    logic [4:0] op_id;
    logic [13:0] out_idx;
    logic [9:0] term_idx;
    integer d_kind,d_ci,d_ih,d_co,d_oh,d_stride,d_relu,d_src,d_dst,d_option_a,d_wbase,d_pbase,d_main_n,d_skip_n;
    logic [1:0] d_skip;
    logic [4:0] d_r;
    `include "full_graph.svh"
    integer out_n,k,oc,oy,ox,ci,iy,ix,x_address,w_address,p_address,skip_address;
    logic inside_input,skip_inside;
    logic signed [7:0] pair_x,pair_w;
    logic signed [15:0] product;
    logic signed [31:0] acc,active_n;
    logic signed [32:0] acc_next;
    logic [4:0] active_r;
    logic signed [63:0] add_value,post_wide,unused_rounded;
    logic [4:0] post_shift;
    logic [1:0] post_mode;
    logic signed [31:0] post_code,unused_best_score;
    requant_full post(.wide(post_wide),.shift(post_shift),.mode(post_mode),.rounded(unused_rounded),.code(post_code));
    argmax10 maximum(.clk(clk),.clear(rst || clear_load || (start && start_ready)),
        .fire(trace_valid && trace_ready && d_kind==3),.index(out_idx[3:0]),.score(trace_code),.prediction(prediction),.best_score(unused_best_score));
    always_comb begin
        out_n=d_co*d_oh*d_oh;oc=int'(out_idx)/(d_oh==0?1:d_oh*d_oh);
        oy=(int'(out_idx)%(d_oh==0?1:d_oh*d_oh))/(d_oh==0?1:d_oh);ox=int'(out_idx)%(d_oh==0?1:d_oh);
        k=d_kind==2?64:(d_kind==3?64:d_ci*9);
        ci=int'(term_idx)/9;iy=oy*d_stride+(int'(term_idx)%9)/3-1;ix=ox*d_stride+int'(term_idx)%3-1;
        inside_input=iy>=0 && iy<d_ih && ix>=0 && ix<d_ih;
        x_address=(ci*d_ih+iy)*d_ih+ix;
        w_address=d_wbase+oc*k+int'(term_idx);p_address=d_pbase+oc;
        if(d_kind==2) begin x_address=int'(out_idx)*64+int'(term_idx);inside_input=1;end
        if(d_kind==3) begin x_address=int'(term_idx);inside_input=1;end
        skip_inside=d_option_a==0 || (oc>=d_ci/2 && oc<d_ci/2+d_ci);
        skip_address=d_option_a==0?int'(out_idx):((oc-d_ci/2)*d_ih+2*oy)*d_ih+2*ox;
        product=pair_x*pair_w;
        if(d_kind==2) acc_next={acc[31],acc}+{{25{pair_x[7]}},pair_x};
        else acc_next={acc[31],acc}+{{17{product[15]}},product};
        post_wide=d_kind==1?add_value:{{32{acc[31]}},acc}*{{32{active_n[31]}},active_n};
        post_shift=d_kind==1?5'(d_r):active_r;
        post_mode=d_kind==3?2'd2:(d_relu!=0?2'd1:2'd0);
        clear_load=load_begin && (state==IDLE || state==FAILED);
        prepared=armed && input_count==3072 && weight_count==268336 && bias_count==698 && n_count==698 && shift_count==698;
        cfg_ready=!rst && state==IDLE && !load_begin && !start;
        start_ready=!rst && state==IDLE && prepared && !load_begin && !cfg_valid;
        busy=state!=IDLE && state!=FAILED;
        step_valid=!rst && state==MAC;
        mac_fire=step_valid && compute_ready && d_kind!=2;
        gap_fire=step_valid && compute_ready && d_kind==2;
        trace_valid=!rst && state==TRACE_HOLD;trace_op=op_id;trace_addr=out_idx;
        rsp_valid=!rst && state==RESP;
        score_read_data=score_read_addr<10?scores[score_read_addr]:32'sd0;
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;armed<=0;input_count<=0;weight_count<=0;bias_count<=0;n_count<=0;shift_count<=0;
            op_id<=0;out_idx<=0;term_idx<=0;pair_x<=0;pair_w<=0;acc<=0;active_n<=0;active_r<=0;add_value<=0;
            trace_acc<=0;trace_code<=0;trace_skip<=0;trace_wide<=0;trace_skip_from_x<=0;trace_skip_addr<=0;
            load_error<=0;start_rejected<=0;done<=0;fault<=0;fault_code<=0;result_valid<=0;
            for(integer i=0;i<10;i=i+1) scores[i]<=0;
        end else begin
            load_error<=0;start_rejected<=0;done<=0;
            if(start && !start_ready) start_rejected<=1;
            if(clear_load) begin
                state<=IDLE;armed<=1;input_count<=0;weight_count<=0;bias_count<=0;n_count<=0;shift_count<=0;
                fault<=0;fault_code<=0;result_valid<=0;
            end else begin
                if(cfg_valid && cfg_ready) case(cfg_kind)
                    0: if(cfg_addr==19'(input_count) && cfg_addr<3072 && cfg_data[31:8]==0) begin
                        act_mem[0][cfg_addr[13:0]]<=cfg_data[7:0];input_count<=input_count+1;
                    end else load_error<=1;
                    1: if(cfg_addr==weight_count && cfg_addr<268336 && cfg_data[31:8]==0 && cfg_data[7:0]!=8'h80) begin
                        w_mem[cfg_addr]<=cfg_data[7:0];weight_count<=weight_count+1;
                    end else load_error<=1;
                    2: if(cfg_addr==19'(bias_count) && cfg_addr<698) begin
                        b_mem[cfg_addr[9:0]]<=cfg_data;bias_count<=bias_count+1;
                    end else load_error<=1;
                    3: if(cfg_addr==19'(n_count) && cfg_addr<698 && !cfg_data[31]) begin
                        n_mem[cfg_addr[9:0]]<=cfg_data;n_count<=n_count+1;
                    end else load_error<=1;
                    4: if(cfg_addr==19'(shift_count) && cfg_addr<698 && cfg_data<=31) begin
                        r_mem[cfg_addr[9:0]]<=cfg_data[4:0];shift_count<=shift_count+1;
                    end else load_error<=1;
                    default:load_error<=1;
                endcase
                case(state)
                    IDLE: if(start && start_ready) begin armed<=0;op_id<=0;out_idx<=0;result_valid<=0;state<=FETCH;end
                    FETCH: begin
                        if(op_id>=30 || d_src<0 || d_src>2 || (d_kind!=3 && (d_dst<0 || d_dst>2)) || out_n<1 || out_n>16384) begin
                            fault<=1;fault_code<=3;state<=FAILED;
                        end else begin out_idx<=0;state<=d_kind==1?ADD_READ:INIT;end
                    end
                    INIT: begin
                        term_idx<=0;trace_skip<=0;trace_skip_from_x<=0;trace_skip_addr<=0;
                        if(d_kind==2) begin acc<=0;active_n<=d_main_n;active_r<=5'(d_r);end
                        else begin acc<=b_mem[p_address];active_n<=n_mem[p_address];active_r<=r_mem[p_address];end
                        if(d_kind!=2 && (p_address<0 || p_address>=698)) begin fault<=1;fault_code<=2;state<=FAILED;end
                        else state<=READ_PAIR;
                    end
                    READ_PAIR: begin
                        if((inside_input && (x_address<0 || x_address>=16384)) || (d_kind!=2 && (w_address<0 || w_address>=268336))) begin
                            fault<=1;fault_code<=2;state<=FAILED;
                        end else begin
                            pair_x<=inside_input?act_mem[d_src][x_address]:8'sd0;
                            pair_w<=d_kind==2?8'sd0:w_mem[w_address];state<=MAC;
                        end
                    end
                    MAC: if(compute_ready) begin
                        if(acc_next>33'sd2147483647 || acc_next< -33'sd2147483648) begin fault<=1;fault_code<=1;state<=FAILED;end
                        else begin
                            acc<=acc_next[31:0];
                            if(int'(term_idx)==k-1) state<=QUANT;
                            else begin term_idx<=term_idx+1;state<=READ_PAIR;end
                        end
                    end
                    ADD_READ: begin
                        trace_skip_from_x<=skip_inside;trace_skip_addr<=skip_inside?14'(skip_address):14'd0;
                        if(skip_inside && (skip_address<0 || skip_address>=16384)) begin fault<=1;fault_code<=2;state<=FAILED;end
                        else if(skip_inside) begin
                            trace_skip<=act_mem[d_skip][skip_address];
                            add_value<={{56{act_mem[d_src][out_idx][7]}},act_mem[d_src][out_idx]}*{{32{d_main_n[31]}},d_main_n}
                                +{{56{act_mem[d_skip][skip_address][7]}},act_mem[d_skip][skip_address]}*{{32{d_skip_n[31]}},d_skip_n};
                        end else begin
                            trace_skip<=0;add_value<={{56{act_mem[d_src][out_idx][7]}},act_mem[d_src][out_idx]}*{{32{d_main_n[31]}},d_main_n};
                        end
                        if(!skip_inside || (skip_address>=0 && skip_address<16384)) state<=QUANT;
                    end
                    QUANT: begin trace_acc<=d_kind==1?32'sd0:acc;trace_code<=post_code;trace_wide<=post_wide;state<=TRACE_HOLD;end
                    TRACE_HOLD: if(trace_ready) begin
                        if(d_kind==3) scores[out_idx[3:0]]<=trace_code;
                        else act_mem[d_dst][out_idx]<=trace_code[7:0];
                        if(int'(out_idx)==out_n-1) begin
                            if(op_id==29) begin state<=RESP;result_valid<=1;end
                            else begin op_id<=op_id+1;state<=FETCH;end
                        end else begin out_idx<=out_idx+1;state<=d_kind==1?ADD_READ:INIT;end
                    end
                    RESP: if(rsp_ready) begin done<=1;state<=IDLE;end
                    FAILED:begin end
                    default:begin fault<=1;fault_code<=3;state<=FAILED;end
                endcase
            end
        end
    end
endmodule
