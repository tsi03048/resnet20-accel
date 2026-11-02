`timescale 1ns/1ps
`default_nettype none
// Diagnostic Option A Transition; two separately elaborated cores, sequential schedule: H=ReLU(Q4(Conv1(X))),
// M=Q4(Conv2(H)), Y=sat8(ReLU(signext(M)+signext(OptionA(X)))).
// X, H, M and Y share one activation scale; zero points0, weight scale1/4.
module transition_block #(parameter integer C=2,H=4,W=H,D=2*C,OH=H/2,OW=W/2)(
    input wire clk,rst,prepared,cmd_valid,output wire cmd_ready,
    input wire load_we,input wire [1:0] load_sel,input wire [15:0] load_addr,
    input wire [7:0] load_data,output wire load_ready,
    input wire signed [31:0] bias1_cfg[0:D-1],bias2_cfg[0:D-1],
    output wire busy,rsp_valid,input wire rsp_ready,
    output wire y_valid,input wire y_ready,output wire signed [7:0] y_data,
    output wire [15:0] y_index,output wire y_last,
    output wire [3:0] dbg_stage,output wire dbg_conv_y_fire,dbg_conv_acc_fire,
    output wire [15:0] dbg_conv_y_index,output wire signed [7:0] dbg_conv_y_data,
    output wire signed [31:0] dbg_conv_acc,output wire dbg_term_fire
);
    localparam integer N=D*OH*OW,NX=C*H*W,NW1=C*D*9,NW2=D*D*9;
    localparam IDLE=4'd0,START1=4'd1,RUN1=4'd2,START2=4'd3,RUN2=4'd4,
               ADD_ISSUE=4'd5,ADD_WAIT=4'd6,ADD_HOLD=4'd7,RESP=4'd8;
    reg [3:0] state;
    reg [7:0] xmem[0:NX-1],amem[0:N-1],fmem[0:N-1];
    reg [7:0] w1mem[0:NW1-1],w2mem[0:NW2-1];
    reg signed [31:0] b1[0:D-1],b2[0:D-1];
    wire stage1=(state==START1)||(state==RUN1);
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
    wire [1:0] cr,cb,cs,xe_i,we_i,yv_i,yl_i,rf_i,rp_i,tf_i,tp_i,af_i;
    wire [15:0] xa_i[0:1],wa_i[0:1],yi_i[0:1];
    wire signed [7:0] yd_i[0:1];
    wire [31:0] rt_i[0:1],tt_i[0:1];
    wire signed [31:0] ad_i[0:1];
    wire select2=!stage1;
    assign core_cmd_ready=cr[select2];assign core_busy=cb[select2];assign core_rsp=cs[select2];
    assign xe=xe_i[select2];assign we=we_i[select2];assign xa=xa_i[select2];assign wa=wa_i[select2];
    assign cyv=yv_i[select2];assign cyl=yl_i[select2];assign cyi=yi_i[select2];assign cyd=yd_i[select2];
    assign unused_req_fire=rf_i[select2];assign unused_req_pad=rp_i[select2];
    assign unused_req_tag=rt_i[select2];assign unused_term_tag=tt_i[select2];
    assign unused_term_pad=tp_i[select2];assign dbg_term_fire=tf_i[select2];
    assign dbg_conv_acc_fire=af_i[select2];assign dbg_conv_acc=ad_i[select2];
    conv3x3_core #(.CIN(C),.COUT(D),.H(H),.W(W),.PAD(1),.STRIDE(2)) core1(
        .clk(clk),.rst(rst),.prepared(1'b1),.cmd_valid(state==1),.cmd_ready(cr[0]),
        .relu_mode(1'b1),.bias_cfg(b1),.busy(cb[0]),.rsp_valid(cs[0]),.rsp_ready(state==2),
        .x_ram_en(xe_i[0]),.x_ram_addr(xa_i[0]),.x_ram_data(xd),
        .w_ram_en(we_i[0]),.w_ram_addr(wa_i[0]),.w_ram_data(wd),
        .y_valid(yv_i[0]),.y_ready(state==2),.y_data(yd_i[0]),.y_index(yi_i[0]),.y_last(yl_i[0]),
        .dbg_req_fire(rf_i[0]),.dbg_req_pad(rp_i[0]),.dbg_term_fire(tf_i[0]),.dbg_term_pad(tp_i[0]),
        .dbg_acc_fire(af_i[0]),.dbg_req_tag(rt_i[0]),.dbg_term_tag(tt_i[0]),.dbg_acc_data(ad_i[0]));
    conv3x3_core #(.CIN(D),.COUT(D),.H(OH),.W(OW),.PAD(1),.STRIDE(1)) core2(
        .clk(clk),.rst(rst),.prepared(1'b1),.cmd_valid(state==3),.cmd_ready(cr[1]),
        .relu_mode(1'b0),.bias_cfg(b2),.busy(cb[1]),.rsp_valid(cs[1]),.rsp_ready(state==4),
        .x_ram_en(xe_i[1]),.x_ram_addr(xa_i[1]),.x_ram_data(xd),
        .w_ram_en(we_i[1]),.w_ram_addr(wa_i[1]),.w_ram_data(wd),
        .y_valid(yv_i[1]),.y_ready(state==4),.y_data(yd_i[1]),.y_index(yi_i[1]),.y_last(yl_i[1]),
        .dbg_req_fire(rf_i[1]),.dbg_req_pad(rp_i[1]),.dbg_term_fire(tf_i[1]),.dbg_term_pad(tp_i[1]),
        .dbg_acc_fire(af_i[1]),.dbg_req_tag(rt_i[1]),.dbg_term_tag(tt_i[1]),.dbg_acc_data(ad_i[1]));
    reg [15:0] add_index;
    // H/OW are static powers of two in the three verified configurations.
    wire [15:0] skip_co=add_index >> $clog2(OH*OW);
    wire [15:0] skip_oy=(add_index >> $clog2(OW)) & 16'(OH-1);
    wire [15:0] skip_ox=add_index & 16'(OW-1);
    wire skip_zero=(skip_co<16'(C/2))||(skip_co>=16'(C/2+C));
    wire [15:0] skip_address=16'((32'(skip_co)-C/2)*H*W+32'(skip_oy)*2*W+32'(skip_ox)*2);
    reg signed [7:0] skip_q,main_q,result_q;
    wire signed [8:0] add_wide={main_q[7],main_q}+{skip_q[7],skip_q};
    assign y_valid=(state==ADD_HOLD)&&!rst;
    assign y_data=result_q;assign y_index=add_index;
    assign y_last=(add_index==16'(N-1));
    always @(posedge clk)begin
        if(load_we&&load_ready)begin
            case(load_sel)
                0:if(integer'(load_addr)<NX)xmem[integer'(load_addr)]<=load_data;
                1:if(integer'(load_addr)<NW1)w1mem[integer'(load_addr)]<=load_data;
                2:if(integer'(load_addr)<NW2)w2mem[integer'(load_addr)]<=load_data;
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
            for(integer i=0;i<D;i=i+1)begin b1[i]<=0;b2[i]<=0;end
        end else case(state)
            IDLE:if(cmd_valid&&cmd_ready)begin
                for(integer i=0;i<D;i=i+1)begin b1[i]<=bias1_cfg[i];b2[i]<=bias2_cfg[i];end
                state<=START1;
            end
            START1:if(core_cmd_ready)state<=RUN1;
            RUN1:if(core_rsp)state<=START2;
            START2:if(core_cmd_ready)state<=RUN2;
            RUN2:if(core_rsp)begin add_index<=0;state<=ADD_ISSUE;end
            ADD_ISSUE:begin
                if(skip_zero)skip_q<=0;
                else skip_q<=$signed(xmem[integer'(skip_address)]);
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
