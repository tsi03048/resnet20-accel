`timescale 1ns/1ps
// Fixed ResNet20 E2-B: 19 Conv + 9 Add + GAP + FC, three feature banks.
// Sequential native loader; no Golden, readmemh, host intermediate writes.
module full_model_timed(
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
    wire held_rst;
    wire held_load_begin;
    wire held_cfg_valid;
    wire [2:0] held_cfg_kind;
    wire [18:0] held_cfg_addr;
    wire [31:0] held_cfg_data;
    wire held_start;
    wire held_compute_ready;
    wire held_trace_ready;
    wire held_rsp_ready;
    wire [3:0] held_score_read_addr;
    assign held_score_read_addr=score_read_addr;
    input_hold #(.WIDTH(61),.STAGES(8)) input_delays(
        .data({rst,load_begin,cfg_valid,cfg_kind,cfg_addr,cfg_data,start,compute_ready,trace_ready,rsp_ready}),
        .delayed({held_rst,held_load_begin,held_cfg_valid,held_cfg_kind,held_cfg_addr,held_cfg_data,held_start,held_compute_ready,held_trace_ready,held_rsp_ready}));
    full_model core(
        .clk(clk),
        .rst(held_rst),
        .load_begin(held_load_begin),
        .cfg_valid(held_cfg_valid),
        .cfg_ready(cfg_ready),
        .cfg_kind(held_cfg_kind),
        .cfg_addr(held_cfg_addr),
        .cfg_data(held_cfg_data),
        .load_error(load_error),
        .prepared(prepared),
        .input_count(input_count),
        .weight_count(weight_count),
        .bias_count(bias_count),
        .n_count(n_count),
        .shift_count(shift_count),
        .start(held_start),
        .start_ready(start_ready),
        .start_rejected(start_rejected),
        .busy(busy),
        .done(done),
        .fault(fault),
        .fault_code(fault_code),
        .compute_ready(held_compute_ready),
        .step_valid(step_valid),
        .mac_fire(mac_fire),
        .gap_fire(gap_fire),
        .trace_valid(trace_valid),
        .trace_ready(held_trace_ready),
        .trace_op(trace_op),
        .trace_addr(trace_addr),
        .trace_acc(trace_acc),
        .trace_code(trace_code),
        .trace_skip(trace_skip),
        .trace_wide(trace_wide),
        .trace_skip_from_x(trace_skip_from_x),
        .trace_skip_addr(trace_skip_addr),
        .rsp_valid(rsp_valid),
        .result_valid(result_valid),
        .rsp_ready(held_rsp_ready),
        .prediction(prediction),
        .score_read_addr(held_score_read_addr),
        .score_read_data(score_read_data)
    );
endmodule
