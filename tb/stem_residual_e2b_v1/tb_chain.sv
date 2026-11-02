`timescale 1ns/1ps
module tb_chain;
    logic clk=0,rst=1,load_begin=0,cfg_valid=0,start=0;
    logic [1:0] cfg_target=0;
    logic [3:0] cfg_kind=0;
    logic [14:0] cfg_addr=0;
    logic [31:0] cfg_data=0;
    wire cfg_ready,load_error,prepared,start_ready,start_rejected,busy,done,fault;
    wire [2:0] fault_code,stage;
    logic stem_mac_ready=1,block_mac_ready=1,link_ready=1,conv_ready=1,y_ready=1,rsp_ready=1;
    wire stem_mac_valid,stem_mac_fire,block_mac_valid,block_mac_fire,bridge_valid,bridge_ready,conv_valid,conv_phase,y_valid,rsp_valid;
    wire [13:0] bridge_addr,conv_addr,y_addr;
    wire [14:0] bridge_count,block_input_count;
    wire signed [31:0] bridge_acc,conv_acc;
    wire signed [7:0] bridge_code,conv_code,y_code,add_main,add_skip;
    wire signed [63:0] add_wide;
    logic [7:0] x[0:3071],sw[0:431],w1[0:2303],w2[0:2303];
    logic [31:0] sb[0:15],sn[0:15],ss[0:15],b1[0:15],b2[0:15],n1[0:15],n2[0:15],s1[0:15],s2[0:15],ac[0:2];
    logic [31:0] sa[0:16383],a1[0:16383],a2[0:16383];
    logic [7:0] sx[0:16383],h[0:16383],m[0:16383],y[0:16383],forwarded[0:16383];
    logic [63:0] aw[0:16383];
    integer mode=0,jobs=0,case_id=0,cycles=0,bridges=0,h_count=0,m_count=0,outputs=0,smacs=0,bmacs=0,responses=0;
    integer cancelled=0,bridge_stalls=0,conv_stalls=0,y_stalls=0,rsp_stalls=0,smac_stalls=0,bmac_stalls=0,lifetime_checks=0;
    integer dump_fd=0,trace_enable=0;
    bit held_bridge=0,held_conv=0,held_y=0,held_rsp=0,force_link_hold=0,force_y_hold=0,force_rsp_hold=0,last_done=0;
    logic [13:0] prev_bridge_addr,prev_conv_addr,prev_y_addr;
    logic [14:0] prev_bridge_count,prev_input_count;
    logic prev_conv_phase;
    logic signed [31:0] prev_bridge_acc,prev_conv_acc;
    logic signed [7:0] prev_bridge_code,prev_conv_code,prev_y_code,prev_main,prev_skip;
    logic signed [63:0] prev_wide;
    string case_dir,dump_path;
    stem_residual dut(.*);
    always #5 clk=~clk;
    always @(negedge clk) begin
        cycles=cycles+1;
        stem_mac_ready=1;block_mac_ready=1;link_ready=!force_link_hold;
        conv_ready=1;y_ready=!force_y_hold;rsp_ready=!force_rsp_hold;
        if(mode==1 && busy && !rst) begin
            stem_mac_ready=cycles%5!=0;block_mac_ready=cycles%7!=0;
            link_ready=!(bridge_valid && !held_bridge);
            conv_ready=!(conv_valid && !held_conv);
            y_ready=!(y_valid && !held_y);
        end
    end
    always @(posedge clk) begin
        if(rst) begin
            bridges=0;h_count=0;m_count=0;outputs=0;smacs=0;bmacs=0;responses=0;
            held_bridge=0;held_conv=0;held_y=0;held_rsp=0;last_done=0;
        end else begin
            if(held_bridge && (!bridge_valid || bridge_addr!==prev_bridge_addr || bridge_acc!==prev_bridge_acc
                || bridge_code!==prev_bridge_code || bridge_count!==prev_bridge_count || block_input_count!==prev_input_count)) $fatal(1,"BRIDGE_HOLD_VIOLATION");
            if(held_conv && (!conv_valid || conv_addr!==prev_conv_addr || conv_phase!==prev_conv_phase || conv_acc!==prev_conv_acc || conv_code!==prev_conv_code)) $fatal(1,"CONV_HOLD_VIOLATION");
            if(held_y && (!y_valid || y_addr!==prev_y_addr || y_code!==prev_y_code || add_wide!==prev_wide || add_main!==prev_main || add_skip!==prev_skip)) $fatal(1,"Y_HOLD_VIOLATION");
            if(held_rsp && !rsp_valid) $fatal(1,"RESPONSE_HOLD_VIOLATION");
            held_bridge=bridge_valid && !bridge_ready;held_conv=conv_valid && !conv_ready;
            held_y=y_valid && !y_ready;held_rsp=rsp_valid && !rsp_ready;
            prev_bridge_addr=bridge_addr;prev_bridge_acc=bridge_acc;prev_bridge_code=bridge_code;prev_bridge_count=bridge_count;prev_input_count=block_input_count;
            prev_conv_addr=conv_addr;prev_conv_phase=conv_phase;prev_conv_acc=conv_acc;prev_conv_code=conv_code;
            prev_y_addr=y_addr;prev_y_code=y_code;prev_main=add_main;prev_skip=add_skip;prev_wide=add_wide;
            if(held_bridge) bridge_stalls=bridge_stalls+1;
            if(held_conv) conv_stalls=conv_stalls+1;
            if(held_y) y_stalls=y_stalls+1;
            if(held_rsp) rsp_stalls=rsp_stalls+1;
            if(stem_mac_valid && !stem_mac_ready) smac_stalls=smac_stalls+1;
            if(block_mac_valid && !block_mac_ready) bmac_stalls=bmac_stalls+1;
            if(busy && (cfg_ready || start_ready)) $fatal(1,"BUSY_HOST_READY");
            if(stage==3 && (bridge_count!=16384 || block_input_count!=16384 || dut.s_busy || !dut.r_prepared)) $fatal(1,"BLOCK_START_WITHOUT_DRAINED_STEM");
            if(stem_mac_fire) smacs=smacs+1;
            if(block_mac_fire) begin
                if(bridges!=16384 || bridge_count!=16384 || block_input_count!=16384 || smacs!=442368) $fatal(1,"BLOCK_STARTED_EARLY");
                bmacs=bmacs+1;
            end
            if(bridge_valid && bridge_ready) begin
                if(int'(bridge_addr)!=bridges || int'(bridge_count)!=bridges || int'(block_input_count)!=bridges) $fatal(1,"BRIDGE_ORDER");
                if(bridge_acc!==sa[bridge_addr]) $fatal(1,"STEM_ACC_MISMATCH addr=%0d",bridge_addr);
                if(bridge_code!==sx[bridge_addr]) $fatal(1,"BRIDGE_CODE_MISMATCH addr=%0d actual=%0d expected=%0d",bridge_addr,bridge_code,$signed(sx[bridge_addr]));
                forwarded[bridge_addr]=bridge_code;
                if(dump_fd!=0) $fdisplay(dump_fd,"%0d,%0d,0,%0d,%0d,0,%0d,0,0",jobs,case_id,bridge_addr,bridge_acc,bridge_code);
                bridges=bridges+1;
            end
            if(conv_valid && conv_ready) begin
                if(!conv_phase) begin
                    if(int'(conv_addr)!=h_count || m_count!=0 || outputs!=0) $fatal(1,"H_ORDER");
                    if(conv_acc!==a1[conv_addr] || conv_code!==h[conv_addr]) $fatal(1,"H_BOUNDARY_MISMATCH addr=%0d",conv_addr);
                    h_count=h_count+1;
                end else begin
                    if(h_count!=16384 || int'(conv_addr)!=m_count || outputs!=0) $fatal(1,"M_ORDER");
                    if(conv_acc!==a2[conv_addr]) $fatal(1,"ACC2_MISMATCH addr=%0d",conv_addr);
                    if(conv_code!==m[conv_addr]) $fatal(1,"M_CODE_MISMATCH addr=%0d",conv_addr);
                    m_count=m_count+1;
                end
                if(dump_fd!=0) $fdisplay(dump_fd,"%0d,%0d,%0d,%0d,%0d,0,%0d,0,0",jobs,case_id,int'(conv_phase)+1,conv_addr,conv_acc,conv_code);
            end
            if(y_valid && y_ready) begin
                if(h_count!=16384 || m_count!=16384 || int'(y_addr)!=outputs) $fatal(1,"Y_ORDER");
                if(add_main!==m[y_addr] || add_skip!==forwarded[y_addr] || add_skip!==sx[y_addr]) $fatal(1,"SKIP_PAIR_MISMATCH addr=%0d",y_addr);
                if(add_wide!==aw[y_addr]) $fatal(1,"ADD_WIDE_MISMATCH addr=%0d",y_addr);
                if(y_code!==y[y_addr]) $fatal(1,"Y_CODE_MISMATCH addr=%0d",y_addr);
                if(outputs==0) $display("FIRST_Y case=%0d code=%0d skip=%0d main=%0d",case_id,y_code,add_skip,add_main);
                if(dump_fd!=0) $fdisplay(dump_fd,"%0d,%0d,3,%0d,0,%0d,%0d,%0d,%0d",jobs,case_id,y_addr,add_wide,y_code,add_main,add_skip);
                outputs=outputs+1;
            end
            if(rsp_valid) begin
                if(bridges!=16384 || outputs!=16384 || smacs!=442368 || bmacs!=4718592 || done) $fatal(1,"EARLY_RESPONSE");
                if(rsp_ready) responses=responses+1;
            end
            if(done && (responses!=1 || outputs!=16384 || last_done)) $fatal(1,"DONE_CONTRACT");
            last_done=done;
        end
    end
    task automatic read_case(input integer which);
        case_id=which;
        if(which==0) case_dir="reference/e2b_v1/chain_vectors/actual0";
        else case_dir="reference/e2b_v1/chain_vectors/synthetic_zero";
        $readmemh({case_dir,"/input.hex"},x);$readmemh({case_dir,"/stem_acc.hex"},sa);$readmemh({case_dir,"/stem.hex"},sx);
        $readmemh({case_dir,"/acc1.hex"},a1);$readmemh({case_dir,"/h.hex"},h);$readmemh({case_dir,"/acc2.hex"},a2);$readmemh({case_dir,"/m.hex"},m);
        $readmemh({case_dir,"/add_wide.hex"},aw);$readmemh({case_dir,"/y.hex"},y);
    endtask
    task automatic write_word(input integer target,input integer kind,input integer addr,input logic [31:0] data,input bit expect_error);
        @(negedge clk);cfg_valid=1;cfg_target=2'(target);cfg_kind=4'(kind);cfg_addr=15'(addr);cfg_data=data;
        @(posedge clk);if(!cfg_ready) $fatal(1,"LOADER_NOT_READY");
        @(negedge clk);cfg_valid=0;if(load_error!==expect_error) $fatal(1,"LOAD_ERROR_EXPECTATION target=%0d kind=%0d",target,kind);
    endtask
    task automatic begin_load;
        @(negedge clk);load_begin=1;
        @(negedge clk);load_begin=0;
        if(prepared || bridge_count!=0 || block_input_count!=0 || fault) $fatal(1,"LOAD_BEGIN_CONTRACT");
    endtask
    task automatic load_all;
        begin_load();
        for(integer j=0;j<3072;j=j+1) write_word(0,0,j,{24'd0,x[j]},0);
        for(integer j=0;j<432;j=j+1) write_word(0,1,j,{24'd0,sw[j]},0);
        for(integer j=0;j<16;j=j+1) begin write_word(0,2,j,sb[j],0);write_word(0,3,j,sn[j],0);write_word(0,4,j,ss[j],0);end
        for(integer j=0;j<2304;j=j+1) begin write_word(1,1,j,{24'd0,w1[j]},0);write_word(1,2,j,{24'd0,w2[j]},0);end
        for(integer j=0;j<16;j=j+1) begin
            write_word(1,3,j,b1[j],0);write_word(1,4,j,b2[j],0);write_word(1,5,j,n1[j],0);write_word(1,6,j,n2[j],0);write_word(1,7,j,s1[j],0);write_word(1,8,j,s2[j],0);
        end
        for(integer j=0;j<3;j=j+1) write_word(1,9,j,ac[j],0);
        if(!prepared || block_input_count!=0 || dut.r_prepared) $fatal(1,"PREPARED_WITHOUT_COMPUTED_X");
        $display("LOAD_PASS case=%0d host_block_x_writes=0 block_input_count=0 constants_ready=1",case_id);
    endtask
    task automatic reject_start;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        if(!start_rejected || busy || done || y_valid || rsp_valid) $fatal(1,"UNPREPARED_START_ACCEPTED");
    endtask
    task automatic launch;
        @(negedge clk);bridges=0;h_count=0;m_count=0;outputs=0;smacs=0;bmacs=0;responses=0;
        if(!start_ready) $fatal(1,"START_NOT_READY");start=1;
        @(negedge clk);start=0;
    endtask
    task automatic finish_job;
        integer timeout_count;
        timeout_count=0;
        while(!done && timeout_count<30000000) begin @(negedge clk);timeout_count=timeout_count+1;if(fault) $fatal(1,"UNEXPECTED_CHAIN_FAULT %0d",fault_code);end
        if(!done || responses!=1 || outputs!=16384 || bridges!=16384 || h_count!=16384 || m_count!=16384 || smacs!=442368 || bmacs!=4718592) $fatal(1,"TIMEOUT_OR_COUNTS");
        for(integer j=0;j<16384;j=j+1) begin
            if(dut.block_core.x_mem[j]!==forwarded[j] || forwarded[j]!==sx[j] || dut.block_core.work_mem[j]!==y[j] || dut.block_core.main_mem[j]!==m[j]) $fatal(1,"BUFFER_LIFETIME addr=%0d",j);
            lifetime_checks=lifetime_checks+3;
        end
        $display("JOB_PASS mode=%0d job=%0d case=%0d bridges=16384 h=16384 m=16384 y=16384 stem_macs=442368 block_macs=4718592 mismatches=0",mode,jobs,case_id);
        jobs=jobs+1;repeat(2) @(negedge clk);
        if(prepared || start_ready) $fatal(1,"STALE_FRAME_ARMED");reject_start();
    endtask
    task automatic cancel_and_check(input integer point);
        @(negedge clk);$display("CANCELLED point=%0d bridges=%0d h=%0d m=%0d y=%0d",point,bridges,h_count,m_count,outputs);rst=1;cancelled=cancelled+1;
        repeat(2) @(negedge clk);rst=0;force_link_hold=0;force_y_hold=0;force_rsp_hold=0;
        repeat(4) begin @(negedge clk);if(busy || prepared || bridge_valid || conv_valid || y_valid || rsp_valid || done || block_input_count!=0 || bridge_count!=0) $fatal(1,"RESET_LEAK");end
        reject_start();
    endtask
    initial begin
        if(!$value$plusargs("MODE=%d",mode)) mode=0;
        if(!$value$plusargs("DUMP=%s",dump_path)) dump_path="";
        if(!$value$plusargs("TRACE=%d",trace_enable)) trace_enable=0;
        if(dump_path!="") begin dump_fd=$fopen(dump_path,"w");if(dump_fd==0) $fatal(1,"DUMP_OPEN_FAILED");$fdisplay(dump_fd,"job,case,stage,address,acc,wide,code,main,skip");end
        $readmemh("reference/e2b_v1/stem_vectors/weight.hex",sw);$readmemh("reference/e2b_v1/stem_vectors/bias.hex",sb);
        $readmemh("reference/e2b_v1/stem_vectors/multiplier.hex",sn);$readmemh("reference/e2b_v1/stem_vectors/shift.hex",ss);
        $readmemh("reference/e2b_v1/residual_l10_vectors/weight1.hex",w1);$readmemh("reference/e2b_v1/residual_l10_vectors/weight2.hex",w2);
        $readmemh("reference/e2b_v1/residual_l10_vectors/bias1.hex",b1);$readmemh("reference/e2b_v1/residual_l10_vectors/bias2.hex",b2);
        $readmemh("reference/e2b_v1/residual_l10_vectors/multiplier1.hex",n1);$readmemh("reference/e2b_v1/residual_l10_vectors/multiplier2.hex",n2);
        $readmemh("reference/e2b_v1/residual_l10_vectors/shift1.hex",s1);$readmemh("reference/e2b_v1/residual_l10_vectors/shift2.hex",s2);
        $readmemh("reference/e2b_v1/residual_l10_vectors/add_config.hex",ac);read_case(0);
        if(mode==6) sx[0]=sx[0]^8'd1;
        if(mode==7) m[0]=m[0]^8'd1;
        if(mode==8) y[0]=y[0]^8'd1;
        if(mode==9) aw[0]=aw[0]^64'd1;
        repeat(3) @(negedge clk);rst=0;reject_start();
        if(mode==5) begin
            begin_load();
            write_word(1,0,0,32'd20,1);write_word(2,0,0,0,1);write_word(0,0,4096,0,1);
            write_word(0,8,0,0,1);write_word(1,10,0,0,1);write_word(0,1,0,32'h80,1);
            write_word(1,9,2,32'd32,1);write_word(1,5,0,32'hffffffff,1);
            if(block_input_count!=0 || prepared || dut.unused_s_weight_count!=0) $fatal(1,"INVALID_ROUTE_WROTE_DATA");
            $display("LOADER_NEGATIVE_PASS rejected=8 host_block_x_rejected=1");
        end
        load_all();
        if(mode==10) begin
            for(integer j=0;j<3072;j=j+1) write_word(0,0,j,32'd127,0);
            for(integer j=0;j<27;j=j+1) write_word(0,1,j,32'd127,0);
            write_word(0,2,0,32'h7fffffff,0);
        end
        if(mode==11) begin
            for(integer j=0;j<144;j=j+1) write_word(1,1,j,32'd127,0);
            write_word(1,3,0,32'h7fffffff,0);
        end
        launch();
        if(trace_enable!=0) begin
            $dumpfile("results/stem_residual_rtl/first_bridge.vcd");
            wait(bridge_count>=35);$dumpvars;repeat(500) @(negedge clk);
            $display("TRACE_WINDOW_ONLY cycles=500 completed_jobs=0");$finish;
        end
        if(mode==10 || mode==11) begin
            wait(fault);repeat(3) @(negedge clk);
            if(fault_code!=(mode==10?3'd1:3'd2) || busy || done || rsp_valid || y_valid || cfg_ready || start_ready || outputs!=0) $fatal(1,"FAULT_PROPAGATION");
            $display("FAULT_PASS source=%0d outputs=0 response=0",fault_code);
            load_all();if(fault || !prepared) $fatal(1,"FAULT_CLEAR_PREPARE");
            $display("FAULT_CLEAR_PASS prepared=1 compute_rerun=0");$finish;
        end
        if(mode==1) begin
            force_rsp_hold=1;
            @(negedge clk);cfg_valid=1;cfg_target=1;cfg_kind=0;cfg_addr=0;cfg_data=0;start=1;
            repeat(2) begin @(negedge clk);if(cfg_ready || !start_rejected) $fatal(1,"BUSY_COMMAND_ACCEPTED");end
            cfg_valid=0;start=0;$display("BUSY_COMMAND_PASS cfg_blocked=1 start_rejected=1");
            wait(rsp_valid);repeat(5) @(negedge clk);if(done) $fatal(1,"RESPONSE_NOT_HELD");force_rsp_hold=0;
        end
        if(mode==2) begin
            wait(bridge_count>=37);force_link_hold=1;wait(bridge_valid && !bridge_ready);repeat(3) @(negedge clk);cancel_and_check(0);
            load_all();launch();wait(m_count>=19);cancel_and_check(1);
            load_all();force_y_hold=1;launch();wait(y_valid);repeat(3) @(negedge clk);cancel_and_check(2);
            load_all();launch();
        end
        finish_job();
        if(mode==0) begin
            read_case(1);load_all();launch();finish_job();
            read_case(0);load_all();launch();finish_job();
        end
        if(mode==1 && (bridge_stalls==0 || conv_stalls==0 || y_stalls==0 || rsp_stalls==0 || smac_stalls==0 || bmac_stalls==0)) $fatal(1,"STALL_NOT_EXERCISED");
        if(dump_fd!=0) $fclose(dump_fd);
        $display("CASE_PASS mode=%0d jobs=%0d cancelled=%0d bridge_stalls=%0d conv_stalls=%0d y_stalls=%0d rsp_stalls=%0d stem_mac_stalls=%0d block_mac_stalls=%0d lifetime_checks=%0d",mode,jobs,cancelled,bridge_stalls,conv_stalls,y_stalls,rsp_stalls,smac_stalls,bmac_stalls,lifetime_checks);$finish;
    end
endmodule
