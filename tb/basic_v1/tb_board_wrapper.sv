`timescale 1ns/1ps
// Simulation-only VIO stand-in. Never add this file to the Vivado project.
module vio_basic(input wire clk,
    input wire [31:0] probe_in0,probe_in1,probe_in2,probe_in3,
    input wire [1:0] probe_in4, input wire [3:0] probe_in5,
    output logic probe_out0=0, probe_out1=0);
endmodule

module tb_board_wrapper;
    logic GCLK=0;
    always #5 GCLK=~GCLK;
    basic_vio_top dut(.*);
    task automatic run_job;
        @(negedge GCLK); dut.observe.probe_out0=1;
        repeat(2) @(negedge GCLK); dut.observe.probe_out0=0;
        repeat(200) @(negedge GCLK);
        if(dut.result0 !== 10 || dut.result1 !== 9 || dut.result2 !== 8 || dut.result3 !== 6
            || dut.stored !== 4'b1111 || dut.completed !== 1'b1 || dut.busy !== 0)
            $fatal(1,"BOARD_WRAPPER_MISMATCH");
    endtask
    initial begin
        repeat(300) @(negedge GCLK);
        run_job();
        dut.observe.probe_out1=1;
        repeat(3) @(negedge GCLK);
        if(dut.stored !== 0 || dut.completed !== 0) $fatal(1,"BOARD_RESET");
        dut.observe.probe_out1=0;
        run_job();
        $display("PASS board wrapper: 10,9,8,6; reset and restart");
        $finish;
    end
endmodule
