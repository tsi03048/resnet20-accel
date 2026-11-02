`timescale 1ns/1ps
// Exact truth-table model of the UNISIM LUT1 used for identity hold buffers.
module LUT1 #(parameter logic [1:0] INIT=2'b00)(input wire I0,output wire O);
    /* verilator inline_module */
    // Explicit identity specialization lets a zero-delay simulator remove
    // hundreds of physical delay cells while preserving the same truth table.
    // The conditional also maps X/Z input to X, as a LUT truth-table lookup does.
    if(INIT==2'b10) begin:identity
        assign O=I0?1'b1:1'b0;
    end else begin:lookup
        assign O=INIT[I0];
    end
endmodule
