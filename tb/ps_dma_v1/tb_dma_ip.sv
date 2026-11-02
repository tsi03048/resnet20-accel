`timescale 1ns/1ps
// Real AMD AXI DMA 7.1; behavioral AXI DDR memory and AXI-Lite PS master.
module tb_dma_ip;
    logic clk=0;always #5 clk=~clk;
    wire  s_axi_lite_aclk;
    wire  m_axi_mm2s_aclk;
    wire  m_axi_s2mm_aclk;
    logic  axi_resetn=0;
    logic  s_axi_lite_awvalid=0;
    wire  s_axi_lite_awready;
    logic [9:0] s_axi_lite_awaddr=0;
    logic  s_axi_lite_wvalid=0;
    wire  s_axi_lite_wready;
    logic [31:0] s_axi_lite_wdata=0;
    wire [1:0] s_axi_lite_bresp;
    wire  s_axi_lite_bvalid;
    logic  s_axi_lite_bready=0;
    logic  s_axi_lite_arvalid=0;
    wire  s_axi_lite_arready;
    logic [9:0] s_axi_lite_araddr=0;
    wire  s_axi_lite_rvalid;
    logic  s_axi_lite_rready=0;
    wire [31:0] s_axi_lite_rdata;
    wire [1:0] s_axi_lite_rresp;
    wire [31:0] m_axi_mm2s_araddr;
    wire [7:0] m_axi_mm2s_arlen;
    wire [2:0] m_axi_mm2s_arsize;
    wire [1:0] m_axi_mm2s_arburst;
    wire [2:0] m_axi_mm2s_arprot;
    wire [3:0] m_axi_mm2s_arcache;
    wire  m_axi_mm2s_arvalid;
    wire  m_axi_mm2s_arready;
    logic [63:0] m_axi_mm2s_rdata=0;
    logic [1:0] m_axi_mm2s_rresp=0;
    logic  m_axi_mm2s_rlast=0;
    logic  m_axi_mm2s_rvalid=0;
    wire  m_axi_mm2s_rready;
    wire  mm2s_prmry_reset_out_n;
    wire [31:0] m_axis_mm2s_tdata;
    wire [3:0] m_axis_mm2s_tkeep;
    wire  m_axis_mm2s_tvalid;
    wire  m_axis_mm2s_tready;
    wire  m_axis_mm2s_tlast;
    wire [31:0] m_axi_s2mm_awaddr;
    wire [7:0] m_axi_s2mm_awlen;
    wire [2:0] m_axi_s2mm_awsize;
    wire [1:0] m_axi_s2mm_awburst;
    wire [2:0] m_axi_s2mm_awprot;
    wire [3:0] m_axi_s2mm_awcache;
    wire  m_axi_s2mm_awvalid;
    wire  m_axi_s2mm_awready;
    wire [63:0] m_axi_s2mm_wdata;
    wire [7:0] m_axi_s2mm_wstrb;
    wire  m_axi_s2mm_wlast;
    wire  m_axi_s2mm_wvalid;
    wire  m_axi_s2mm_wready;
    logic [1:0] m_axi_s2mm_bresp=0;
    logic  m_axi_s2mm_bvalid=0;
    wire  m_axi_s2mm_bready;
    wire  s2mm_prmry_reset_out_n;
    wire [31:0] s_axis_s2mm_tdata;
    wire [3:0] s_axis_s2mm_tkeep;
    wire  s_axis_s2mm_tvalid;
    wire  s_axis_s2mm_tready;
    wire  s_axis_s2mm_tlast;
    wire  mm2s_introut;
    wire  s2mm_introut;
    wire [31:0] axi_dma_tstvec;
    dma_under_test dut(
        .s_axi_lite_aclk(s_axi_lite_aclk),
        .m_axi_mm2s_aclk(m_axi_mm2s_aclk),
        .m_axi_s2mm_aclk(m_axi_s2mm_aclk),
        .axi_resetn(axi_resetn),
        .s_axi_lite_awvalid(s_axi_lite_awvalid),
        .s_axi_lite_awready(s_axi_lite_awready),
        .s_axi_lite_awaddr(s_axi_lite_awaddr),
        .s_axi_lite_wvalid(s_axi_lite_wvalid),
        .s_axi_lite_wready(s_axi_lite_wready),
        .s_axi_lite_wdata(s_axi_lite_wdata),
        .s_axi_lite_bresp(s_axi_lite_bresp),
        .s_axi_lite_bvalid(s_axi_lite_bvalid),
        .s_axi_lite_bready(s_axi_lite_bready),
        .s_axi_lite_arvalid(s_axi_lite_arvalid),
        .s_axi_lite_arready(s_axi_lite_arready),
        .s_axi_lite_araddr(s_axi_lite_araddr),
        .s_axi_lite_rvalid(s_axi_lite_rvalid),
        .s_axi_lite_rready(s_axi_lite_rready),
        .s_axi_lite_rdata(s_axi_lite_rdata),
        .s_axi_lite_rresp(s_axi_lite_rresp),
        .m_axi_mm2s_araddr(m_axi_mm2s_araddr),
        .m_axi_mm2s_arlen(m_axi_mm2s_arlen),
        .m_axi_mm2s_arsize(m_axi_mm2s_arsize),
        .m_axi_mm2s_arburst(m_axi_mm2s_arburst),
        .m_axi_mm2s_arprot(m_axi_mm2s_arprot),
        .m_axi_mm2s_arcache(m_axi_mm2s_arcache),
        .m_axi_mm2s_arvalid(m_axi_mm2s_arvalid),
        .m_axi_mm2s_arready(m_axi_mm2s_arready),
        .m_axi_mm2s_rdata(m_axi_mm2s_rdata),
        .m_axi_mm2s_rresp(m_axi_mm2s_rresp),
        .m_axi_mm2s_rlast(m_axi_mm2s_rlast),
        .m_axi_mm2s_rvalid(m_axi_mm2s_rvalid),
        .m_axi_mm2s_rready(m_axi_mm2s_rready),
        .mm2s_prmry_reset_out_n(mm2s_prmry_reset_out_n),
        .m_axis_mm2s_tdata(m_axis_mm2s_tdata),
        .m_axis_mm2s_tkeep(m_axis_mm2s_tkeep),
        .m_axis_mm2s_tvalid(m_axis_mm2s_tvalid),
        .m_axis_mm2s_tready(m_axis_mm2s_tready),
        .m_axis_mm2s_tlast(m_axis_mm2s_tlast),
        .m_axi_s2mm_awaddr(m_axi_s2mm_awaddr),
        .m_axi_s2mm_awlen(m_axi_s2mm_awlen),
        .m_axi_s2mm_awsize(m_axi_s2mm_awsize),
        .m_axi_s2mm_awburst(m_axi_s2mm_awburst),
        .m_axi_s2mm_awprot(m_axi_s2mm_awprot),
        .m_axi_s2mm_awcache(m_axi_s2mm_awcache),
        .m_axi_s2mm_awvalid(m_axi_s2mm_awvalid),
        .m_axi_s2mm_awready(m_axi_s2mm_awready),
        .m_axi_s2mm_wdata(m_axi_s2mm_wdata),
        .m_axi_s2mm_wstrb(m_axi_s2mm_wstrb),
        .m_axi_s2mm_wlast(m_axi_s2mm_wlast),
        .m_axi_s2mm_wvalid(m_axi_s2mm_wvalid),
        .m_axi_s2mm_wready(m_axi_s2mm_wready),
        .m_axi_s2mm_bresp(m_axi_s2mm_bresp),
        .m_axi_s2mm_bvalid(m_axi_s2mm_bvalid),
        .m_axi_s2mm_bready(m_axi_s2mm_bready),
        .s2mm_prmry_reset_out_n(s2mm_prmry_reset_out_n),
        .s_axis_s2mm_tdata(s_axis_s2mm_tdata),
        .s_axis_s2mm_tkeep(s_axis_s2mm_tkeep),
        .s_axis_s2mm_tvalid(s_axis_s2mm_tvalid),
        .s_axis_s2mm_tready(s_axis_s2mm_tready),
        .s_axis_s2mm_tlast(s_axis_s2mm_tlast),
        .mm2s_introut(mm2s_introut),
        .s2mm_introut(s2mm_introut),
        .axi_dma_tstvec(axi_dma_tstvec)
    );

    assign s_axi_lite_aclk=clk;assign m_axi_mm2s_aclk=clk;assign m_axi_s2mm_aclk=clk;
    integer cycle=0,read_bursts=0,write_bursts=0,stream_words=0,packets=0;
    byte memory[0:4194303];
    logic read_active=0,write_active=0;
    logic [31:0] read_address,write_address;
    integer read_left,write_left;
    wire enable_stream=cycle%11!=0;
    assign m_axis_mm2s_tready=s_axis_s2mm_tready && enable_stream;
    assign s_axis_s2mm_tdata=m_axis_mm2s_tdata;
    assign s_axis_s2mm_tkeep=m_axis_mm2s_tkeep;
    assign s_axis_s2mm_tlast=m_axis_mm2s_tlast;
    assign s_axis_s2mm_tvalid=m_axis_mm2s_tvalid && enable_stream;
    assign m_axi_mm2s_arready=!read_active && !m_axi_mm2s_rvalid && cycle%7!=0;
    assign m_axi_s2mm_awready=!write_active && !m_axi_s2mm_bvalid && cycle%7!=0;
    assign m_axi_s2mm_wready=write_active && cycle%5!=0;
    always @(posedge clk) begin
        cycle=cycle+1;
        if(cycle>5000000) $fatal(1,"DMA_IP_TIMEOUT");
        if(m_axis_mm2s_tvalid && m_axis_mm2s_tready) begin stream_words=stream_words+1;if(m_axis_mm2s_tlast) packets=packets+1;end
        if(m_axi_mm2s_arvalid && m_axi_mm2s_arready) begin
            if(m_axi_mm2s_arburst!=1 || m_axi_mm2s_arsize!=3 || m_axi_mm2s_arlen>15 || (m_axi_mm2s_araddr[11:0]+(m_axi_mm2s_arlen+1)*8)>4096) $fatal(1,"READ_BURST");
            read_address<=m_axi_mm2s_araddr;read_left<=m_axi_mm2s_arlen+1;read_active<=1;read_bursts=read_bursts+1;
        end
        if(m_axi_mm2s_rvalid && m_axi_mm2s_rready) begin
            m_axi_mm2s_rvalid<=0;
            if(read_left==1) read_active<=0;
            else begin read_left<=read_left-1;read_address<=read_address+8;end
        end else if(read_active && !m_axi_mm2s_rvalid && cycle%5!=0) begin
            for(integer i=0;i<8;i=i+1) m_axi_mm2s_rdata[i*8+:8]<=memory[read_address-32'h02000000+i];
            m_axi_mm2s_rresp<=0;m_axi_mm2s_rlast<=read_left==1;m_axi_mm2s_rvalid<=1;
        end
        if(m_axi_s2mm_awvalid && m_axi_s2mm_awready) begin
            if(m_axi_s2mm_awburst!=1 || m_axi_s2mm_awsize!=3 || m_axi_s2mm_awlen>15 || (m_axi_s2mm_awaddr[11:0]+(m_axi_s2mm_awlen+1)*8)>4096) $fatal(1,"WRITE_BURST");
            write_address<=m_axi_s2mm_awaddr;write_left<=m_axi_s2mm_awlen+1;write_active<=1;write_bursts=write_bursts+1;
        end
        if(m_axi_s2mm_bvalid && m_axi_s2mm_bready) m_axi_s2mm_bvalid<=0;
        if(m_axi_s2mm_wvalid && m_axi_s2mm_wready) begin
            if(m_axi_s2mm_wlast!=(write_left==1)) $fatal(1,"WRITE_LAST");
            for(integer i=0;i<8;i=i+1) if(m_axi_s2mm_wstrb[i]) memory[write_address-32'h02000000+i]<=m_axi_s2mm_wdata[i*8+:8];
            if(write_left==1) begin write_active<=0;m_axi_s2mm_bvalid<=1;m_axi_s2mm_bresp<=0;end
            else begin write_left<=write_left-1;write_address<=write_address+8;end
        end
    end
    task automatic wr(input logic [9:0] address,input logic [31:0] data);
        fork
            begin @(negedge clk);s_axi_lite_awaddr=address;s_axi_lite_awvalid=1;do @(posedge clk);while(!s_axi_lite_awready);@(negedge clk);s_axi_lite_awvalid=0;end
            begin @(negedge clk);s_axi_lite_wdata=data;s_axi_lite_wvalid=1;do @(posedge clk);while(!s_axi_lite_wready);@(negedge clk);s_axi_lite_wvalid=0;end
        join
        wait(s_axi_lite_bvalid);if(s_axi_lite_bresp!=0) $fatal(1,"DMA_BRESP");
        @(negedge clk);s_axi_lite_bready=1;@(posedge clk);@(negedge clk);s_axi_lite_bready=0;
    endtask
    task automatic rd(input logic [9:0] address,output logic [31:0] value);
        @(negedge clk);s_axi_lite_araddr=address;s_axi_lite_arvalid=1;
        do @(posedge clk);while(!s_axi_lite_arready);
        @(negedge clk);s_axi_lite_arvalid=0;wait(s_axi_lite_rvalid);
        if(s_axi_lite_rresp!=0) $fatal(1,"DMA_RRESP");value=s_axi_lite_rdata;
        @(negedge clk);s_axi_lite_rready=1;@(posedge clk);@(negedge clk);s_axi_lite_rready=0;
    endtask
    task automatic reset_dma;
        logic [31:0] value;
        wr(0,4);
        do rd(0,value);while(value[2]);
        wr(4,32'h7000);wr(10'h034,32'h7000);wr(0,1);wr(10'h030,1);
    endtask
    task automatic arm(input integer bytes);
        wr(10'h034,32'h7000);wr(10'h048,32'h02200000);wr(10'h058,32'(bytes));
        wr(4,32'h7000);wr(10'h018,32'h02010000);wr(10'h028,32'(bytes));
    endtask
    task automatic finish_transfer(input integer bytes);
        logic [31:0] value;
        do begin rd(10'h034,value);if(value&32'h770) $fatal(1,"S2MM_DMA_ERROR value=%h",value);end while(!value[12]);
        do begin rd(4,value);if(value&32'h770) $fatal(1,"MM2S_DMA_ERROR value=%h",value);end while(!value[12]);
        for(integer i=0;i<bytes;i=i+1) if(memory[32'h200000+i]!==memory[32'h10000+i]) $fatal(1,"DDR_LOOPBACK_BYTE index=%0d",i);
        $display("DMA_IP_TRANSFER_PASS bytes=%0d read_bursts=%0d write_bursts=%0d stream_words=%0d",bytes,read_bursts,write_bursts,stream_words);
    endtask
    initial begin
        for(integer i=0;i<1073356;i=i+1) memory[32'h10000+i]=8'(i*37+11);
        repeat(16) @(negedge clk);axi_resetn=1;repeat(32) @(negedge clk);
        reset_dma();arm(1073356);finish_transfer(1073356);
        arm(12300);wait(stream_words>268339+100);reset_dma();
        for(integer i=0;i<64;i=i+1) memory[32'h200000+i]=8'ha5;
        arm(64);finish_transfer(64);
        $display("DMA_IP_PASS real_axi_dma=7.1 max_packet_bytes=1073356 reset_during_transfer=1 recovered_bytes=64 memory_bfm=1 stream_stalls=1");
        $finish;
    end
endmodule
