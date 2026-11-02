`timescale 1ns/1ps
// Exact truth-table model of the UNISIM LUT1 used for identity hold buffers.
module LUT1 #(parameter logic [1:0] INIT=2'b00)(input wire I0,output wire O);
    assign O=INIT[I0];
endmodule
