`timescale 1ns/1ps
`default_nettype none
// Diagnostic quantized Identity block: H=ReLU(Q4(Conv1(X))),
// M=Q4(Conv2(H)), Y=sat8(ReLU(signext(M)+signext(X))).
// X, H, M and Y share one activation scale; zero points0, weight scale1/4.
module residual_block #(parameter integer C=2,H=4,W=H)(
    input wire clk,rst,prepared,cmd_valid,output wire cmd_ready,
    input wire load_we,input wire [1:0] load_sel,input wire [15:0] load_addr,
    input wire [7:0] load_data,output wire load_ready,
    input wire signed [31:0] bias1_cfg[0:C-1],bias2_cfg[0:C-1],
    output wire busy,rsp_valid,input wire rsp_ready,
    output wire y_valid,input wire y_ready,output wire signed [7:0] y_data,
    output wire [15:0] y_index,output wire y_last,
    output wire [3:0] dbg_stage,output wire dbg_conv_y_fire,dbg_conv_acc_fire,
    output wire [15:0] dbg_conv_y_index,output wire signed [7:0] dbg_conv_y_data,
    output wire signed [31:0] dbg_conv_acc,output wire dbg_term_fire
);
    localparam integer N=C*H*W,NW=C*C*9;
    localparam IDLE=4'd0,START1=4'd1,RUN1=4'd2,START2=4'd3,RUN2=4'd4,
               ADD_ISSUE=4'd5,ADD_WAIT=4'd6,ADD_HOLD=4'd7,RESP=4'd8;
    reg [3:0] state;
    reg [7:0] xmem[0:N-1],amem[0:N-1],fmem[0:N-1];
    reg [7:0] w1mem[0:NW-1],w2mem[0:NW-1];
    reg signed [31:0] b1[0:C-1],b2[0:C-1];
    wire signed [31:0] selected_bias[0:C-1];
    wire stage1=(state==START1)||(state==RUN1);
    for(genvar i=0;i<C;i=i+1)begin:BIAS
        assign selected_bias[i]=stage1?b1[i]:b2[i];
    end
    assign cmd_ready=(state==IDLE)&&prepared&&!load_we&&!rst;
    assign load_ready=(state==IDLE)&&!cmd_valid&&!rst;
    assign busy=(state!=IDLE)&&(state!=RESP);
    assign rsp_valid=(state==RESP)&&!rst;
    assign dbg_stage=state;
    wire core_cmd_ready,core_busy,core_rsp,xe,we,cyv,cyl;
    wire [15:0] xa,wa,cyi;
    wire signed [7:0] cyd;
    reg [7:0] xd,wd;
    wire core_y_ready=(state==RUN1)||(state==RUN2);
    wire unused_req_fire,unused_req_pad,unused_term_pad;
    wire [31:0] unused_req_tag,unused_term_tag;
    assign dbg_conv_y_fire=cyv&&core_y_ready;
    assign dbg_conv_y_index=cyi;assign dbg_conv_y_data=cyd;
    conv3x3_core #(.CIN(C),.COUT(C),.H(H),.W(W),.PAD(1)) core(
        .clk(clk),.rst(rst),.prepared(1'b1),.cmd_valid((state==START1)||(state==START2)),
        .cmd_ready(core_cmd_ready),.relu_mode(stage1),.bias_cfg(selected_bias),
        .busy(core_busy),.rsp_valid(core_rsp),.rsp_ready((state==RUN1)||(state==RUN2)),
        .x_ram_en(xe),.x_ram_addr(xa),.x_ram_data(xd),.w_ram_en(we),.w_ram_addr(wa),.w_ram_data(wd),
        .y_valid(cyv),.y_ready(core_y_ready),.y_data(cyd),.y_index(cyi),.y_last(cyl),
        .dbg_req_fire(unused_req_fire),.dbg_req_pad(unused_req_pad),
        .dbg_term_fire(dbg_term_fire),.dbg_term_pad(unused_term_pad),
        .dbg_acc_fire(dbg_conv_acc_fire),.dbg_req_tag(unused_req_tag),
        .dbg_term_tag(unused_term_tag),.dbg_acc_data(dbg_conv_acc));
    reg [15:0] add_index;
    reg signed [7:0] skip_q,main_q,result_q;
    wire signed [8:0] add_wide={main_q[7],main_q}+{skip_q[7],skip_q};
    assign y_valid=(state==ADD_HOLD)&&!rst;
    assign y_data=result_q;assign y_index=add_index;
    assign y_last=(add_index==16'(N-1));
    always @(posedge clk)begin
        if(load_we&&load_ready)begin
            case(load_sel)
                0:if(integer'(load_addr)<N)xmem[integer'(load_addr)]<=load_data;
                1:if(integer'(load_addr)<NW)w1mem[integer'(load_addr)]<=load_data;
                2:if(integer'(load_addr)<NW)w2mem[integer'(load_addr)]<=load_data;
                default:begin end
            endcase
        end
        if(!rst)begin
            if(xe)xd<=stage1?xmem[integer'(xa)]:amem[integer'(xa)];
            if(we)wd<=stage1?w1mem[integer'(wa)]:w2mem[integer'(wa)];
            if(dbg_conv_y_fire)begin
                if(state==RUN1)amem[integer'(cyi)]<=cyd;
                if(state==RUN2)fmem[integer'(cyi)]<=cyd;
            end
        end
        if(rst)begin
            state<=IDLE;add_index<=0;skip_q<=0;main_q<=0;result_q<=0;xd<=0;wd<=0;
            for(integer i=0;i<C;i=i+1)begin b1[i]<=0;b2[i]<=0;end
        end else case(state)
            IDLE:if(cmd_valid&&cmd_ready)begin
                for(integer i=0;i<C;i=i+1)begin b1[i]<=bias1_cfg[i];b2[i]<=bias2_cfg[i];end
                state<=START1;
            end
            START1:if(core_cmd_ready)state<=RUN1;
            RUN1:if(core_rsp)state<=START2;
            START2:if(core_cmd_ready)state<=RUN2;
            RUN2:if(core_rsp)begin add_index<=0;state<=ADD_ISSUE;end
            ADD_ISSUE:begin
                skip_q<=$signed(xmem[integer'(add_index)]);
                main_q<=$signed(fmem[integer'(add_index)]);state<=ADD_WAIT;
            end
            ADD_WAIT:begin
                if(add_wide<0)result_q<=0;
                else if(add_wide>127)result_q<=8'sd127;
                else result_q<=add_wide[7:0];
                state<=ADD_HOLD;
            end
            ADD_HOLD:if(y_valid&&y_ready)begin
                // Conv2 has drained: B no longer contains a live H tensor.
                amem[integer'(add_index)]<=result_q;
                if(add_index==16'(N-1))state<=RESP;
                else begin add_index<=add_index+1;state<=ADD_ISSUE;end
            end
            RESP:if(rsp_valid&&rsp_ready)state<=IDLE;
            default:state<=IDLE;
        endcase
    end
    // Observe the internal completion fields in simulation assertions below.
    // They are functional guards as well as checks on sequential ownership.
    always @(posedge clk)if(!rst)begin
        if(core_rsp&&core_busy)$error("core response while busy");
        if(dbg_conv_y_fire&&(cyl!=(cyi==16'(N-1))))$error("core last/index");
    end
endmodule
`default_nettype wire
