`timescale 1ns/1ps
// PS AXI-Lite master and DDR-backed DMA stream BFMs; not a CPU/DDR PHY model.
module tb_ps_packed;
    logic aclk=0;always #5 aclk=~aclk;wire clk=aclk;
    logic aresetn=0;
    logic [11:0] s_axi_awaddr=0,s_axi_araddr=0;
    logic [2:0] s_axi_awprot=0,s_axi_arprot=0;
    logic s_axi_awvalid=0,s_axi_wvalid=0,s_axi_bready=0,s_axi_arvalid=0,s_axi_rready=0;
    wire s_axi_awready,s_axi_wready,s_axi_bvalid,s_axi_arready,s_axi_rvalid;
    logic [31:0] s_axi_wdata=0;
    logic [3:0] s_axi_wstrb=0;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_bresp,s_axi_rresp;
    logic [31:0] s_axis_tdata=0;
    logic [3:0] s_axis_tkeep=15;
    logic s_axis_tlast=0,s_axis_tvalid=0,m_axis_tready=0;
    wire s_axis_tready,m_axis_tlast,m_axis_tvalid;
    wire [31:0] m_axis_tdata;
    wire [3:0] m_axis_tkeep;
    resnet20_axi_packed dut(.*);
    wire rst=!aresetn || dut.soft_reset;
    wire compute_ready=dut.compute_ready,trace_ready=dut.trace_ready,rsp_ready=dut.rsp_ready;
    wire prepared=dut.prepared,start_ready=dut.start_ready,busy=dut.busy,done=dut.done,fault=dut.fault;
    wire [2:0] fault_code=dut.fault_code;
    wire step_valid=dut.step_valid,mac_fire=dut.mac_fire,gap_fire=dut.gap_fire;
    wire trace_valid=dut.trace_valid,trace_skip_from_x=dut.trace_skip_from_x,rsp_valid=dut.rsp_valid,result_valid=dut.result_valid;
    wire [4:0] trace_op=dut.trace_op;
    wire [13:0] trace_addr=dut.trace_addr,trace_skip_addr=dut.trace_skip_addr;
    wire signed [31:0] trace_acc=dut.trace_acc,trace_code=dut.trace_code;
    wire signed [7:0] trace_skip=dut.trace_skip;
    wire signed [63:0] trace_wide=dut.trace_wide;
    wire [3:0] prediction=dut.prediction;
    logic [31:0] ddr_tx[0:268338],ddr_rx[0:15];
    logic [31:0] expected_tag;
    integer axi_checks=0,packet_checks=0,axis_holds=0;
    logic old_out_hold=0;
    logic [36:0] old_out;
    always @(posedge clk) begin
        if(rst) old_out_hold=0;
        else begin
            if(old_out_hold && (!m_axis_tvalid || {m_axis_tlast,m_axis_tkeep,m_axis_tdata}!==old_out)) $fatal(1,"S2MM_HOLD_CHANGED");
            old_out_hold=m_axis_tvalid && !m_axis_tready;old_out={m_axis_tlast,m_axis_tkeep,m_axis_tdata};
            if(old_out_hold) axis_holds=axis_holds+1;
        end
    end
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

    always @(posedge clk) begin : scoreboard
        integer ix,op,ad,base,actual_value,wanted_value;
        logic [169:0] current_trace;
        logic [76:0] current_mac;
        current_trace={trace_op,trace_addr,trace_acc,trace_code,trace_skip,trace_wide,trace_skip_from_x,trace_skip_addr};
        current_mac={dut.core.acc,dut.core.term_idx,dut.core.pair_x,dut.core.pair_w,dut.core.op_id,dut.core.out_idx};
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
                            actual_value=int'(dut.core.feature_mem.mem[src[op]*16384+i]);
                            if(actual_value!=wanted_value) $fatal(1,"SOURCE_BANK op=%0d index=%0d got=%0d expected=%0d",op,i,actual_value,wanted_value);
                        end
                        if(kind[op]==1) for(integer i=0;i<skip_len[op];i=i+1)
                            if(int'(dut.core.feature_mem.mem[skip[op]*16384+i])!=ecode[skip_offset[op]+i]) $fatal(1,"SKIP_BANK op=%0d index=%0d",op,i);
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

    always @(negedge clk) begin
        cycles=cycles+1;
        if(cycles>1100000000) $fatal(1,"GLOBAL_TIMEOUT");
    end
    task automatic axi_write(input logic [11:0] address,input logic [31:0] data,
        input logic [3:0] strobes=15,input integer order=0,input logic [1:0] response=0);
        logic [1:0] saved;
        fork
            begin
                repeat(order==2?3:0) @(negedge clk);
                @(negedge clk);s_axi_awaddr=address;s_axi_awvalid=1;
                do @(posedge clk);while(!s_axi_awready);
                @(negedge clk);s_axi_awvalid=0;
            end
            begin
                repeat(order==1?3:0) @(negedge clk);
                @(negedge clk);s_axi_wdata=data;s_axi_wstrb=strobes;s_axi_wvalid=1;
                do @(posedge clk);while(!s_axi_wready);
                @(negedge clk);s_axi_wvalid=0;
            end
        join
        wait(s_axi_bvalid);saved=s_axi_bresp;
        repeat(3) begin @(negedge clk);if(!s_axi_bvalid || s_axi_bresp!==saved) $fatal(1,"BRESP_HOLD");end
        if(saved!==response) $fatal(1,"AXI_WRITE address=%h response=%d expected=%d",address,saved,response);
        s_axi_bready=1;@(posedge clk);@(negedge clk);s_axi_bready=0;axi_checks=axi_checks+1;
    endtask
    task automatic axi_read(input logic [11:0] address,output logic [31:0] data,input logic [1:0] response=0);
        logic [31:0] saved;
        @(negedge clk);s_axi_araddr=address;s_axi_arvalid=1;
        do @(posedge clk);while(!s_axi_arready);
        @(negedge clk);s_axi_arvalid=0;
        wait(s_axi_rvalid);saved=s_axi_rdata;
        repeat(3) begin @(negedge clk);if(!s_axi_rvalid || s_axi_rdata!==saved || s_axi_rresp!==response) $fatal(1,"RRESP_HOLD");end
        data=saved;s_axi_rready=1;@(posedge clk);@(negedge clk);s_axi_rready=0;axi_checks=axi_checks+1;
    endtask
    task automatic beat(input logic [31:0] value,input bit last=0,input logic [3:0] keep=15);
        @(negedge clk);s_axis_tdata=value;s_axis_tlast=last;s_axis_tkeep=keep;s_axis_tvalid=1;
        do @(posedge clk);while(!s_axis_tready);
        @(negedge clk);s_axis_tvalid=0;
    endtask
    task automatic reset_core;
        checking=0;s_axis_tvalid=0;m_axis_tready=0;
        axi_write(12'h004,4);
        repeat(3) @(negedge clk);
        if(busy || prepared || result_valid || rsp_valid || fault || dut.rx_enabled || dut.tx_active || dut.rx_words!=0 || dut.tx_words!=0) $fatal(1,"RESET_NOT_CLEAN");
    endtask
    task automatic begin_load;
        checking=0;expected_tag=32'ha5000000+32'(job);
        axi_write(12'h00c,expected_tag,15,job%3);
        axi_write(12'h004,1,15,(job+1)%3);
    endtask
    task automatic transfer(input integer typ,input integer count);
        integer bus_words;
        bus_words=typ<2?count/4:count;
        ddr_tx[0]=32'h52323032;ddr_tx[1]=32'(typ);ddr_tx[2]=32'(count);
        for(integer i=0;i<bus_words;i=i+1) ddr_tx[i+3]=0;
        for(integer i=0;i<count;i=i+1) case(typ)
            0:ddr_tx[i/4+3][(i%4)*8+:8]=stimulus[i];
            1:ddr_tx[i/4+3][(i%4)*8+:8]=weights[i];
            2:ddr_tx[i+3]=biases[i];
            3:ddr_tx[i+3]=ns[i];
            4:ddr_tx[i+3]=rs[i];
        endcase
        for(integer i=0;i<bus_words+3;i=i+1) begin
            if(stall_enable && i%17==0) repeat(2) @(negedge clk);
            beat(ddr_tx[i],i==bus_words+2);
        end
        // MM2S TLAST acceptance can precede the final three native writes.
        wait(!dut.unpack_valid);repeat(2) @(negedge clk);
        if(dut.error_code!=0) $fatal(1,"TRANSFER_ERROR type=%0d error=%h",typ,dut.error_code);
        $display("MM2S_PASS job=%0d kind=%0d payload_words=%0d bus_words=%0d bytes=%0d",job,typ,count,bus_words,(bus_words+3)*4);
    endtask
    task automatic prepare;
        logic [31:0] status;
        begin_load();
        transfer(0,3072);transfer(1,268336);transfer(2,698);transfer(3,698);transfer(4,698);
        axi_read(12'h008,status);
        if(!status[2] || !status[0] || status[6] || !start_ready || (dut.rx_words!=273502 || dut.rx_bus_words!=69961)) $fatal(1,"PREPARE_INCOMPLETE status=%h",status);
        for(integer i=0;i<3072;i=i+1) if(dut.core.feature_mem.mem[i]!==stimulus[i]) $fatal(1,"INPUT_BOUNDARY index=%0d",i);
    endtask
    task automatic launch;
        events=0;expected_op=0;expected_addr=0;boundaries=1;macs=0;gaps=0;compute_stalls=0;trace_stalls=0;rsp_stalls=0;checking=1;
        axi_write(12'h004,2);
        if(!busy || prepared) $fatal(1,"START_FAILED");
    endtask
    task automatic receive_packet;
        for(integer i=0;i<16;i=i+1) begin
            wait(m_axis_tvalid);
            if(stall_enable) repeat(5) @(negedge clk);
            @(negedge clk);m_axis_tready=1;
            @(posedge clk);
            if(!m_axis_tvalid || m_axis_tkeep!=15 || m_axis_tlast!=(i==15)) $fatal(1,"S2MM_PACKET_FORMAT index=%0d",i);
            ddr_rx[i]=m_axis_tdata;
            @(negedge clk);m_axis_tready=0;
        end
        repeat(2) @(negedge clk);
    endtask
    task automatic finish_job;
        logic [31:0] status;
        receive_packet();
        if(ddr_rx[0]!=32'h52323052 || ddr_rx[1]!=expected_tag || ddr_rx[2]!=0 || ddr_rx[3]!=32'(case_id==0?3:8)) $fatal(1,"S2MM_HEADER_OR_TAG");
        for(integer i=0;i<10;i=i+1) begin
            if(ddr_rx[i+4]!==ecode[trace_offset[29]+i]) $fatal(1,"DDR_SCORE index=%0d",i);
            $display("SCORE job=%0d sample=%0d class=%0d value=%0d",job,case_id,i,$signed(ddr_rx[i+4]));
        end
        if({ddr_rx[15],ddr_rx[14]}<40551040) $fatal(1,"CYCLE_COUNT_MISSING");
        axi_read(12'h008,status);
        if(!status[5] || status[3] || status[6] || status[4] || dut.tx_words!=16 || !result_valid || prepared) $fatal(1,"DMA_COMPLETION_STATE");
        if(events!=274506 || boundaries!=61 || macs!=40551040 || gaps!=4096) $fatal(1,"JOB_COUNTS");
        if(stall_enable && (compute_stalls==0 || trace_stalls==0 || rsp_stalls==0 || axis_holds==0)) $fatal(1,"STALL_NOT_EXERCISED");
        checking=0;
        $display("JOB_PASS job=%0d sample=%0d boundaries=%0d elements=552084 events=%0d macs=%0d gaps=%0d prediction=%0d compute_stalls=%0d trace_stalls=%0d rsp_stalls=%0d",job,case_id,boundaries,events,macs,gaps,prediction,compute_stalls,trace_stalls,rsp_stalls);
        $display("S2MM_PASS job=%0d words=16 bytes=64 tag=%h elapsed=%0d",job,ddr_rx[1],{ddr_rx[15],ddr_rx[14]});
        job=job+1;
    endtask
    task automatic cancel_reset(input integer location);
        $display("RESET_CANCEL location=%0d op=%0d events=%0d rx_words=%0d tx_words=%0d",location,trace_op,events,dut.rx_words,dut.tx_words);
        reset_cancels=reset_cancels+1;reset_core();
    endtask
    task automatic malformed(input integer which);
        begin_load();
        case(which)
            0:begin beat(32'hdeadbeef);beat(0,1);end
            1:begin beat(32'h52323032);beat(1);beat(0,1);end
            2:begin beat(32'h52323032);beat(0);beat(3073);beat(0,1);end
            3:beat(32'h52323032,1);
            4:beat(32'h52323032,1,7);
            5:begin beat(32'h52323032);beat(0);beat(3072);beat(0,1);end
            6:begin beat(32'h52323032);beat(0);beat(3072);for(integer i=0;i<768;i=i+1) beat(0);beat(0,1);end
            7:begin transfer(0,3072);beat(32'h52323032);beat(1);beat(268336);beat(32'h00000080);beat(0,1);end
        endcase
        repeat(3) @(negedge clk);
        if(dut.error_code==0 || prepared) $fatal(1,"BAD_PACKET_ACCEPTED case=%0d",which);
        axi_write(12'h004,2,15,0,2);
        packet_checks=packet_checks+1;
        reset_core();
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

        repeat(4) @(negedge clk);aresetn=1;repeat(3) @(negedge clk);
        reset_core();load_case(0);
        if(mode==3) begin : protocols
            logic [31:0] value;
            axi_read(0,value);if(value!=32'h52323032) $fatal(1,"ID_REGISTER");
            axi_write(12'h00c,32'h11223344,15,1);axi_write(12'h00c,32'haabbccdd,5,2);
            axi_read(12'h00c,value);if(value!=32'h11bb33dd) $fatal(1,"BYTE_STROBES");
            axi_write(0,0,15,0,2);axi_write(12'h005,1,15,0,2);axi_write(4,2,15,0,2);
            axi_write(4,1,0);if(dut.rx_enabled) $fatal(1,"ZERO_STROBE_SIDE_EFFECT");
            axi_read(12'hffc,value,2);axi_read(12'h009,value,2);
            // Reset cancels an AW-only transaction and a stalled read response.
            @(negedge clk);s_axi_awvalid=1;s_axi_awaddr=12'h00c;
            @(posedge clk);@(negedge clk);s_axi_awvalid=0;aresetn=0;
            repeat(3) @(negedge clk);aresetn=1;repeat(3) @(negedge clk);
            if(s_axi_bvalid || s_axi_rvalid || !s_axi_awready || !s_axi_wready) $fatal(1,"AXI_RESET_PENDING");
            for(integer i=0;i<8;i=i+1) malformed(i);
            $display("PROTOCOL_PASS malformed=8 axi_checks=%0d aw_w_orders=3 byte_strobes=1 response_hold=1 reset_pending=1",axi_checks);
            $finish;
        end
        if(mode==4) begin
            prepare();
            for(integer i=0;i<268336;i=i+1) begin
                if(i<262144) begin if(dut.core.weights.low_mem.mem[i]!==weights[i]) $fatal(1,"PACKED_WEIGHT index=%0d",i);end
                else if(dut.core.weights.high_mem.mem[i-262144]!==weights[i]) $fatal(1,"PACKED_WEIGHT_TAIL index=%0d",i);
            end
            for(integer i=0;i<698;i=i+1)
                if(dut.core.biases.mem[i]!==biases[i] || dut.core.multipliers.mem[i]!==ns[i] || dut.core.shifts.mem[i]!==rs[i][4:0]) $fatal(1,"PACKED_COEFFICIENT index=%0d",i);
            $display("PACKED_LOADER_PASS input_bytes=3072 weight_bytes=268336 coefficients=2094 bus_words=69961 bytes=279844 bram_boundary=262144");$finish;
        end
        if(mode==11) begin
            for(integer i=0;i<3072;i=i+1) stimulus[i]=127;
            for(integer i=0;i<27;i=i+1) weights[i]=127;
            biases[0]=32'h7fffffff;prepare();launch();receive_packet();checking=0;
            if(ddr_rx[2]!=32'h80000001 || dut.error_code!=32'h80000001) $fatal(1,"FAULT_NOT_RETURNED_TO_DDR");
            reset_core();$display("OVERFLOW_PASS code=1 reset_clean=1 error_packet=1");$finish;
        end
        if(mode==2) begin
            begin_load();beat(32'h52323032);cancel_reset(0);
            begin_load();transfer(0,3072);beat(32'h52323032);beat(1);beat(268336);
            for(integer i=0;i<64;i=i+1) beat({weights[4*i+3],weights[4*i+2],weights[4*i+1],weights[4*i]});cancel_reset(1);
            prepare();launch();wait(dut.core.coeff_re);@(posedge clk);#1;cancel_reset(2);
            prepare();launch();wait(dut.core.multiply.busy);repeat(5) @(negedge clk);cancel_reset(3);
            prepare();launch();wait(dut.core.rounding.busy);@(negedge clk);cancel_reset(4);
            prepare();launch();wait(events>=37);cancel_reset(5);
            prepare();launch();wait(trace_op==11 && trace_addr>=19);cancel_reset(6);
            prepare();launch();wait(m_axis_tvalid);
            for(integer i=0;i<5;i=i+1) begin @(negedge clk);m_axis_tready=1;@(posedge clk);@(negedge clk);m_axis_tready=0;end
            cancel_reset(7);
            load_case(1);prepare();launch();finish_job();
            $display("RESET_PASS cancelled=%0d recovered_sample=1",reset_cancels);
        end else if(mode==1) begin
            stall_enable=1;prepare();launch();
            axi_write(4,1,15,0,2);axi_write(4,2,15,0,2);axi_write(12'h00c,0,15,0,2);
            axi_write(12'h040,1);repeat(100) @(negedge clk);axi_write(12'h040,0);
            axi_write(12'h040,2);wait(trace_valid);repeat(10) @(negedge clk);axi_write(12'h040,0);
            finish_job();axi_write(4,2,15,0,2);$display("BUSY_STALE_GUARD_PASS");
        end else begin
            prepare();launch();finish_job();
            if(fd!=0) begin $fclose(fd);fd=0;end
            if(mode==0) begin load_case(1);prepare();launch();finish_job();load_case(0);prepare();launch();finish_job();end
        end
        if(mode>=6 && mode<=9) $fatal(1,"WRONG_GOLDEN_ACCEPTED");
        $display("CASE_PASS mode=%0d jobs=%0d",mode,job);$finish;
    end
endmodule
