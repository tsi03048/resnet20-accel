`timescale 1ns/1ps
module tb_argmax;
    logic clk=0;always #5 clk=~clk;
    logic clear=1,fire=0;
    logic [3:0] index=0,prediction;
    logic signed [31:0] score=0,best_score;
    argmax10 dut(.*);
    task automatic send(input integer i,input integer value);
        @(negedge clk);index=4'(i);score=value;fire=1;
        @(negedge clk);fire=0;
    endtask
    initial begin
        repeat(2) @(negedge clk);clear=0;
        for(integer i=0;i<10;i=i+1) send(i,-2147483648);
        if(prediction!=0 || best_score!=-2147483648) $fatal(1,"ARGMAX_MIN_TIE");
        @(negedge clk);clear=1;@(negedge clk);clear=0;
        for(integer i=0;i<10;i=i+1) send(i,i==3 || i==8?2147483647:-i-100);
        if(prediction!=3 || best_score!=2147483647) $fatal(1,"ARGMAX_SIGNED_TIE");
        repeat(3) @(negedge clk);
        if(prediction!=3) $fatal(1,"ARGMAX_HOLD");
        @(negedge clk);clear=1;@(negedge clk);
        if(prediction!=0) $fatal(1,"ARGMAX_CLEAR");
        $display("ARGMAX_PASS sequences=2 scores=20 signed_extremes=1 lowest_tie=1 hold=1 reset=1");$finish;
    end
endmodule
