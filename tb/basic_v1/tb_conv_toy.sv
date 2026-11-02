`timescale 1ns/1ps
module tb_conv_toy;
    logic clk=0, rst=1, start=0, mac_ready=1, y_ready=1;
    wire busy, done, y_valid, mac_fire;
    wire [1:0] y_addr;
    wire signed [31:0] y_data;
    integer outputs=0, macs=0, cycle=0, mode=0;
    integer expected[0:3];
    logic held=0;
    logic signed [31:0] held_data;
    logic [1:0] held_addr;
    conv_toy dut(.*);
    always #5 clk=~clk;
    always @(posedge clk) begin
        if(rst) begin outputs=0; macs=0; held=0; end
        else begin
            if(held && (!y_valid || y_addr !== held_addr || y_data !== held_data))
                $fatal(1,"HOLD VIOLATION");
            held = y_valid && !y_ready;
            held_data = y_data; held_addr = y_addr;
            if(mac_fire) macs=macs+1;
            if(y_valid && y_ready) begin
                if(int'(y_addr) != outputs || y_data !== expected[outputs])
                    $fatal(1,"EXPECTED_MISMATCH addr=%0d actual=%0d", y_addr,y_data);
                outputs=outputs+1;
            end
        end
    end
    task automatic launch;
        @(negedge clk); start=1;
        @(negedge clk); start=0;
    endtask
    task automatic finish_job;
        integer timeout_count;
        timeout_count=0;
        while(!done && timeout_count<1000) begin
            @(negedge clk);
            cycle=cycle+1; timeout_count=timeout_count+1;
            mac_ready = mode==1 ? cycle%3 != 0 : 1;
            y_ready = mode==1 ? cycle%4 == 0 : 1;
        end
        if(!done || outputs!=4 || macs!=36)
            $fatal(1,"COUNTS/TIMEOUT outputs=%0d macs=%0d",outputs,macs);
    endtask
    initial begin
        if(!$value$plusargs("MODE=%d",mode)) mode=0;
        expected[0]=10; expected[1]=9; expected[2]=8; expected[3]=6;
        if(mode==3) expected[0]=11;
        $dumpfile("toy.vcd"); $dumpvars(0,tb_conv_toy);
        repeat(3) @(negedge clk); rst=0;
        launch();
        if(mode==2) begin
            repeat(9) @(negedge clk);
            rst=1;
            repeat(2) @(negedge clk); rst=0;
            repeat(3) begin
                @(negedge clk);
                if(y_valid || done || busy) $fatal(1,"RESET LEAK");
            end
            launch();
        end
        finish_job();
        $display("PASS mode=%0d outputs=%0d macs=%0d",mode,outputs,macs);
        $finish;
    end
endmodule
