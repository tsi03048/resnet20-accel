`timescale 1ns/1ps
// Single FCLK domain. AXI-Lite control, MM2S packet loader, S2MM score packet.
// Golden data is never an input to this hardware.
module resnet20_axi_packed(
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI:S_AXIS:M_AXIS, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 aclk CLK" *) input wire aclk,
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 aresetn RST" *) input wire aresetn,
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, FREQ_HZ 100000000" *)
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *) input wire [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *) input wire [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *) input wire s_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *) output wire s_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WDATA" *) input wire [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *) input wire [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WVALID" *) input wire s_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI WREADY" *) output wire s_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BRESP" *) output logic [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BVALID" *) output logic s_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI BREADY" *) input wire s_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *) input wire [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *) input wire [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *) input wire s_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *) output wire s_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RDATA" *) output logic [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RRESP" *) output logic [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RVALID" *) output logic s_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 S_AXI RREADY" *) input wire s_axi_rready,
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME S_AXIS, TDATA_NUM_BYTES 4, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 100000000" *)
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TDATA" *) input wire [31:0] s_axis_tdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TKEEP" *) input wire [3:0] s_axis_tkeep,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TLAST" *) input wire s_axis_tlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TVALID" *) input wire s_axis_tvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TREADY" *) output wire s_axis_tready,
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME M_AXIS, TDATA_NUM_BYTES 4, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 100000000" *)
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TDATA" *) output logic [31:0] m_axis_tdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TKEEP" *) output wire [3:0] m_axis_tkeep,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TLAST" *) output wire m_axis_tlast,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output wire m_axis_tvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input wire m_axis_tready
);
    localparam [31:0] LOAD_MAGIC=32'h52323032,RESULT_MAGIC=32'h52323052;
    logic aw_have,w_have;
    logic [11:0] aw_saved;
    logic [31:0] w_saved,tag;
    logic [3:0] strobe_saved;
    logic begin_pulse,start_pulse,soft_reset;
    logic [1:0] pause;
    logic rx_enabled,load_complete,done_sticky,tx_active,tx_sent;
    logic [2:0] stage,rx_state;
    logic [18:0] rx_index,rx_limit,rx_ingress;
    logic [31:0] unpack_data,rx_bus_words;
    logic [1:0] unpack_lane;
    logic unpack_valid;
    wire [2:0] ingress_units=stage<2?3'd4:3'd1;
    wire unpack_last=stage>=2 || unpack_lane==3;
    wire [31:0] cfg_data=stage<2?{24'd0,unpack_data[unpack_lane*8+:8]}:unpack_data;
    logic [31:0] error_code,rx_words,tx_words,tx_status,tx_tag;
    logic [3:0] tx_index,tx_prediction,score_read_addr;
    logic [63:0] elapsed,frozen_elapsed;
    wire core_rst=!aresetn || soft_reset;
    wire cfg_ready,prepared,start_ready,start_rejected,busy,done,fault,load_error;
    wire [2:0] fault_code;
    wire [12:0] input_count;
    wire [18:0] weight_count;
    wire [9:0] bias_count,n_count,shift_count;
    wire step_valid,mac_fire,gap_fire,trace_valid,trace_skip_from_x,rsp_valid,result_valid;
    wire [4:0] trace_op;
    wire [13:0] trace_addr,trace_skip_addr;
    wire signed [31:0] trace_acc,trace_code,score_read_data;
    wire signed [7:0] trace_skip;
    wire signed [63:0] trace_wide;
    wire [3:0] prediction;
    wire compute_ready=!pause[0],trace_ready=!pause[1];
    wire [18:0] expected_count=stage==0?19'd3072:(stage==1?19'd268336:19'd698);
    wire payload_format_ok=s_axis_tkeep==4'hf && s_axis_tlast==(rx_ingress==rx_limit-{16'd0,ingress_units});
    wire cfg_valid=rx_enabled && rx_state==3 && unpack_valid;
    wire cfg_fire=cfg_valid && cfg_ready;
    wire rsp_ready=tx_active && m_axis_tready && tx_index==15 && tx_status==0;
    assign s_axis_tready=aresetn && !soft_reset && !begin_pulse && rx_enabled && !busy && !tx_active && (rx_state!=3 || (rx_ingress<rx_limit && (!unpack_valid || (cfg_fire && unpack_last))));
    assign m_axis_tvalid=aresetn && !soft_reset && tx_active;
    assign m_axis_tkeep=4'hf;
    assign m_axis_tlast=tx_index==15;
    assign s_axi_awready=!aw_have && !s_axi_bvalid;
    assign s_axi_wready=!w_have && !s_axi_bvalid;
    assign s_axi_arready=!s_axi_rvalid;
    always_comb begin
        score_read_addr=tx_index>=4 && tx_index<14?tx_index-4'd4:4'd0;
        case(tx_index)
            0:m_axis_tdata=RESULT_MAGIC;
            1:m_axis_tdata=tx_tag;
            2:m_axis_tdata=tx_status;
            3:m_axis_tdata={28'd0,tx_prediction};
            14:m_axis_tdata=frozen_elapsed[31:0];
            15:m_axis_tdata=frozen_elapsed[63:32];
            default:m_axis_tdata=tx_status==0?score_read_data:32'd0;
        endcase
    end
    full_model core(.clk(aclk),.rst(core_rst),.load_begin(begin_pulse),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),
        .cfg_kind(stage),.cfg_addr(rx_index),.cfg_data(cfg_data),.load_error(load_error),.prepared(prepared),
        .input_count(input_count),.weight_count(weight_count),.bias_count(bias_count),.n_count(n_count),.shift_count(shift_count),
        .start(start_pulse),.start_ready(start_ready),.start_rejected(start_rejected),.busy(busy),.done(done),.fault(fault),.fault_code(fault_code),
        .compute_ready(compute_ready),.step_valid(step_valid),.mac_fire(mac_fire),.gap_fire(gap_fire),.trace_valid(trace_valid),.trace_ready(trace_ready),
        .trace_op(trace_op),.trace_addr(trace_addr),.trace_acc(trace_acc),.trace_code(trace_code),.trace_skip(trace_skip),.trace_wide(trace_wide),
        .trace_skip_from_x(trace_skip_from_x),.trace_skip_addr(trace_skip_addr),.rsp_valid(rsp_valid),.result_valid(result_valid),.rsp_ready(rsp_ready),
        .prediction(prediction),.score_read_addr(score_read_addr),.score_read_data(score_read_data));

    // AW and W are independently captured. Responses remain stable until READY.
    always_ff @(posedge aclk) begin
        if(!aresetn) begin
            aw_have<=0;w_have<=0;aw_saved<=0;w_saved<=0;strobe_saved<=0;
            s_axi_bvalid<=0;s_axi_bresp<=0;s_axi_rvalid<=0;s_axi_rresp<=0;s_axi_rdata<=0;
            begin_pulse<=0;start_pulse<=0;soft_reset<=0;tag<=0;pause<=0;
        end else begin
            begin_pulse<=0;start_pulse<=0;soft_reset<=0;
            if(s_axi_awvalid && s_axi_awready) begin aw_saved<=s_axi_awaddr;aw_have<=1;end
            if(s_axi_wvalid && s_axi_wready) begin w_saved<=s_axi_wdata;strobe_saved<=s_axi_wstrb;w_have<=1;end
            if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if(aw_have && w_have && !s_axi_bvalid) begin
                aw_have<=0;w_have<=0;s_axi_bvalid<=1;s_axi_bresp<=0;
                case(aw_saved)
                    12'h04:begin
                        if(strobe_saved==0) begin end
                        else if(!strobe_saved[0] || w_saved[31:3]!=0) s_axi_bresp<=2;
                        else case(w_saved[2:0])
                            1:if(!busy && !tx_active && !rx_enabled) begin_pulse<=1;else s_axi_bresp<=2;
                            2:if(start_ready && load_complete && error_code==0 && !tx_active) start_pulse<=1;else s_axi_bresp<=2;
                            4:begin soft_reset<=1;pause<=0;end
                            default:s_axi_bresp<=2;
                        endcase
                    end
                    12'h0c:if(!busy && !rx_enabled && !tx_active) begin
                        for(integer i=0;i<4;i=i+1) if(strobe_saved[i]) tag[i*8+:8]<=w_saved[i*8+:8];
                    end else s_axi_bresp<=2;
                    12'h40:if(strobe_saved[0]) pause<=w_saved[1:0];
                    default:s_axi_bresp<=2;
                endcase
            end
            if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if(s_axi_arvalid && s_axi_arready) begin
                s_axi_rvalid<=1;s_axi_rresp<=0;
                case(s_axi_araddr)
                    12'h00:s_axi_rdata<=LOAD_MAGIC;
                    12'h08:s_axi_rdata<={24'd0,result_valid,error_code!=0,done_sticky,tx_active,busy,prepared,rx_enabled,load_complete};
                    12'h0c:s_axi_rdata<=tag;
                    12'h10:s_axi_rdata<=error_code;
                    12'h14:s_axi_rdata<=rx_words;
                    12'h18:s_axi_rdata<=tx_words;
                    12'h1c:s_axi_rdata<=elapsed[31:0];
                    12'h20:s_axi_rdata<=elapsed[63:32];
                    12'h24:s_axi_rdata<={26'd0,rx_state,stage};
                    12'h28:s_axi_rdata<={19'd0,input_count};
                    12'h2c:s_axi_rdata<={13'd0,weight_count};
                    12'h30:s_axi_rdata<={22'd0,bias_count};
                    12'h34:s_axi_rdata<={22'd0,n_count};
                    12'h38:s_axi_rdata<={22'd0,shift_count};
                    12'h3c:s_axi_rdata<={28'd0,prediction};
                    12'h40:s_axi_rdata<={30'd0,pause};
                    12'h44:s_axi_rdata<=rx_bus_words;
                    12'h48:s_axi_rdata<={29'd0,unpack_valid,unpack_lane};
                    default:begin s_axi_rdata<=0;s_axi_rresp<=2;end
                endcase
            end
        end
    end
    always_ff @(posedge aclk) begin
        if(core_rst || begin_pulse) begin
            rx_enabled<=!core_rst;load_complete<=0;rx_state<=0;stage<=0;rx_index<=0;rx_limit<=0;
            rx_ingress<=0;unpack_data<=0;unpack_lane<=0;unpack_valid<=0;rx_bus_words<=0;
            error_code<=0;rx_words<=0;tx_words<=0;done_sticky<=0;tx_active<=0;tx_sent<=0;
            tx_index<=0;tx_status<=0;tx_tag<=0;tx_prediction<=0;elapsed<=0;frozen_elapsed<=0;
        end else begin
            if(start_pulse) elapsed<=0;else if(busy && !rsp_valid) elapsed<=elapsed+1'b1;
            // Emit logical scalars only on the native loader handshake. A packed
            // word remains unchanged until all four lanes have been accepted.
            if(cfg_fire) begin
                rx_index<=rx_index+1'b1;rx_words<=rx_words+1'b1;
                if(unpack_last) begin unpack_valid<=0;unpack_lane<=0;end
                else unpack_lane<=unpack_lane+1'b1;
                if(rx_index==rx_limit-1'b1) begin
                    rx_state<=0;stage<=stage+1'b1;
                    if(stage==4) begin rx_enabled<=0;load_complete<=1;end
                end
            end
            if(s_axis_tvalid && s_axis_tready) begin
                rx_bus_words<=rx_bus_words+1'b1;
                if(rx_state==4) begin if(s_axis_tlast) rx_enabled<=0;end
                else if(s_axis_tkeep!=4'hf || (rx_state!=3 && s_axis_tlast)) begin
                    error_code<=32'h01;rx_state<=4;if(s_axis_tlast) rx_enabled<=0;
                end else case(rx_state)
                    0:if(s_axis_tdata==LOAD_MAGIC) rx_state<=1;else begin error_code<=2;rx_state<=4;end
                    1:if(s_axis_tdata=={29'd0,stage} && stage<5) rx_state<=2;else begin error_code<=3;rx_state<=4;end
                    2:if(s_axis_tdata=={13'd0,expected_count}) begin rx_limit<=expected_count;rx_index<=0;rx_ingress<=0;rx_state<=3;end
                      else begin error_code<=4;rx_state<=4;end
                    3:if(!payload_format_ok) begin error_code<=5;rx_state<=4;if(s_axis_tlast) rx_enabled<=0;end
                      else begin
                        unpack_data<=s_axis_tdata;unpack_lane<=0;unpack_valid<=1;
                        rx_ingress<=rx_ingress+{16'd0,ingress_units};
                      end
                    default:begin error_code<=6;rx_enabled<=0;end
                endcase
            end
            if(load_error || start_rejected) begin
                error_code<=32'h10;load_complete<=0;unpack_valid<=0;rx_state<=4;
                // Let a malformed MM2S packet drain, so software can observe the
                // error after DMA completion. If TLAST was buffered, stop now.
                rx_enabled<=rx_ingress<rx_limit;
            end
            if(fault && error_code==0) error_code<=32'h80000000|{29'd0,fault_code};
            if((rsp_valid || fault) && !tx_active && !tx_sent) begin
                tx_active<=1;tx_index<=0;tx_tag<=tag;tx_prediction<=prediction;frozen_elapsed<=elapsed;
                tx_status<=fault?(32'h80000000|{29'd0,fault_code}):32'd0;
            end
            if(m_axis_tvalid && m_axis_tready) begin
                tx_words<=tx_words+1'b1;
                if(tx_index==15) begin tx_active<=0;tx_sent<=1;done_sticky<=1;end
                else tx_index<=tx_index+1'b1;
            end
        end
    end
    // Protection attributes are accepted; this peripheral does not distinguish privilege.
    wire unused_ok=&{1'b0,s_axi_awprot,s_axi_arprot,step_valid,mac_fire,gap_fire,trace_valid,trace_skip_from_x,
        trace_op,trace_addr,trace_skip_addr,trace_acc,trace_code,trace_skip,trace_wide,done};
endmodule
