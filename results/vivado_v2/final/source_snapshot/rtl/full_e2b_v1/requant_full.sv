`timescale 1ns/1ps
// One signed RNE, then explicit signed8/ReLU8/common signed32 score clipping.
module requant_full(
    input logic signed [63:0] wide,
    input logic [4:0] shift,
    input logic [1:0] mode,
    output logic signed [63:0] rounded,
    output logic signed [31:0] code
);
    logic signed [63:0] q,remn,half,lower,upper;
    always_comb begin
        q=wide >>> shift;remn=wide-(q <<< shift);half=0;rounded=q;
        if(shift!=0) begin
            half=64'sd1 <<< (shift-1);
            if(remn>half || (remn==half && q[0])) rounded=q+64'sd1;
        end
        lower=mode==2? -64'sd2147483648:(mode==1?64'sd0:-64'sd128);
        upper=mode==2?64'sd2147483647:64'sd127;
        if(rounded<lower) code=lower[31:0];
        else if(rounded>upper) code=upper[31:0];
        else code=rounded[31:0];
    end
endmodule
