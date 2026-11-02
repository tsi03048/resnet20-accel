`timescale 1ns/1ps
module tb_residual;
    logic clk=0,rst=1,load_begin=0,cfg_valid=0,start=0;
    logic [3:0] cfg_kind=0;
    logic [14:0] cfg_addr=0;
    logic [31:0] cfg_data=0;
    wire cfg_ready,load_error,prepared,start_ready,start_rejected,busy,compute_error,rsp_valid,done;
    wire [14:0] input_count;
    wire [11:0] weight1_count,weight2_count;
    wire [4:0] bias1_count,bias2_count,n1_count,n2_count,s1_count,s2_count;
    wire [1:0] add_count;
    logic rsp_ready=1,mac_ready=1,conv_ready=1,y_ready=1;
    wire mac_valid,mac_fire,conv_valid,conv_phase,y_valid;
    wire [13:0] conv_addr,y_addr;
    wire signed [31:0] conv_acc;
    wire signed [7:0] conv_code,y_code,add_main,add_skip;
    wire signed [63:0] add_wide;
    logic [7:0] x[0:16383],w1[0:2303],w2[0:2303],h[0:16383],m[0:16383],y[0:16383];
    logic [31:0] b1[0:15],b2[0:15],n1[0:15],n2[0:15],s1[0:15],s2[0:15],add_cfg[0:2];
    logic [31:0] a1[0:16383],a2[0:16383];
    logic [63:0] aw[0:16383];
    integer mode=0,jobs=0,cycles=0,outputs=0,h_count=0,m_count=0,mac1=0,mac2=0,responses=0;
    integer mac_stalls=0,conv_stalls=0,y_stalls=0,rsp_stalls=0,negative_main=0,lifetime_checks=0;
    integer dump_fd=0,trace_enable=0,cancelled=0;
    bit held_mac=0,held_conv=0,held_y=0,held_rsp=0,force_y_hold=0,force_rsp_hold=0,last_done=0;
    logic [13:0] prev_out,prev_conv_addr,prev_y_addr;
    logic [7:0] prev_term;
    logic prev_phase,prev_conv_phase;
    logic signed [31:0] prev_acc,prev_conv_acc;
    logic signed [7:0] prev_x,prev_w,prev_conv_code,prev_y_code,prev_main,prev_skip;
    logic signed [63:0] prev_wide;
    string vectors,dump_path;
    residual_block dut(.*);
    always #5 clk=~clk;
    always @(negedge clk) begin
        cycles=cycles+1;
        mac_ready=1;conv_ready=1;y_ready=!force_y_hold;rsp_ready=!force_rsp_hold;
        if(mode==1 && busy && !rst) begin
            mac_ready=cycles%5!=0;
            conv_ready=!(conv_valid && !held_conv);
            y_ready=!(y_valid && !held_y);
        end
    end
    always @(posedge clk) begin
        if(rst) begin
            held_mac=0;held_conv=0;held_y=0;held_rsp=0;last_done=0;
            outputs=0;h_count=0;m_count=0;mac1=0;mac2=0;responses=0;negative_main=0;
        end else begin
            if(held_mac && (!mac_valid || dut.out_idx!==prev_out || dut.term_idx!==prev_term || dut.phase!==prev_phase
                || dut.acc!==prev_acc || dut.pair_x!==prev_x || dut.pair_w!==prev_w)) $fatal(1,"MAC_HOLD_VIOLATION");
            if(held_conv && (!conv_valid || conv_addr!==prev_conv_addr || conv_phase!==prev_conv_phase
                || conv_acc!==prev_conv_acc || conv_code!==prev_conv_code)) $fatal(1,"CONV_HOLD_VIOLATION");
            if(held_y && (!y_valid || y_addr!==prev_y_addr || y_code!==prev_y_code || add_wide!==prev_wide
                || add_main!==prev_main || add_skip!==prev_skip)) $fatal(1,"Y_HOLD_VIOLATION");
            if(held_rsp && !rsp_valid) $fatal(1,"RESPONSE_HOLD_VIOLATION");
            held_mac=mac_valid && !mac_ready;held_conv=conv_valid && !conv_ready;
            held_y=y_valid && !y_ready;held_rsp=rsp_valid && !rsp_ready;
            prev_out=dut.out_idx;prev_term=dut.term_idx;prev_phase=dut.phase;prev_acc=dut.acc;prev_x=dut.pair_x;prev_w=dut.pair_w;
            prev_conv_addr=conv_addr;prev_conv_phase=conv_phase;prev_conv_acc=conv_acc;prev_conv_code=conv_code;
            prev_y_addr=y_addr;prev_y_code=y_code;prev_main=add_main;prev_skip=add_skip;prev_wide=add_wide;
            if(held_mac) mac_stalls=mac_stalls+1;
            if(held_conv) conv_stalls=conv_stalls+1;
            if(held_y) y_stalls=y_stalls+1;
            if(held_rsp) rsp_stalls=rsp_stalls+1;
            if(busy && (cfg_ready || start_ready)) $fatal(1,"BUSY_READY_LEAK");
            if(mac_fire) begin
                if(!dut.phase) mac1=mac1+1;else mac2=mac2+1;
            end
            if(conv_valid && conv_ready) begin
                if(!conv_phase) begin
                    if(int'(conv_addr)!=h_count || m_count!=0 || outputs!=0) $fatal(1,"H_ORDER");
                    if(conv_acc!==a1[conv_addr]) $fatal(1,"ACC1_MISMATCH addr=%0d actual=%0d expected=%0d",conv_addr,conv_acc,$signed(a1[conv_addr]));
                    if(conv_code!==h[conv_addr]) $fatal(1,"H_MISMATCH addr=%0d actual=%0d expected=%0d",conv_addr,conv_code,$signed(h[conv_addr]));
                    h_count=h_count+1;
                end else begin
                    if(h_count!=16384 || int'(conv_addr)!=m_count || outputs!=0) $fatal(1,"M_ORDER_OR_H_NOT_DRAINED");
                    if(conv_acc!==a2[conv_addr]) $fatal(1,"ACC2_MISMATCH addr=%0d actual=%0d expected=%0d",conv_addr,conv_acc,$signed(a2[conv_addr]));
                    if(conv_code!==m[conv_addr]) $fatal(1,"M_MISMATCH addr=%0d actual=%0d expected=%0d",conv_addr,conv_code,$signed(m[conv_addr]));
                    if(conv_code<0) negative_main=negative_main+1;
                    m_count=m_count+1;
                end
                if(conv_addr==0) $display("FIRST_CONV phase=%0d acc=%0d code=%0d",conv_phase,conv_acc,conv_code);
                if(dump_fd!=0) $fdisplay(dump_fd,"%0d,%0d,%0d,%0d,0,%0d,0,0",jobs,int'(conv_phase),conv_addr,conv_acc,conv_code);
            end
            if(y_valid && y_ready) begin
                if(h_count!=16384 || m_count!=16384 || int'(y_addr)!=outputs) $fatal(1,"Y_ORDER_OR_CONV_NOT_DRAINED");
                if(add_main!==m[y_addr] || add_skip!==x[y_addr]) $fatal(1,"ADD_PAIR_MISMATCH addr=%0d",y_addr);
                if(add_wide!==aw[y_addr]) $fatal(1,"ADD_WIDE_MISMATCH addr=%0d actual=%0d expected=%0d",y_addr,add_wide,$signed(aw[y_addr]));
                if(y_code!==y[y_addr]) $fatal(1,"Y_MISMATCH addr=%0d actual=%0d expected=%0d",y_addr,y_code,$signed(y[y_addr]));
                if(outputs==0) $display("FIRST_ADD main=%0d skip=%0d wide=%0d code=%0d",add_main,add_skip,add_wide,y_code);
                if(dump_fd!=0) $fdisplay(dump_fd,"%0d,2,%0d,0,%0d,%0d,%0d,%0d",jobs,y_addr,add_wide,y_code,add_main,add_skip);
                outputs=outputs+1;
            end
            if(rsp_valid) begin
                if(h_count!=16384 || m_count!=16384 || outputs!=16384 || mac1!=2359296 || mac2!=2359296 || done)
                    $fatal(1,"EARLY_RESPONSE");
                if(rsp_ready) responses=responses+1;
            end
            if(done && (responses!=1 || outputs!=16384 || last_done)) $fatal(1,"DONE_CONTRACT");
            last_done=done;
        end
    end
    task automatic begin_load;
        @(negedge clk);load_begin=1;
        @(negedge clk);load_begin=0;
        if(prepared || input_count!=0 || add_count!=0 || weight1_count!=0 || weight2_count!=0) $fatal(1,"LOAD_BEGIN_NOT_INVALIDATED");
    endtask
    task automatic write_word(input integer kind,input integer addr,input logic [31:0] data,input bit expect_error);
        @(negedge clk);cfg_valid=1;cfg_kind=4'(kind);cfg_addr=15'(addr);cfg_data=data;
        @(posedge clk);if(!cfg_ready) $fatal(1,"LOADER_NOT_READY");
        @(negedge clk);cfg_valid=0;
        if(load_error!==expect_error) $fatal(1,"LOADER_ERROR_EXPECTATION kind=%0d addr=%0d",kind,addr);
    endtask
    task automatic load_all;
        begin_load();
        for(integer j=0;j<16384;j=j+1) write_word(0,j,{24'd0,x[j]},0);
        write_word(0,0,{24'd0,x[0]},0);
        if(input_count!=16384 || prepared) $fatal(1,"DUPLICATE_OR_PARTIAL_PREPARED");
        for(integer j=0;j<2304;j=j+1) begin write_word(1,j,{24'd0,w1[j]},0);write_word(2,j,{24'd0,w2[j]},0);end
        for(integer j=0;j<16;j=j+1) begin
            write_word(3,j,b1[j],0);write_word(4,j,b2[j],0);write_word(5,j,n1[j],0);write_word(6,j,n2[j],0);
            write_word(7,j,s1[j],0);write_word(8,j,s2[j],0);
        end
        for(integer j=0;j<3;j=j+1) write_word(9,j,add_cfg[j],0);
        if(!prepared || weight1_count!=2304 || weight2_count!=2304 || bias1_count!=16 || bias2_count!=16
            || n1_count!=16 || n2_count!=16 || s1_count!=16 || s2_count!=16 || add_count!=3) $fatal(1,"LOADER_COUNTS");
        $display("LOAD_PASS input=16384 weights=4608 biases=32 multipliers=32 shifts=32 add=3");
    endtask
    task automatic reject_start;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        if(!start_rejected || busy || done || y_valid || rsp_valid) $fatal(1,"UNPREPARED_START_ACCEPTED");
    endtask
    task automatic launch;
        @(negedge clk);outputs=0;h_count=0;m_count=0;mac1=0;mac2=0;responses=0;negative_main=0;
        if(!start_ready) $fatal(1,"START_NOT_READY");
        start=1;
        @(negedge clk);start=0;
    endtask
    task automatic finish_job;
        integer timeout_count;
        timeout_count=0;
        while(!done && timeout_count<30000000) begin
            @(negedge clk);timeout_count=timeout_count+1;
            if(compute_error) $fatal(1,"UNEXPECTED_OVERFLOW");
        end
        if(!done || responses!=1 || outputs!=16384 || h_count!=16384 || m_count!=16384 || mac1!=2359296 || mac2!=2359296)
            $fatal(1,"TIMEOUT_OR_COUNTS");
        for(integer j=0;j<16384;j=j+1) begin
            if(dut.x_mem[j]!==x[j] || dut.work_mem[j]!==y[j] || dut.main_mem[j]!==m[j]) $fatal(1,"BUFFER_LIFETIME addr=%0d",j);
            lifetime_checks=lifetime_checks+3;
        end
        $display("JOB_PASS mode=%0d job=%0d h=16384 m=16384 y=16384 mac1=2359296 mac2=2359296 mismatches=0 negative_main=%0d",mode,jobs,negative_main);
        jobs=jobs+1;
        repeat(2) @(negedge clk);
    endtask
    task automatic cancel_and_check(input integer point);
        @(negedge clk);$display("CANCELLED point=%0d h=%0d m=%0d y=%0d",point,h_count,m_count,outputs);rst=1;
        cancelled=cancelled+1;
        repeat(2) @(negedge clk);rst=0;force_y_hold=0;force_rsp_hold=0;
        repeat(4) begin @(negedge clk);if(busy || prepared || conv_valid || y_valid || rsp_valid || done) $fatal(1,"RESET_LEAK");end
        reject_start();
    endtask
    initial begin
        if(!$value$plusargs("MODE=%d",mode)) mode=0;
        if(!$value$plusargs("VECTORS=%s",vectors)) vectors="reference/e2b_v1/residual_l10_vectors";
        if(!$value$plusargs("DUMP=%s",dump_path)) dump_path="";
        if(!$value$plusargs("TRACE=%d",trace_enable)) trace_enable=0;
        if(dump_path!="") begin
            dump_fd=$fopen(dump_path,"w");if(dump_fd==0) $fatal(1,"DUMP_OPEN_FAILED");
            $fdisplay(dump_fd,"job,stage,address,acc,wide,code,main,skip");
        end
        if(trace_enable!=0) begin $dumpfile("results/residual_rtl/first500.vcd");$dumpvars(1,tb_residual);$dumpvars(1,dut);$dumpoff;end
        $readmemh({vectors,"/input.hex"},x);$readmemh({vectors,"/weight1.hex"},w1);$readmemh({vectors,"/weight2.hex"},w2);
        $readmemh({vectors,"/bias1.hex"},b1);$readmemh({vectors,"/bias2.hex"},b2);
        $readmemh({vectors,"/multiplier1.hex"},n1);$readmemh({vectors,"/multiplier2.hex"},n2);
        $readmemh({vectors,"/shift1.hex"},s1);$readmemh({vectors,"/shift2.hex"},s2);$readmemh({vectors,"/add_config.hex"},add_cfg);
        $readmemh({vectors,"/acc1_expected.hex"},a1);$readmemh({vectors,"/acc2_expected.hex"},a2);
        $readmemh({vectors,"/h_expected.hex"},h);$readmemh({vectors,"/m_expected.hex"},m);
        $readmemh({vectors,"/add_wide_expected.hex"},aw);$readmemh({vectors,"/output_expected.hex"},y);
        if(mode==6) a1[0]=a1[0]^32'd1;
        if(mode==7) m[0]=m[0]^8'd1;
        if(mode==8) y[0]=y[0]^8'd1;
        if(mode==9) aw[0]=aw[0]^64'd1;
        repeat(3) @(negedge clk);rst=0;reject_start();
        if(mode==5) begin
            begin_load();
            write_word(15,0,0,1);write_word(0,16384,0,1);write_word(1,2304,0,1);write_word(2,2304,0,1);
            write_word(3,16,0,1);write_word(5,0,32'hffffffff,1);write_word(6,0,32'h80000000,1);
            write_word(7,0,32'd32,1);write_word(8,0,32'd32,1);write_word(9,3,0,1);
            write_word(9,0,32'hffffffff,1);write_word(9,2,32'd32,1);write_word(0,0,32'h100,1);write_word(2,0,32'h80,1);
            if(input_count!=0 || weight1_count!=0 || weight2_count!=0 || add_count!=0 || prepared) $fatal(1,"BAD_WRITE_CHANGED_COUNT");
            write_word(0,0,{24'd0,x[0]},0);write_word(0,0,{24'd0,x[0]},0);
            if(input_count!=1) $fatal(1,"DUPLICATE_COUNT");reject_start();
            $display("LOADER_NEGATIVE_PASS rejected=14 duplicate_count=1 partial_start_rejected=1");
        end
        load_all();
        if(mode==10) begin
            for(integer j=0;j<16384;j=j+1) write_word(0,j,32'd127,0);
            for(integer j=0;j<144;j=j+1) write_word(1,j,32'd127,0);
            write_word(3,0,32'h7fffffff,0);launch();repeat(100) @(negedge clk);
            if(!compute_error || busy || done || rsp_valid || conv_valid || y_valid || h_count!=0 || outputs!=0) $fatal(1,"OVERFLOW_NOT_REJECTED");
            $display("OVERFLOW_PASS rejected=1 outputs=0 response=0");$finish;
        end
        launch();
        if(mode==1) begin
            force_rsp_hold=1;
            @(negedge clk);cfg_valid=1;cfg_kind=9;cfg_addr=0;cfg_data=0;start=1;
            repeat(2) begin @(negedge clk);if(cfg_ready || !start_rejected) $fatal(1,"BUSY_COMMAND_ACCEPTED");end
            cfg_valid=0;start=0;$display("BUSY_COMMAND_PASS cfg_blocked=1 start_rejected=1");
            wait(rsp_valid);repeat(5) @(negedge clk);
            if(done || start_ready || cfg_ready) $fatal(1,"RESPONSE_NOT_HELD");force_rsp_hold=0;
        end
        if(mode==2) begin
            wait(h_count>=37);cancel_and_check(0);
            load_all();launch();wait(m_count>=19);cancel_and_check(1);
            load_all();force_y_hold=1;launch();wait(y_valid);repeat(3) @(negedge clk);cancel_and_check(2);
            load_all();launch();
        end
        if(trace_enable!=0) begin
            fork
                begin $dumpon;repeat(500) @(negedge clk);$dumpoff;end
                finish_job();
            join
        end else finish_job();
        if(mode==0) begin launch();finish_job();end
        if(mode==1 && (mac_stalls==0 || conv_stalls==0 || y_stalls==0 || rsp_stalls==0)) $fatal(1,"STALL_NOT_EXERCISED");
        if(dump_fd!=0) $fclose(dump_fd);
        $display("CASE_PASS mode=%0d jobs=%0d cancelled=%0d mac_stalls=%0d conv_stalls=%0d y_stalls=%0d rsp_stalls=%0d lifetime_checks=%0d",mode,jobs,cancelled,mac_stalls,conv_stalls,y_stalls,rsp_stalls,lifetime_checks);
        $finish;
    end
endmodule
