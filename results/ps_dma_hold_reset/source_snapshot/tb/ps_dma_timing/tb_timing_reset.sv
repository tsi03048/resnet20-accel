`timescale 1ns/1ps
// PS AXI-Lite master and DDR-backed DMA stream BFMs; not a CPU/DDR PHY model.
module tb_timing_reset;
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
    integer endpoint_checks=0;
    // Check the accepted header's endpoint registers throughout payload stalls.
    always @(posedge clk) if(aresetn && !dut.soft_reset && dut.rx_state==3) begin
        endpoint_checks=endpoint_checks+1;
        case(dut.stage)
            0:if(dut.last_scalar!==19'd3071 || dut.last_ingress!==19'd3068 || !dut.packet_packed) $fatal(1,"INPUT_ENDPOINT");
            1:if(dut.last_scalar!==19'd268335 || dut.last_ingress!==19'd268332 || !dut.packet_packed) $fatal(1,"WEIGHT_ENDPOINT");
            default:if(dut.last_scalar!==19'd697 || dut.last_ingress!==19'd697 || dut.packet_packed) $fatal(1,"COEFFICIENT_ENDPOINT");
        endcase
    end
    integer axi_checks=0,cycles=0,input_stalls=0,reset_buffer_collisions=0;
    always @(posedge clk) begin
        cycles=cycles+1;if(cycles>500000) $fatal(1,"PACKED_RESET_TIMEOUT rx_state=%0d unpack=%0d/%0d scalar=%0d ready=%0d axi=%0d/%0d/%0d reset=%0d",dut.rx_state,dut.unpack_valid,dut.unpack_lane,dut.core.input_count,dut.cfg_ready,s_axi_awvalid,s_axi_wvalid,s_axi_bvalid,aresetn);
        if(s_axis_tvalid && !s_axis_tready) input_stalls=input_stalls+1;
        if(aresetn && dut.soft_reset && dut.unpack_valid) begin
            if(dut.cfg_fire || dut.core.input_count!=0) $fatal(1,"RESET_COLLISION_ACCEPTED_SCALAR");
            reset_buffer_collisions=reset_buffer_collisions+1;
        end
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

    task automatic header;
        axi_write(12'h004,1);
        beat(32'h52323032);beat(0);beat(3072);
    endtask
    task automatic assert_clean;
        if(dut.unpack_valid || dut.rx_enabled || dut.rx_words!=0 || dut.rx_bus_words!=0 || dut.core.input_count!=0 || prepared || busy || result_valid) $fatal(1,"PACKED_RESET_STALE");
    endtask
    initial begin
        repeat(3) @(negedge clk);aresetn=1;repeat(3) @(negedge clk);
        for(integer lane=0;lane<4;lane=lane+1) begin
            $display("PACKED_RESET_TRY lane=%0d",lane);header();beat(32'h7f0180ff);
            $display("PACKED_RESET_BUFFER lane=%0d valid=%0d active_lane=%0d",lane,dut.unpack_valid,dut.unpack_lane);
            repeat(lane) @(negedge clk);
            if(!dut.unpack_valid || dut.unpack_lane!=2'(lane) || dut.core.input_count!=13'(lane)) $fatal(1,"RESET_LANE_NOT_REACHED lane=%0d",lane);
            aresetn=0;repeat(3) @(negedge clk);aresetn=1;repeat(3) @(negedge clk);assert_clean();
            $display("PACKED_LANE_RESET_PASS lane=%0d accepted_scalars=%0d",lane,lane);
        end
        // AW/W arrive one cycle before the packed payload. The RESET pulse and
        // payload-buffer capture coincide, then clear invalidates the buffer.
        header();
        fork
            axi_write(12'h004,4);
            begin @(negedge clk);beat(32'h7f0180ff);end
        join
        repeat(3) @(negedge clk);assert_clean();
        if(reset_buffer_collisions!=1) $fatal(1,"SOFT_RESET_BUFFER_COLLISION_NOT_EXERCISED");
        $display("PACKED_SOFT_RESET_PASS payload_capture_collision=1 native_scalars=0");
        header();
        for(integer i=0;i<768;i=i+1) beat(32'h7f0180ff,i==767);
        wait(!dut.unpack_valid);repeat(3) @(negedge clk);
        if(dut.core.input_count!=3072 || dut.rx_words!=3072 || dut.rx_bus_words!=771) $fatal(1,"PACKED_RESET_RECOVERY_COUNT");
        for(integer i=0;i<3072;i=i+1) begin
            logic [7:0] want;
            case(i%4) 0:want=8'hff;1:want=8'h80;2:want=8'h01;3:want=8'h7f;endcase
            if(dut.core.feature_mem.mem[i]!==want) $fatal(1,"PACKED_RESET_RECOVERY_BYTE index=%0d",i);
        end
        if(input_stalls==0) $fatal(1,"PACKED_BACKPRESSURE_NOT_EXERCISED");
        // Numeric error must be visible before any malformed TLAST is sent.
        // Drain the remaining correctly sized packet to permit MM2S completion.
        beat(32'h52323032);beat(1);beat(268336);beat(32'h00000080);
        repeat(8) @(negedge clk);
        if(dut.error_code!==32'h10 || dut.core.weight_count!=0) $fatal(1,"PACKED_BAD_WEIGHT_NOT_REJECTED");
        for(integer i=1;i<67084;i=i+1) beat(0,i==67083);
        if(dut.rx_enabled || dut.rx_bus_words!=67858 || prepared || dut.error_code!==32'h10) $fatal(1,"PACKED_BAD_WEIGHT_DRAIN_FAILED");
        $display("PACKED_BAD_WEIGHT_PASS code=16 complete_packet_drain=1 packet_words=67087");
        axi_write(12'h004,4);repeat(3) @(negedge clk);assert_clean();
        $display("PACKED_RESET_PASS hard_reset_lanes=4 soft_reset_collision=1 recovered_input_bytes=3072 wire_words=771 source_stalls=%0d synthetic_pattern=1",input_stalls);
        if(endpoint_checks==0) $fatal(1,"NO_ENDPOINT_CHECKS");$display("TIMING_ENDPOINT_PASS payload_cycles=%0d",endpoint_checks);$finish;
    end
endmodule
