`timescale 1ns/1ps
module tb_requant;
    logic signed [31:0] acc,multiplier;
    logic [4:0] shift;
    wire signed [63:0] rounded;
    wire signed [7:0] code;
    longint signed expected_rounded;
    integer expected_code,sh,fd,status,count;
    requant_rne_relu dut(.*);
    initial begin
        count=0;
        fd=$fopen("results/stem_rtl/rne_vectors.txt","r");
        if(fd==0) $fatal(1,"RNE_VECTOR_OPEN_FAILED");
        while(!$feof(fd)) begin
            status=$fscanf(fd,"%d %d %d %d %d\n",acc,multiplier,sh,expected_rounded,expected_code);
            if(status!=5) $fatal(1,"RNE_VECTOR_PARSE_FAILED");
            shift=5'(sh); #1;
            if(rounded !== expected_rounded || $signed(code) != expected_code)
                $fatal(1,"RNE_MISMATCH index=%0d acc=%0d N=%0d shift=%0d got=%0d expected=%0d",count,acc,multiplier,sh,rounded,expected_rounded);
            count=count+1;
        end
        $fclose(fd);
        if(count!=1280) $fatal(1,"RNE_VECTOR_COUNT %0d",count);
        $display("RNE_PASS vectors=%0d",count); $finish;
    end
endmodule
