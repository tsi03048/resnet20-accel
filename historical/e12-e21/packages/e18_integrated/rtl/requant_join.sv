`timescale 1ns/1ps
`default_nettype none
// Coefficients belong to this input token. Add uses one common denominator.
module requant_join(
    input wire clk,rst,in_valid,output wire in_ready,
    input wire signed [31:0] main_value,skip_value,
    input wire [15:0] main_multiplier,skip_multiplier,
    input wire [4:0] right_shift,input wire add_mode,relu_mode,
    input wire signed [7:0] output_zero,
    input wire [15:0] channel,input wire last,
    output reg out_valid,input wire out_ready,
    output reg signed [7:0] out_code,output reg [15:0] out_channel,
    output reg out_last
);
    wire signed [16:0] nm=$signed({1'b0,main_multiplier});
    wire signed [16:0] ns=$signed({1'b0,skip_multiplier});
    wire signed [48:0] pm=main_value*nm,ps=skip_value*ns;
    wire signed [63:0] wm={{15{pm[48]}},pm};
    wire signed [63:0] ws={{15{ps[48]}},ps};
    wire signed [63:0] combined=wm+(add_mode?ws:64'sd0);
    function automatic signed [7:0] quantize(
        input signed [63:0] v,input [4:0] sh,input signed [7:0] z,input relu_en);
        reg signed [63:0] q,z_extended;
        reg [63:0] remainder_bits,half_value,mask;
        begin
            q=v>>>sh;
            if(sh!=0)begin
                mask=(64'd1<<sh)-1;
                remainder_bits=$unsigned(v)&mask;
                half_value=64'd1<<(sh-1);
                if((remainder_bits>half_value)||((remainder_bits==half_value)&&q[0]))q=q+1;
            end
            z_extended={{56{z[7]}},z};
            q=q+z_extended;
            if(relu_en&&(q<z_extended))q=z_extended;
            if(q>127)quantize=8'sd127;
            else if(q<(-128))quantize=8'sh80;
            else quantize=q[7:0];
        end
    endfunction
    assign in_ready=!out_valid&&!rst;
    always @(posedge clk)begin
        if(rst)begin out_valid<=0;out_code<=0;out_channel<=0;out_last<=0;end
        else begin
            if(out_valid&&out_ready)out_valid<=0;
            if(in_valid&&in_ready)begin
                out_valid<=1;out_code<=quantize(combined,right_shift,output_zero,relu_mode);
                out_channel<=channel;out_last<=last;
            end
        end
    end
endmodule
`default_nettype wire
