`timescale 1ns/1ps
module tb_post;
    logic signed [63:0] wide,rounded;
    logic [4:0] shift;
    logic [1:0] mode;
    logic signed [31:0] code;
    logic [63:0] ws[0:1999],expected_round[0:1999];
    logic [31:0] ss[0:1999],ms[0:1999],expected_code[0:1999];
    requant_full dut(.*);
    initial begin
        $readmemh("reference/e2b_v1/full_vectors/post/wide.hex",ws);
        $readmemh("reference/e2b_v1/full_vectors/post/shift.hex",ss);
        $readmemh("reference/e2b_v1/full_vectors/post/mode.hex",ms);
        $readmemh("reference/e2b_v1/full_vectors/post/rounded.hex",expected_round);
        $readmemh("reference/e2b_v1/full_vectors/post/code.hex",expected_code);
        for(integer i=0;i<2000;i=i+1) begin
            wide=ws[i];shift=ss[i][4:0];mode=ms[i][1:0];#1;
            if(rounded!==expected_round[i] || code!==expected_code[i]) $fatal(1,"POST_MISMATCH vector=%0d",i);
        end
        $display("POST_PASS vectors=2000 oracle=Fraction");$finish;
    end
endmodule
