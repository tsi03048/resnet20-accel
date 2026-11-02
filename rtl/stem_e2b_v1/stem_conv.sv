// Fixed actual ResNet-20 Stem: NCHW [1,3,32,32] -> [1,16,32,32].
// Native word loader, synchronous registered X/W reads, one serial MAC.
// No $readmemh, Golden, hierarchical preload, AXI, DMA or FPGA result claims in DUT.
module stem_conv(
    input logic clk, rst, load_begin,
    input logic cfg_valid,
    output logic cfg_ready,
    input logic [2:0] cfg_kind,
    input logic [11:0] cfg_addr,
    input logic [31:0] cfg_data,
    output logic load_error, prepared,
    output logic [11:0] input_count,
    output logic [8:0] weight_count,
    output logic [4:0] bias_count, multiplier_count, shift_count,
    input logic start,
    output logic start_ready, start_rejected, busy, done, compute_error,
    input logic mac_ready,
    output logic mac_valid, mac_fire,
    output logic y_valid,
    input logic y_ready,
    output logic [13:0] y_addr,
    output logic signed [31:0] y_acc,
    output logic signed [7:0] y_code
);
    typedef enum logic [2:0] {IDLE, INIT, READ_PAIR, MAC, REQUANT, STORE} state_t;
    state_t state;
    logic signed [7:0] x_mem[0:3071], w_mem[0:431];
    logic signed [31:0] bias_mem[0:15], n_mem[0:15];
    logic [4:0] shift_mem[0:15];
    logic [3071:0] x_seen;
    logic [431:0] w_seen;
    logic [15:0] b_seen, n_seen, s_seen;
    logic [13:0] out_idx;
    logic [4:0] term_idx, active_shift;
    logic signed [7:0] pair_x, pair_w;
    logic signed [15:0] product;
    logic signed [31:0] acc, active_n;
    logic signed [32:0] acc_next;
    logic signed [63:0] unused_rounded;
    logic signed [7:0] requant_code;
    integer oc, ci, iy, ix;
    logic [11:0] x_offset;
    logic [8:0] w_offset;
    logic inside_input;
    requant_rne_relu post(.acc(acc),.multiplier(active_n),.shift(active_shift),
                         .rounded(unused_rounded),.code(requant_code));
    always_comb begin
        oc = int'(out_idx) / 1024;
        ci = int'(term_idx) / 9;
        iy = (int'(out_idx) % 1024) / 32 + (int'(term_idx) % 9) / 3 - 1;
        ix = int'(out_idx) % 32 + int'(term_idx) % 3 - 1;
        inside_input = iy >= 0 && iy < 32 && ix >= 0 && ix < 32;
        x_offset = 12'(ci*1024 + iy*32 + ix);
        w_offset = 9'(oc*27 + int'(term_idx));
        product = pair_x * pair_w;
        acc_next = {acc[31],acc} + {{17{product[15]}},product};
        prepared = input_count == 3072 && weight_count == 432 && bias_count == 16
                    && multiplier_count == 16 && shift_count == 16;
        cfg_ready = !rst && state == IDLE && !load_begin && !start;
        start_ready = !rst && state == IDLE && prepared && !load_begin && !cfg_valid;
        busy = state != IDLE;
        mac_valid = !rst && state == MAC;
        mac_fire = mac_valid && mac_ready;
        y_valid = !rst && state == STORE;
        y_addr = out_idx;
    end
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE; done<=0; compute_error<=0; load_error<=0; start_rejected<=0;
            x_seen<='0; w_seen<='0; b_seen<='0; n_seen<='0; s_seen<='0;
            input_count<=0; weight_count<=0; bias_count<=0; multiplier_count<=0; shift_count<=0;
            out_idx<=0; term_idx<=0; acc<=0; active_n<=0; active_shift<=0;
            pair_x<=0; pair_w<=0; y_acc<=0; y_code<=0;
        end else begin
            done<=0; load_error<=0; start_rejected<=0;
            if(start && !start_ready) start_rejected<=1;
            if(load_begin && state==IDLE) begin
                x_seen<='0; w_seen<='0; b_seen<='0; n_seen<='0; s_seen<='0;
                input_count<=0; weight_count<=0; bias_count<=0; multiplier_count<=0; shift_count<=0;
                compute_error<=0;
            end
            if(cfg_valid && cfg_ready) begin
                case(cfg_kind)
                    0: if(cfg_addr<3072 && cfg_data[31:8]==0) begin
                        x_mem[cfg_addr]<=cfg_data[7:0];
                        if(!x_seen[cfg_addr]) input_count<=input_count+1;
                        x_seen[cfg_addr]<=1;
                    end else load_error<=1;
                    1: if(cfg_addr<432 && cfg_data[31:8]==0 && cfg_data[7:0]!=8'h80) begin
                        w_mem[cfg_addr[8:0]]<=cfg_data[7:0];
                        if(!w_seen[cfg_addr[8:0]]) weight_count<=weight_count+1;
                        w_seen[cfg_addr[8:0]]<=1;
                    end else load_error<=1;
                    2: if(cfg_addr<16) begin
                        bias_mem[cfg_addr[3:0]]<=cfg_data;
                        if(!b_seen[cfg_addr[3:0]]) bias_count<=bias_count+1;
                        b_seen[cfg_addr[3:0]]<=1;
                    end else load_error<=1;
                    3: if(cfg_addr<16 && !cfg_data[31]) begin
                        n_mem[cfg_addr[3:0]]<=cfg_data;
                        if(!n_seen[cfg_addr[3:0]]) multiplier_count<=multiplier_count+1;
                        n_seen[cfg_addr[3:0]]<=1;
                    end else load_error<=1;
                    4: if(cfg_addr<16 && cfg_data<=31) begin
                        shift_mem[cfg_addr[3:0]]<=cfg_data[4:0];
                        if(!s_seen[cfg_addr[3:0]]) shift_count<=shift_count+1;
                        s_seen[cfg_addr[3:0]]<=1;
                    end else load_error<=1;
                    default: load_error<=1;
                endcase
            end
            case(state)
                IDLE: if(start && start_ready) begin
                    out_idx<=0; compute_error<=0; state<=INIT;
                end
                INIT: begin
                    acc<=bias_mem[oc]; active_n<=n_mem[oc]; active_shift<=shift_mem[oc];
                    term_idx<=0; state<=READ_PAIR;
                end
                READ_PAIR: begin
                    if(inside_input) pair_x<=x_mem[x_offset];
                    else pair_x<=8'sd0;
                    pair_w<=w_mem[w_offset]; state<=MAC;
                end
                MAC: if(mac_ready) begin
                    if(acc_next>33'sd2147483647 || acc_next< -33'sd2147483648) begin
                        compute_error<=1; state<=IDLE;
                    end else begin
                        acc<=acc_next[31:0];
                        if(term_idx==26) state<=REQUANT;
                        else begin term_idx<=term_idx+1; state<=READ_PAIR; end
                    end
                end
                REQUANT: begin y_acc<=acc; y_code<=requant_code; state<=STORE; end
                STORE: if(y_ready) begin
                    if(out_idx==16383) begin done<=1; state<=IDLE; end
                    else begin out_idx<=out_idx+1; state<=INIT; end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
