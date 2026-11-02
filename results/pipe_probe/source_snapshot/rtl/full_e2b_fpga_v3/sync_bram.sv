`timescale 1ns/1ps
// Independent synchronous read and write ports. Payload has no reset.
module sync_bram #(
    parameter integer WIDTH=8,AW=10,DEPTH=1024
)(
    input logic clk,ce,we,re,
    input logic [AW-1:0] waddr,raddr,
    input logic [WIDTH-1:0] data,
    output logic [WIDTH-1:0] q
);
    (* ram_style="block" *) logic [WIDTH-1:0] mem[0:DEPTH-1];
    logic [WIDTH-1:0] raw_q;
    logic read_pending;
    always_ff @(posedge clk) begin
        if(we) mem[waddr]<=data;
        if(ce) begin
            if(re) raw_q<=mem[raddr];
            read_pending<=re;
            if(read_pending) q<=raw_q;
        end
    end
endmodule
