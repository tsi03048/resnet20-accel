`timescale 1ns/1ps
// Identity-only input path delay for this OOC physical boundary.
// Actual setup/hold delay is checked after placement/routing, never assumed.
module input_hold #(parameter integer WIDTH=65,STAGES=16)(
    input wire [WIDTH-1:0] data,
    output wire [WIDTH-1:0] delayed
);
    wire [WIDTH-1:0] chain[0:STAGES];
    assign chain[0]=data;
    assign delayed=chain[STAGES];
    for(genvar s=0;s<STAGES;s=s+1) begin:stage
        for(genvar b=0;b<WIDTH;b=b+1) begin:bit_delay
            (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b10)) delay_cell(.I0(chain[s][b]),.O(chain[s+1][b]));
        end
    end
endmodule
