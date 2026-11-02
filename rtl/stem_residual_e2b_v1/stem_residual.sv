// Same-clock Stem -> L1.0 controller. Numerical child cores are unchanged.
// Only actual Stem output fires can write Block X; host Block-X loads are rejected.
module stem_residual(
    input logic clk,rst,load_begin,cfg_valid,
    output logic cfg_ready,
    input logic [1:0] cfg_target,
    input logic [3:0] cfg_kind,
    input logic [14:0] cfg_addr,
    input logic [31:0] cfg_data,
    output logic load_error,prepared,
    input logic start,
    output logic start_ready,start_rejected,busy,done,fault,
    output logic [2:0] fault_code,stage,
    input logic stem_mac_ready,block_mac_ready,link_ready,conv_ready,y_ready,rsp_ready,
    output logic stem_mac_valid,stem_mac_fire,block_mac_valid,block_mac_fire,
    output logic bridge_valid,bridge_ready,
    output logic [13:0] bridge_addr,
    output logic signed [31:0] bridge_acc,
    output logic signed [7:0] bridge_code,
    output logic [14:0] bridge_count,block_input_count,
    output logic conv_valid,conv_phase,
    output logic [13:0] conv_addr,
    output logic signed [31:0] conv_acc,
    output logic signed [7:0] conv_code,
    output logic y_valid,rsp_valid,
    output logic [13:0] y_addr,
    output logic signed [7:0] y_code,add_main,add_skip,
    output logic signed [63:0] add_wide
);
    typedef enum logic [2:0] {IDLE,START_STEM,RUN_STEM,START_BLOCK,RUN_BLOCK,FAILED} state_t;
    state_t state;
    logic armed,core_rst,clear_load,host_ok,s_route,r_route,host_error;
    logic s_cfg_valid,s_cfg_ready,s_load_error,s_prepared,s_start_ready,s_busy,s_done,s_error;
    logic r_cfg_valid,r_cfg_ready,r_load_error,r_prepared,r_start_ready,r_error;
    logic [3:0] r_cfg_kind;
    logic [14:0] r_cfg_addr;
    logic [31:0] r_cfg_data;
    logic [11:0] w1_count,w2_count;
    logic [4:0] b1_count,b2_count,n1_count,n2_count,s1_count,s2_count;
    logic [1:0] add_count;
    logic r_static_prepared,bridge_order_ok;
    logic s_y_valid,s_y_ready,r_conv_valid,r_y_valid,r_rsp_valid,r_rsp_ready;
    logic unused_s_start_rejected,unused_r_start_rejected,unused_r_busy,unused_r_done;
    logic [11:0] unused_s_input_count;
    logic [8:0] unused_s_weight_count;
    logic [4:0] unused_s_bias_count,unused_s_n_count,unused_s_shift_count;
    always_comb begin
        stage=state;busy=state!=IDLE && state!=FAILED;
        core_rst=rst || state==FAILED;
        clear_load=load_begin && (state==IDLE || state==FAILED);
        host_ok=!rst && state==IDLE && !start && !load_begin;
        s_route=cfg_target==0 && cfg_kind<=4 && cfg_addr[14:12]==0;
        r_route=cfg_target==1 && cfg_kind>=1 && cfg_kind<=9;
        cfg_ready=host_ok && (s_route?s_cfg_ready:(r_route?r_cfg_ready:1'b1));
        s_cfg_valid=cfg_valid && cfg_ready && s_route;
        r_cfg_valid=cfg_valid && cfg_ready && r_route;
        r_cfg_kind=cfg_kind;r_cfg_addr=cfg_addr;r_cfg_data=cfg_data;
        r_static_prepared=w1_count==2304 && w2_count==2304 && b1_count==16 && b2_count==16
             && n1_count==16 && n2_count==16 && s1_count==16 && s2_count==16 && add_count==3;
        prepared=state==IDLE && armed && s_prepared && r_static_prepared && block_input_count==0;
        start_ready=!rst && prepared && !load_begin && !cfg_valid;
        load_error=host_error || s_load_error || r_load_error;
        bridge_order_ok=bridge_count<16384 && {1'b0,bridge_addr}==bridge_count && block_input_count==bridge_count;
        bridge_valid=!rst && state==RUN_STEM && s_y_valid;
        bridge_ready=!rst && state==RUN_STEM && r_cfg_ready && link_ready && bridge_order_ok;
        s_y_ready=bridge_ready;
        if(state==RUN_STEM) begin
            r_cfg_valid=bridge_valid && link_ready && bridge_order_ok;
            r_cfg_kind=0;r_cfg_addr={1'b0,bridge_addr};r_cfg_data={24'd0,bridge_code};
        end
        conv_valid=!rst && state==RUN_BLOCK && r_conv_valid;
        y_valid=!rst && state==RUN_BLOCK && r_y_valid;
        rsp_valid=!rst && state==RUN_BLOCK && r_rsp_valid;
        r_rsp_ready=state==RUN_BLOCK && rsp_ready;
    end
    stem_conv stem(
        .clk(clk),.rst(core_rst),.load_begin(clear_load),.cfg_valid(s_cfg_valid),.cfg_ready(s_cfg_ready),
        .cfg_kind(cfg_kind[2:0]),.cfg_addr(cfg_addr[11:0]),.cfg_data(cfg_data),.load_error(s_load_error),.prepared(s_prepared),
        .input_count(unused_s_input_count),.weight_count(unused_s_weight_count),.bias_count(unused_s_bias_count),
        .multiplier_count(unused_s_n_count),.shift_count(unused_s_shift_count),
        .start(state==START_STEM),.start_ready(s_start_ready),.start_rejected(unused_s_start_rejected),
        .busy(s_busy),.done(s_done),.compute_error(s_error),.mac_ready(stem_mac_ready),.mac_valid(stem_mac_valid),.mac_fire(stem_mac_fire),
        .y_valid(s_y_valid),.y_ready(s_y_ready),.y_addr(bridge_addr),.y_acc(bridge_acc),.y_code(bridge_code)
    );
    residual_block block_core(
        .clk(clk),.rst(core_rst),.load_begin(clear_load),.cfg_valid(r_cfg_valid),.cfg_ready(r_cfg_ready),
        .cfg_kind(r_cfg_kind),.cfg_addr(r_cfg_addr),.cfg_data(r_cfg_data),.load_error(r_load_error),.prepared(r_prepared),
        .input_count(block_input_count),.weight1_count(w1_count),.weight2_count(w2_count),.bias1_count(b1_count),.bias2_count(b2_count),
        .n1_count(n1_count),.n2_count(n2_count),.s1_count(s1_count),.s2_count(s2_count),.add_count(add_count),
        .start(state==START_BLOCK),.start_ready(r_start_ready),.start_rejected(unused_r_start_rejected),
        .busy(unused_r_busy),.done(unused_r_done),.compute_error(r_error),.rsp_valid(r_rsp_valid),.rsp_ready(r_rsp_ready),
        .mac_ready(block_mac_ready),.mac_valid(block_mac_valid),.mac_fire(block_mac_fire),
        .conv_valid(r_conv_valid),.conv_ready(conv_ready),.conv_phase(conv_phase),.conv_addr(conv_addr),.conv_acc(conv_acc),.conv_code(conv_code),
        .y_valid(r_y_valid),.y_ready(y_ready),.y_addr(y_addr),.y_code(y_code),.add_main(add_main),.add_skip(add_skip),.add_wide(add_wide)
    );
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;armed<=0;bridge_count<=0;host_error<=0;start_rejected<=0;done<=0;fault<=0;fault_code<=0;
        end else begin
            host_error<=0;start_rejected<=0;done<=0;
            if(start && !start_ready) start_rejected<=1;
            if(cfg_valid && cfg_ready && !s_route && !r_route) host_error<=1;
            if(clear_load) begin
                state<=IDLE;armed<=1;bridge_count<=0;fault<=0;fault_code<=0;
            end else case(state)
                IDLE: if(start && start_ready) begin armed<=0;bridge_count<=0;state<=START_STEM;end
                START_STEM: if(s_start_ready) state<=RUN_STEM;
                RUN_STEM: begin
                    if(bridge_valid && bridge_ready) bridge_count<=bridge_count+1;
                    if(s_error) begin fault<=1;fault_code<=1;state<=FAILED;end
                    else if(bridge_valid && !bridge_order_ok) begin fault<=1;fault_code<=3;state<=FAILED;end
                    else if(s_done) begin
                        if(bridge_count==16384 && block_input_count==16384 && r_prepared && !s_busy) state<=START_BLOCK;
                        else begin fault<=1;fault_code<=3;state<=FAILED;end
                    end
                end
                START_BLOCK: if(r_start_ready) state<=RUN_BLOCK;
                RUN_BLOCK: begin
                    if(r_error) begin fault<=1;fault_code<=2;state<=FAILED;end
                    else if(r_rsp_valid && rsp_ready) begin done<=1;state<=IDLE;end
                end
                FAILED: begin end
                default:begin fault<=1;fault_code<=3;state<=FAILED;end
            endcase
        end
    end
endmodule
