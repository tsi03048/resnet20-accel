`timescale 1ns/1ps
// Shared ONE-rounding signed-wide postprocessor; Conv2 preserves negatives.
module rne_clip(
    input logic signed [63:0] wide,
    input logic [4:0] shift,
    input logic relu,
    output logic signed [63:0] rounded,
    output logic signed [7:0] code
);
    logic signed [63:0] quotient, remainder, half;
    always_comb begin
        quotient = wide >>> shift;
        remainder = wide - (quotient <<< shift);
        half = 0;
        rounded = quotient;
        if(shift != 0) begin
            half = 64'sd1 <<< (shift-1);
            if(remainder > half || (remainder == half && quotient[0])) rounded = quotient + 64'sd1;
        end
        if(relu && rounded < 0) code = 0;
        else if(rounded < -128) code = -8'sd128;
        else if(rounded > 127) code = 8'sd127;
        else code = rounded[7:0];
    end
endmodule
