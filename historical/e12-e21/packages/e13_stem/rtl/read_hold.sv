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
