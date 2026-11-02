`timescale 1ns/1ps
module tb_full;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,load_begin=0,cfg_valid=0,start=0,compute_ready=1,trace_ready=1,rsp_ready=1;
    logic cfg_ready,load_error,prepared,start_ready,start_rejected,busy,done,fault;
    logic [2:0] cfg_kind=0,fault_code;
    logic [18:0] cfg_addr=0,weight_count;
    logic [31:0] cfg_data=0;
    logic [12:0] input_count;
    logic [9:0] bias_count,n_count,shift_count;
    logic step_valid,mac_fire,gap_fire,trace_valid,trace_skip_from_x,rsp_valid,result_valid;
    logic [4:0] trace_op;
    logic [13:0] trace_addr,trace_skip_addr;
    logic signed [31:0] trace_acc,trace_code,score_read_data;
    logic signed [7:0] trace_skip;
    logic signed [63:0] trace_wide;
    logic [3:0] prediction,score_read_addr=0;
    full_model dut(.*);
    logic [7:0] stimulus[0:3071],weights[0:268335],eskip[0:274505];
    logic [31:0] biases[0:697],ns[0:697],rs[0:697];
    logic signed [31:0] eacc[0:274505],ecode[0:274505],eaddr[0:274505];
    logic signed [63:0] ewide[0:274505];
    integer kind[0:29],nout[0:29],src[0:29],dst[0:29],skip[0:29],source_offset[0:29],source_len[0:29],skip_offset[0:29],skip_len[0:29],trace_offset[0:29];
    integer mode=0,case_id=0,job=0,events=0,expected_op=0,expected_addr=0,boundaries=1;
    integer macs=0,gaps=0,compute_stalls=0,trace_stalls=0,rsp_stalls=0,cycles=0,fd=0;
    integer held_edges=0,reset_cancels=0,loader_checks=0;
    bit checking=0,stall_enable=0,force_hold_rsp=0,trace_waited=0,hold_trace=0,hold_mac=0,hold_rsp=0;
    logic [169:0] old_trace;
    logic [76:0] old_mac;
    logic [3:0] old_prediction;
    string dump_path;

    // Drive stalls away from the sampling edge. Hold each trace once in mode 1.
    always @(negedge clk) begin
        cycles=cycles+1;
        compute_ready=!(stall_enable && cycles%7==0);
        trace_ready=!(stall_enable && trace_valid && !trace_waited);
        if(!trace_valid || trace_ready) trace_waited=0;else trace_waited=1;
        rsp_ready=!force_hold_rsp;
        if(cycles>900000000) $fatal(1,"GLOBAL_TIMEOUT");
    end
    always @(posedge clk) begin : scoreboard
        integer ix,op,ad,base,actual_value,wanted_value;
        logic [169:0] current_trace;
        logic [76:0] current_mac;
        current_trace={trace_op,trace_addr,trace_acc,trace_code,trace_skip,trace_wide,trace_skip_from_x,trace_skip_addr};
        current_mac={dut.acc,dut.term_idx,dut.pair_x,dut.pair_w,dut.op_id,dut.out_idx};
        if(rst) begin hold_trace=0;hold_mac=0;hold_rsp=0;end
        else begin
            if(hold_trace && (!trace_valid || current_trace!==old_trace)) $fatal(1,"TRACE_HOLD_CHANGED");
            if(hold_mac && current_mac!==old_mac) $fatal(1,"MAC_HOLD_CHANGED");
            if(hold_rsp && (!rsp_valid || !result_valid || prediction!==old_prediction)) $fatal(1,"RSP_HOLD_CHANGED");
            hold_trace=trace_valid && !trace_ready;old_trace=current_trace;
            hold_mac=step_valid && !compute_ready;old_mac=current_mac;
            hold_rsp=rsp_valid && !rsp_ready;old_prediction=prediction;
            if(checking) begin
                if(mac_fire) macs=macs+1;
                if(gap_fire) gaps=gaps+1;
                if(step_valid && !compute_ready) compute_stalls=compute_stalls+1;
                if(trace_valid && !trace_ready) trace_stalls=trace_stalls+1;
                if(rsp_valid && !rsp_ready) rsp_stalls=rsp_stalls+1;
                if(fault && mode!=11) $fatal(1,"UNEXPECTED_FAULT code=%0d",fault_code);
                if(trace_valid && trace_ready) begin
                    op=int'(trace_op);ad=int'(trace_addr);ix=trace_offset[op]+ad;
                    if(op!=expected_op || ad!=expected_addr) $fatal(1,"TRACE_ORDER op=%0d addr=%0d expected=%0d/%0d",op,ad,expected_op,expected_addr);
                    // Read-only inspection: every source bank must contain preceding RTL output.
                    if(ad==0) begin
                        for(integer i=0;i<source_len[op];i=i+1) begin
                            base=source_offset[op];
                            wanted_value=base<0?int'($signed(stimulus[i])):ecode[base+i];
                            actual_value=int'(dut.feature_mem.mem[src[op]*16384+i]);
                            if(actual_value!=wanted_value) $fatal(1,"SOURCE_BANK op=%0d index=%0d got=%0d expected=%0d",op,i,actual_value,wanted_value);
                        end
                        if(kind[op]==1) for(integer i=0;i<skip_len[op];i=i+1)
                            if(int'(dut.feature_mem.mem[skip[op]*16384+i])!=ecode[skip_offset[op]+i]) $fatal(1,"SKIP_BANK op=%0d index=%0d",op,i);
                    end
                    if(trace_code!==ecode[ix]) $fatal(1,"CODE_MISMATCH op=%0d addr=%0d got=%0d expected=%0d",op,ad,trace_code,ecode[ix]);
                    if(kind[op]!=1 && trace_acc!==eacc[ix]) $fatal(1,"ACC_MISMATCH op=%0d addr=%0d got=%0d expected=%0d",op,ad,trace_acc,eacc[ix]);
                    if(kind[op]==1 && trace_skip!==eskip[ix]) $fatal(1,"SKIP_MISMATCH op=%0d addr=%0d",op,ad);
                    if(trace_wide!==ewide[ix]) $fatal(1,"WIDE_MISMATCH op=%0d addr=%0d got=%0d expected=%0d",op,ad,trace_wide,ewide[ix]);
                    if(kind[op]==1 && (trace_skip_from_x!=(eaddr[ix]>=0) || (eaddr[ix]>=0 && int'(trace_skip_addr)!=eaddr[ix]))) $fatal(1,"SKIP_ADDRESS op=%0d addr=%0d",op,ad);
                    if(fd!=0) $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d",op,ad,trace_acc,trace_code,trace_skip,trace_wide,kind[op]==1?eaddr[ix]:-1);
                    events=events+1;expected_addr=expected_addr+1;
                    if(expected_addr==nout[op]) begin
                        boundaries=boundaries+2;expected_op=expected_op+1;expected_addr=0;
                        $display("OP_PASS job=%0d sample=%0d op=%0d outputs=%0d boundaries=%0d",job,case_id,op,nout[op],boundaries);
                    end
                end
            end
        end
    end
    task automatic reset_core;
        @(negedge clk);rst=1;cfg_valid=0;start=0;load_begin=0;checking=0;
        repeat(3) @(negedge clk);rst=0;
        @(negedge clk);
        if(busy || prepared || result_valid || rsp_valid || fault || input_count!=0 || weight_count!=0 || bias_count!=0 || n_count!=0 || shift_count!=0) $fatal(1,"RESET_NOT_CLEAN");
    endtask
    task automatic load_case(input integer cid);
        case_id=cid;
        $readmemh($sformatf("reference/e2b_v1/full_vectors/sample%0d/input.hex",cid),stimulus);
        $readmemh($sformatf("reference/e2b_v1/full_vectors/sample%0d/acc.hex",cid),eacc);
        $readmemh($sformatf("reference/e2b_v1/full_vectors/sample%0d/code.hex",cid),ecode);
        $readmemh($sformatf("reference/e2b_v1/full_vectors/sample%0d/skip.hex",cid),eskip);
        $readmemh($sformatf("reference/e2b_v1/full_vectors/sample%0d/wide.hex",cid),ewide);
        $readmemh($sformatf("reference/e2b_v1/full_vectors/sample%0d/skip_addr.hex",cid),eaddr);
        if(mode==6) ecode[0]=ecode[0]^1;
        if(mode==7) eskip[trace_offset[12]+2048]=eskip[trace_offset[12]+2048]^1;
        if(mode==8) eacc[trace_offset[28]]=eacc[trace_offset[28]]^1;
        if(mode==9) ecode[trace_offset[29]]=ecode[trace_offset[29]]^1;
    endtask
    task automatic word(input integer typ,addr,input logic [31:0] value,input bit bad);
        @(negedge clk);cfg_valid=1;cfg_kind=3'(typ);cfg_addr=19'(addr);cfg_data=value;
        if(!cfg_ready) $fatal(1,"LOADER_NOT_READY");
        @(posedge clk);#1;
        if(load_error!=bad) $fatal(1,"LOADER_ERROR_EXPECTATION kind=%0d addr=%0d",typ,addr);
        if(bad) loader_checks=loader_checks+1;
    endtask
    task automatic prepare;
        checking=0;
        @(negedge clk);load_begin=1;cfg_valid=0;
        @(negedge clk);load_begin=0;
        for(integer i=0;i<3072;i=i+1) word(0,i,{24'd0,stimulus[i]},0);
        for(integer i=0;i<268336;i=i+1) word(1,i,{24'd0,weights[i]},0);
        for(integer i=0;i<698;i=i+1) word(2,i,biases[i],0);
        for(integer i=0;i<698;i=i+1) word(3,i,ns[i],0);
        for(integer i=0;i<698;i=i+1) word(4,i,rs[i],0);
        @(negedge clk);cfg_valid=0;#1;
        if(!prepared || !start_ready) $fatal(1,"PREPARE_INCOMPLETE");
        for(integer i=0;i<3072;i=i+1) if(dut.feature_mem.mem[i]!==stimulus[i]) $fatal(1,"INPUT_BOUNDARY index=%0d",i);
    endtask
    task automatic launch;
        force_hold_rsp=1;
        events=0;expected_op=0;expected_addr=0;boundaries=1;macs=0;gaps=0;compute_stalls=0;trace_stalls=0;rsp_stalls=0;checking=1;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        if(!busy || prepared) $fatal(1,"START_FAILED");
    endtask
    task automatic finish_job;
        wait(rsp_valid);@(negedge clk);
        if(events!=274506 || boundaries!=61 || macs!=40551040 || gaps!=4096 || !result_valid || prediction!=(case_id==0?3:8)) $fatal(1,"JOB_COUNTS_OR_PREDICTION events=%0d boundaries=%0d macs=%0d gaps=%0d prediction=%0d",events,boundaries,macs,gaps,prediction);
        for(integer i=0;i<10;i=i+1) begin
            score_read_addr=4'(i);#1;
            if(score_read_data!==ecode[trace_offset[29]+i]) $fatal(1,"FINAL_SCORE index=%0d",i);
            $display("SCORE job=%0d sample=%0d class=%0d value=%0d",job,case_id,i,score_read_data);
        end
        if(stall_enable && (compute_stalls==0 || trace_stalls==0 || rsp_stalls==0)) $fatal(1,"STALL_NOT_EXERCISED");
        force_hold_rsp=0;
        wait(done);@(negedge clk);checking=0;
        if(busy || prepared || !result_valid) $fatal(1,"COMPLETION_STATE");
        $display("JOB_PASS job=%0d sample=%0d boundaries=%0d elements=552084 events=%0d macs=%0d gaps=%0d prediction=%0d compute_stalls=%0d trace_stalls=%0d rsp_stalls=%0d",job,case_id,boundaries,events,macs,gaps,prediction,compute_stalls,trace_stalls,rsp_stalls);
        job=job+1;
    endtask
    task automatic cancel_reset(input integer location);
        $display("RESET_CANCEL location=%0d op=%0d events=%0d",location,trace_op,events);
        reset_cancels=reset_cancels+1;reset_core();force_hold_rsp=0;
    endtask
    initial begin
        if($value$plusargs("MODE=%d",mode)) begin end
        if($value$plusargs("DUMP=%s",dump_path)) begin fd=$fopen(dump_path,"w");if(fd==0) $fatal(1,"DUMP_OPEN");end
        $readmemh("reference/e2b_v1/full_vectors/constants/weight.hex",weights);
        $readmemh("reference/e2b_v1/full_vectors/constants/bias.hex",biases);
        $readmemh("reference/e2b_v1/full_vectors/constants/multiplier.hex",ns);
        $readmemh("reference/e2b_v1/full_vectors/constants/shift.hex",rs);
        $readmemh("reference/e2b_v1/full_vectors/layout/kind.hex",kind);
        $readmemh("reference/e2b_v1/full_vectors/layout/nout.hex",nout);
        $readmemh("reference/e2b_v1/full_vectors/layout/src.hex",src);
        $readmemh("reference/e2b_v1/full_vectors/layout/dst.hex",dst);
        $readmemh("reference/e2b_v1/full_vectors/layout/skip.hex",skip);
        $readmemh("reference/e2b_v1/full_vectors/layout/source_offset.hex",source_offset);
        $readmemh("reference/e2b_v1/full_vectors/layout/source_len.hex",source_len);
        $readmemh("reference/e2b_v1/full_vectors/layout/skip_offset.hex",skip_offset);
        $readmemh("reference/e2b_v1/full_vectors/layout/skip_len.hex",skip_len);
        $readmemh("reference/e2b_v1/full_vectors/layout/trace_offset.hex",trace_offset);
        reset_core();load_case(0);
        if(mode==10) begin
            @(negedge clk);load_begin=1;@(negedge clk);load_begin=0;
            word(0,1,0,1);word(0,0,0,0);word(0,0,0,1);word(0,3072,0,1);word(0,1,256,1);
            word(1,0,128,1);word(1,1,0,1);word(2,698,0,1);word(3,0,32'hffffffff,1);word(4,0,32,1);word(5,0,0,1);
            @(negedge clk);cfg_valid=0;start=1;@(posedge clk);#1;
            if(!start_rejected || busy || prepared) $fatal(1,"INCOMPLETE_START_ACCEPTED");
            $display("LOADER_PASS rejected=%0d",loader_checks);$finish;
        end
        if(mode==11) begin
            for(integer i=0;i<3072;i=i+1) stimulus[i]=127;
            for(integer i=0;i<27;i=i+1) weights[i]=127;
            biases[0]=32'h7fffffff;prepare();launch();
            wait(fault);@(negedge clk);
            if(fault_code!=1 || rsp_valid || done || result_valid) $fatal(1,"OVERFLOW_GUARD_FAILED");
            checking=0;reset_core();$display("OVERFLOW_PASS code=1 reset_clean=1");$finish;
        end
        if(mode==2) begin
            prepare();launch();wait(events>=37);cancel_reset(0);
            load_case(0);prepare();launch();wait(trace_op==11 && trace_addr>=19);cancel_reset(1);
            load_case(0);prepare();force_hold_rsp=1;launch();wait(rsp_valid);repeat(5) @(negedge clk);cancel_reset(2);
            load_case(1);prepare();launch();finish_job();
            $display("RESET_PASS cancelled=%0d recovered_sample=1",reset_cancels);
        end else if(mode==1) begin
            stall_enable=1;force_hold_rsp=1;prepare();launch();
            @(negedge clk);cfg_valid=1;cfg_kind=0;cfg_addr=0;cfg_data=0;start=1;load_begin=1;
            @(posedge clk);#1;if(cfg_ready || !start_rejected || input_count!=3072) $fatal(1,"BUSY_HOST_GUARD");
            @(negedge clk);cfg_valid=0;start=0;load_begin=0;
            wait(rsp_valid);repeat(5) @(negedge clk);finish_job();
            @(negedge clk);start=1;@(posedge clk);#1;if(!start_rejected || busy) $fatal(1,"STALE_RESTART_ACCEPTED");
            @(negedge clk);start=0;$display("BUSY_STALE_GUARD_PASS");
        end else begin
            prepare();launch();finish_job();
            if(fd!=0) begin $fclose(fd);fd=0;end
            if(mode==0) begin load_case(1);prepare();launch();finish_job();load_case(0);prepare();launch();finish_job();end
        end
        if(mode>=6 && mode<=9) $fatal(1,"WRONG_GOLDEN_ACCEPTED");
        $display("CASE_PASS mode=%0d jobs=%0d",mode,job);$finish;
    end
endmodule
