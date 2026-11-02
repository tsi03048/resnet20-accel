`timescale 1ns/1ps
module tb_rne;
    logic signed [63:0] wide,rounded;
    logic [4:0] shift;
    logic relu;
    wire signed [7:0] code;
    integer fd,rc,count=0,s,r,c;
    longint signed v,expected;
    rne_clip dut(.*);
    initial begin
        fd=$fopen("results/residual_rtl/rne_vectors.txt","r");
        if(fd==0) $fatal(1,"RNE_VECTOR_MISSING");
        rc=$fscanf(fd,"%d %d %d %d %d\n",v,s,r,expected,c);
        while(rc==5) begin
            wide=v;shift=5'(s);relu=1'(r);#1;
            if(rounded!==expected || int'(code)!=c) $fatal(1,"RNE_MISMATCH index=%0d wide=%0d shift=%0d relu=%0d rounded=%0d expected=%0d code=%0d expected_code=%0d",count,wide,s,r,rounded,expected,code,c);
            count=count+1;
            rc=$fscanf(fd,"%d %d %d %d %d\n",v,s,r,expected,c);
        end
        $fclose(fd);
        if(count!=2000) $fatal(1,"RNE_VECTOR_COUNT %0d",count);
        $display("RNE_PASS vectors=%0d signed_relu_modes=2",count);$finish;
    end
endmodule
