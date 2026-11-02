`timescale 1ns/1ps
// 268336 bytes occupy 262144+8192 physical words instead of 524288.
module weight_bram(
    input logic clk,ce,we,re,
    input logic [18:0] waddr,raddr,
    input logic [7:0] data,
    output logic signed [7:0] q
);
    logic [7:0] low_q,high_q;
    logic read_bank,bank_first,read_pending;
    sync_bram #(.WIDTH(8),.AW(18),.DEPTH(262144)) low_mem(
        .clk(clk),.ce(ce),.we(we && !waddr[18]),.re(re && !raddr[18]),
        .waddr(waddr[17:0]),.raddr(raddr[17:0]),.data(data),.q(low_q));
    sync_bram #(.WIDTH(8),.AW(13),.DEPTH(8192)) high_mem(
        .clk(clk),.ce(ce),.we(we && waddr[18]),.re(re && raddr[18]),
        .waddr(waddr[12:0]),.raddr(raddr[12:0]),.data(data),.q(high_q));
    always_ff @(posedge clk) begin
        if(ce) begin
            if(re) bank_first<=raddr[18];
            read_pending<=re;
            if(read_pending) read_bank<=bank_first;
        end
    end
    assign q=read_bank?high_q:low_q;
endmodule
