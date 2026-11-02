`timescale 1ns/1ps
module tb_stem;
    logic clk=0,rst=1,load_begin=0,cfg_valid=0,start=0,mac_ready=1,y_ready=1;
    logic [2:0] cfg_kind=0;
    logic [11:0] cfg_addr=0;
    logic [31:0] cfg_data=0;
    wire cfg_ready,load_error,prepared,start_ready,start_rejected,busy,done,compute_error,mac_valid,mac_fire,y_valid;
    wire [11:0] input_count;
    wire [8:0] weight_count;
    wire [4:0] bias_count,multiplier_count,shift_count;
    wire [13:0] y_addr;
    wire signed [31:0] y_acc;
    wire signed [7:0] y_code;
    logic [7:0] input_words[0:3071],weight_words[0:431],expected_code[0:16383];
    logic [31:0] bias_words[0:15],n_words[0:15],s_words[0:15],expected_acc[0:16383];
    integer mode=0,outputs=0,macs=0,jobs=0,cycles=0,mac_stalls=0,output_stalls=0;
    integer total_mac_stalls=0,total_output_stalls=0,i,trace_enable=0,dump_fd;
    bit held_y=0,held_mac=0,last_done=0;
    logic [13:0] prev_y_addr,prev_out;
    logic signed [31:0] prev_y_acc,prev_acc;
    logic signed [7:0] prev_y_code,prev_pair_x,prev_pair_w;
    logic [4:0] prev_term;
    string vectors,dump_path;
    stem_conv dut(.*);
    always #5 clk=~clk;
    always @(negedge clk) begin
        cycles=cycles+1;
        if(mode==1 && busy && !rst) begin
            mac_ready=cycles%5!=0;
            y_ready=cycles%7!=0;
        end else begin mac_ready=1; y_ready=1; end
    end
    always @(posedge clk) begin
        if(rst) begin
            outputs=0; macs=0; held_y=0; held_mac=0; last_done=0;
            mac_stalls=0; output_stalls=0;
        end else begin
            if(held_y && (!y_valid || y_addr!==prev_y_addr || y_acc!==prev_y_acc || y_code!==prev_y_code))
                $fatal(1,"OUTPUT_HOLD_VIOLATION");
            if(held_mac && (!mac_valid || dut.out_idx!==prev_out || dut.term_idx!==prev_term || dut.acc!==prev_acc
                || dut.pair_x!==prev_pair_x || dut.pair_w!==prev_pair_w))
                $fatal(1,"MAC_HOLD_VIOLATION");
            held_y=y_valid && !y_ready;
            held_mac=mac_valid && !mac_ready;
            prev_y_addr=y_addr; prev_y_acc=y_acc; prev_y_code=y_code;
            prev_out=dut.out_idx; prev_term=dut.term_idx; prev_acc=dut.acc;
            prev_pair_x=dut.pair_x; prev_pair_w=dut.pair_w;
            if(held_mac) begin mac_stalls=mac_stalls+1; total_mac_stalls=total_mac_stalls+1; end
            if(held_y) begin output_stalls=output_stalls+1; total_output_stalls=total_output_stalls+1; end
            if(mac_fire) macs=macs+1;
            if(y_valid && y_ready) begin
                if(int'(y_addr)!=outputs) $fatal(1,"OUTPUT_ORDER expected=%0d actual=%0d",outputs,y_addr);
                if(y_acc!==expected_acc[y_addr])
                    $fatal(1,"EXPECTED_ACC_MISMATCH addr=%0d actual=%0d expected=%0d",y_addr,y_acc,$signed(expected_acc[y_addr]));
                if(y_code!==expected_code[y_addr])
                    $fatal(1,"EXPECTED_OUTPUT_MISMATCH addr=%0d actual=%0d expected=%0d",y_addr,y_code,$signed(expected_code[y_addr]));
                if(outputs==0) $display("FIRST_VALUE mode=%0d acc=%0d code=%0d",mode,y_acc,y_code);
                if(dump_fd!=0) $fdisplay(dump_fd,"%0d,%0d,%0d,%0d",jobs,y_addr,y_acc,y_code);
                outputs=outputs+1;
            end
            if(done && (outputs!=16384 || macs!=442368)) $fatal(1,"EARLY_DONE outputs=%0d macs=%0d",outputs,macs);
            if(done && last_done) $fatal(1,"DONE_NOT_A_PULSE");
            last_done=done;
        end
    end
    task automatic begin_load;
        @(negedge clk); load_begin=1;
        @(negedge clk); load_begin=0;
        if(prepared || input_count!=0 || weight_count!=0 || bias_count!=0 || multiplier_count!=0 || shift_count!=0)
            $fatal(1,"LOAD_BEGIN_NOT_INVALIDATED");
    endtask
    task automatic write_word(input integer kind,input integer addr,input logic [31:0] data,input bit expect_error);
        @(negedge clk); cfg_valid=1; cfg_kind=3'(kind); cfg_addr=12'(addr); cfg_data=data;
        @(posedge clk); if(!cfg_ready) $fatal(1,"LOADER_NOT_READY");
        @(negedge clk); cfg_valid=0;
        if(load_error!==expect_error) $fatal(1,"LOADER_ERROR_EXPECTATION kind=%0d addr=%0d",kind,addr);
    endtask
    task automatic load_all;
        begin_load();
        for(integer j=0;j<3072;j=j+1) write_word(0,j,{24'd0,input_words[j]},0);
        write_word(0,0,{24'd0,input_words[0]},0);
        if(input_count!=3072 || prepared) $fatal(1,"DUPLICATE_OR_PARTIAL_PREPARED");
        for(integer j=0;j<432;j=j+1) write_word(1,j,{24'd0,weight_words[j]},0);
        for(integer j=0;j<16;j=j+1) write_word(2,j,bias_words[j],0);
        for(integer j=0;j<16;j=j+1) write_word(3,j,n_words[j],0);
        for(integer j=0;j<16;j=j+1) write_word(4,j,s_words[j],0);
        if(!prepared || weight_count!=432 || bias_count!=16 || multiplier_count!=16 || shift_count!=16)
            $fatal(1,"LOADER_COUNTS");
        $display("LOAD_PASS input=%0d weight=%0d bias=%0d multiplier=%0d shift=%0d",input_count,weight_count,bias_count,multiplier_count,shift_count);
    endtask
    task automatic launch;
        @(negedge clk);
        outputs=0; macs=0; mac_stalls=0; output_stalls=0;
        if(!start_ready) $fatal(1,"START_NOT_READY");
        start=1;
        @(negedge clk); start=0;
    endtask
    task automatic reject_start;
        @(negedge clk); start=1;
        @(negedge clk); start=0;
        if(!start_rejected || busy || y_valid || done) $fatal(1,"UNPREPARED_START_ACCEPTED");
    endtask
    task automatic finish_job;
        integer timeout_count;
        timeout_count=0;
        while(!done && timeout_count<2000000) begin
            @(negedge clk); timeout_count=timeout_count+1;
            if(compute_error) $fatal(1,"UNEXPECTED_ARITHMETIC_ERROR");
        end
        if(!done || outputs!=16384 || macs!=442368) $fatal(1,"TIMEOUT_OR_COUNTS");
        $display("JOB_PASS mode=%0d job=%0d outputs=%0d macs=%0d acc_mismatches=0 output_mismatches=0",mode,jobs,outputs,macs);
        jobs=jobs+1;
        repeat(2) @(negedge clk);
    endtask
    initial begin
        if(!$value$plusargs("MODE=%d",mode)) mode=0;
        if(!$value$plusargs("VECTORS=%s",vectors)) vectors="reference/e2b_v1/stem_vectors";
        if(!$value$plusargs("TRACE=%d",trace_enable)) trace_enable=0;
        if(!$value$plusargs("DUMP=%s",dump_path)) dump_path="";
        dump_fd=0;
        if(dump_path!="") begin
            dump_fd=$fopen(dump_path,"w");
            if(dump_fd==0) $fatal(1,"DUMP_OPEN_FAILED");
            $fdisplay(dump_fd,"job,address,acc,code");
        end
        if(trace_enable) begin
            $dumpfile("results/stem_rtl/first_window.vcd");
            $dumpvars(1,tb_stem); $dumpvars(1,dut); $dumpoff;
        end
        $readmemh({vectors,"/input.hex"},input_words);
        $readmemh({vectors,"/weight.hex"},weight_words);
        $readmemh({vectors,"/bias.hex"},bias_words);
        $readmemh({vectors,"/multiplier.hex"},n_words);
        $readmemh({vectors,"/shift.hex"},s_words);
        $readmemh({vectors,"/acc_expected.hex"},expected_acc);
        $readmemh({vectors,"/output_expected.hex"},expected_code);
        if(mode==3) expected_code[0]=expected_code[0]^8'd1;
        if(mode==4) expected_acc[0]=expected_acc[0]^32'd1;
        repeat(3) @(negedge clk); rst=0;
        reject_start();
        if(mode==5) begin
            begin_load();
            write_word(7,0,0,1); write_word(0,3072,0,1); write_word(1,432,0,1);
            write_word(2,16,0,1); write_word(3,0,32'hffffffff,1); write_word(4,0,32'd32,1);
            write_word(1,0,32'h80,1); write_word(0,0,32'h100,1);
            if(input_count!=0 || weight_count!=0 || bias_count!=0 || multiplier_count!=0 || shift_count!=0)
                $fatal(1,"BAD_WRITE_CHANGED_COUNT");
            write_word(0,0,{24'd0,input_words[0]},0);
            write_word(0,0,{24'd0,input_words[0]},0);
            if(input_count!=1) $fatal(1,"DUPLICATE_COUNT");
            reject_start();
            $display("LOADER_NEGATIVE_PASS rejected=8 duplicate_count=1 partial_start_rejected=1");
        end
        load_all();
        if(mode==6) begin
            // Deliberately altered synthetic constants: overflow rejection, not model accuracy.
            for(integer j=0;j<3072;j=j+1) write_word(0,j,32'd127,0);
            for(integer j=0;j<27;j=j+1) write_word(1,j,32'd127,0);
            write_word(2,0,32'h7fffffff,0);
            launch();
            repeat(100) @(negedge clk);
            if(!compute_error || done || busy || y_valid || outputs!=0) $fatal(1,"OVERFLOW_NOT_REJECTED");
            $display("OVERFLOW_PASS rejected=1 outputs=0 done=0");
            $finish;
        end
        launch();
        if(mode==1) begin
            // No loader transfer or second start may change an active job.
            @(negedge clk); cfg_valid=1; cfg_kind=2; cfg_addr=0; cfg_data=32'h7fffffff; start=1;
            repeat(2) begin @(negedge clk); if(cfg_ready || !start_rejected) $fatal(1,"BUSY_COMMAND_ACCEPTED"); end
            cfg_valid=0; start=0;
            $display("BUSY_COMMAND_PASS cfg_blocked=1 start_rejected=1");
        end
        if(mode==2) begin
            wait(outputs>=37);
            @(negedge clk); $display("CANCELLED outputs=%0d macs=%0d",outputs,macs); rst=1;
            repeat(2) @(negedge clk); rst=0;
            repeat(3) begin @(negedge clk); if(y_valid || done || busy || prepared) $fatal(1,"RESET_LEAK"); end
            reject_start(); load_all(); launch();
        end
        if(trace_enable) begin
            fork
                begin $dumpon; repeat(300) @(negedge clk); $dumpoff; end
                finish_job();
            join
        end else finish_job();
        if(mode==0) begin launch(); finish_job(); end
        if(mode==1 && (total_mac_stalls==0 || total_output_stalls==0)) $fatal(1,"STALL_NOT_EXERCISED");
        if(dump_fd!=0) $fclose(dump_fd);
        $display("CASE_PASS mode=%0d jobs=%0d mac_stalls=%0d output_stalls=%0d",mode,jobs,total_mac_stalls,total_output_stalls);
        $finish;
    end
endmodule
