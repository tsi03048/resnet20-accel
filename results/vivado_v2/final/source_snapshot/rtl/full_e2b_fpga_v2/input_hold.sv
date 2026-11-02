`timescale 1ns/1ps
// Identity-only input path delay for this OOC physical boundary.
// Actual setup/hold delay is checked after placement/routing, never assumed.
module input_hold #(parameter integer WIDTH=65,STAGES=16)(
    input wire [WIDTH-1:0] data,
    output wire [WIDTH-1:0] delayed
);
    for(genvar s=0;s<STAGES;s=s+1) begin:stage
        wire [WIDTH-1:0] stage_in,stage_out;
        if(s==0) begin:first_input
            assign stage_in=data;
        end else begin:previous_input
            assign stage_in=stage[s-1].stage_out;
        end
        if(s==STAGES-1) begin:last_output
            assign delayed=stage_out;
        end
        for(genvar b=0;b<WIDTH;b=b+1) begin:bit_delay
            (* DONT_TOUCH="TRUE" *) LUT1 #(.INIT(2'b10)) delay_cell(.I0(stage_in[b]),.O(stage_out[b]));
        end
    end
endmodule
