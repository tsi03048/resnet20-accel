`timescale 1ns/1ps
module tb_post;
    logic clk=0;always #5 clk=~clk;
    logic clear=1,start=0,take=0,ready,busy,valid;
    logic signed [63:0] wide=0,rounded;
    logic [4:0] shift=0;
    logic [1:0] mode=0;
    logic signed [31:0] code;
    logic [63:0] ws[0:1999],expected_round[0:1999];
    logic [31:0] ss[0:1999],ms[0:1999],expected_code[0:1999];
    rne_serial dut(.*);
    integer clocks=0;
    always @(posedge clk) begin clocks=clocks+1;if(clocks>200000) $fatal(1,"POST_TIMEOUT");end
    initial begin
        $readmemh("reference/e2b_v1/full_vectors/post/wide.hex",ws);
        $readmemh("reference/e2b_v1/full_vectors/post/shift.hex",ss);
        $readmemh("reference/e2b_v1/full_vectors/post/mode.hex",ms);
        $readmemh("reference/e2b_v1/full_vectors/post/rounded.hex",expected_round);
        $readmemh("reference/e2b_v1/full_vectors/post/code.hex",expected_code);
        repeat(3) @(negedge clk);clear=0;
        for(integer i=0;i<2000;i=i+1) begin
            wait(ready);@(negedge clk);wide=ws[i];shift=ss[i][4:0];mode=ms[i][1:0];start=1;
            @(negedge clk);start=0;wait(valid);@(negedge clk);
            if(rounded!==expected_round[i] || code!==expected_code[i]) $fatal(1,"POST_MISMATCH vector=%0d",i);
            repeat(2) begin @(negedge clk);if(!valid || rounded!==expected_round[i] || code!==expected_code[i]) $fatal(1,"POST_HOLD");end
            take=1;@(negedge clk);take=0;
        end
        $display("POST_PASS vectors=2000 oracle=Fraction");$finish;
    end
endmodule
