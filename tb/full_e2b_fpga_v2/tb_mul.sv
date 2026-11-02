`timescale 1ns/1ps
module tb_mul;
    logic clk=0;always #5 clk=~clk;
    logic clear=1,start=0,take=0,add_second=0,ready,busy,valid;
    logic signed [31:0] lhs1=0,lhs2=0;
    logic [30:0] n1=0,n2=0;
    logic signed [63:0] result;
    logic [31:0] a[0:511],n[0:511],b[0:511],m[0:511],adds[0:511];
    logic [63:0] expected[0:511];
    mul_serial dut(.*);
    integer clocks=0;
    always @(posedge clk) begin clocks=clocks+1;if(clocks>100000) $fatal(1,"MUL_TIMEOUT");end
    initial begin
        $readmemh("reference/e2b_v1/v2_mul/a.hex",a);$readmemh("reference/e2b_v1/v2_mul/n.hex",n);
        $readmemh("reference/e2b_v1/v2_mul/b.hex",b);$readmemh("reference/e2b_v1/v2_mul/m.hex",m);
        $readmemh("reference/e2b_v1/v2_mul/add.hex",adds);$readmemh("reference/e2b_v1/v2_mul/result.hex",expected);
        repeat(3) @(negedge clk);clear=0;
        for(integer i=0;i<512;i=i+1) begin
            wait(ready);@(negedge clk);lhs1=a[i];lhs2=b[i];n1=n[i][30:0];n2=m[i][30:0];add_second=adds[i][0];start=1;
            @(negedge clk);start=0;wait(valid);@(negedge clk);
            if(result!==expected[i]) $fatal(1,"MUL_MISMATCH vector=%0d got=%0d",i,result);
            repeat(2) begin @(negedge clk);if(!valid || result!==expected[i]) $fatal(1,"MUL_HOLD");end
            take=1;@(negedge clk);take=0;
        end
        $display("MUL_PASS vectors=512 oracle=Python_integer");$finish;
    end
endmodule
