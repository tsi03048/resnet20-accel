`timescale 1ns/1ps
module argmax10(
    input logic clk,clear,fire,
    input logic [3:0] index,
    input logic signed [31:0] score,
    output logic [3:0] prediction,
    output logic signed [31:0] best_score
);
    logic have;
    always_ff @(posedge clk) begin
        if(clear) begin have<=0;prediction<=0;best_score<=32'sh80000000;end
        else if(fire && (!have || score>best_score)) begin
            have<=1;prediction<=index;best_score<=score;
        end
    end
endmodule
