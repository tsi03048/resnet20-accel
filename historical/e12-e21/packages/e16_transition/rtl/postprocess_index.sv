`timescale 1ns/1ps
`default_nettype none
module postprocess_index #(parameter integer NOUT=16384)(
    input wire clk,rst,acc_valid,output wire acc_ready,
    input wire signed [31:0] acc_data,input wire relu_mode,
    input wire [15:0] index_in,
    output reg y_valid,input wire y_ready,
    output reg signed [7:0] y_data,output reg [15:0] y_index,output reg y_last
);
    function automatic signed [7:0] quantize4(input signed [31:0] a,input relu_en);
        reg signed [31:0] q;
        begin
            q=a>>>2;
            if((a[1:0]>2)||((a[1:0]==2)&&q[0]))q=q+1;
            if(relu_en&&(q<0))q=0;
            if(q>127)quantize4=8'sd127;
            else if(q<(-128))quantize4=8'sh80;
            else quantize4=q[7:0];
        end
    endfunction
    assign acc_ready=!y_valid&&!rst;
    always @(posedge clk)begin
        if(rst)begin y_valid<=0;y_data<=0;y_index<=0;y_last<=0;end
        else begin
            if(y_valid&&y_ready)y_valid<=0;
            if(acc_valid&&acc_ready)begin
                y_valid<=1;y_data<=quantize4(acc_data,relu_mode);
                y_index<=index_in;y_last<=(index_in==16'(NOUT-1));
            end
        end
    end
endmodule
`default_nettype wire
