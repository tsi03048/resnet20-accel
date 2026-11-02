`timescale 1ns/1ps
`default_nettype none
module mac_scalar(
    input wire clk, rst,
    input wire term_valid, output wire term_ready,
    input wire signed [7:0] x, w,
    input wire first, last, input wire signed [31:0] bias,
    output reg acc_valid, input wire acc_ready,
    output reg signed [31:0] acc_data
);
    reg signed [31:0] psum;
    wire signed [15:0] product=x*w;
    wire signed [31:0] extended_product={{16{product[15]}},product};
    wire signed [31:0] acc_next=(first?bias:psum)+extended_product;
    assign term_ready=!acc_valid&&!rst;
    always @(posedge clk) begin
        if(rst) begin psum<=0;acc_valid<=0;acc_data<=0;end
        else begin
            if(acc_valid&&acc_ready) acc_valid<=0;
            if(term_valid&&term_ready) begin
                psum<=acc_next;
                if(last) begin acc_data<=acc_next;acc_valid<=1;end
            end
        end
    end
endmodule
`default_nettype wire
