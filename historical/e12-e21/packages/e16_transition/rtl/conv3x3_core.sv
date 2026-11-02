`timescale 1ns/1ps
`default_nettype none
// Static shape only: stride1/2, dilation1, groups1, symmetric integer zero point0.
// No runtime divider/modulo. ci/ky/kx and co/oy/ox are nested counters.
module conv3x3_core #(
    parameter integer CIN=3,COUT=16,H=32,W=32,PAD=1,STRIDE=1,
    parameter integer OH=(H+2*PAD-3)/STRIDE+1,OW=(W+2*PAD-3)/STRIDE+1
)(
    input wire clk,rst,prepared,cmd_valid,output wire cmd_ready,
    input wire relu_mode,input wire signed [31:0] bias_cfg [0:COUT-1],
    output wire busy,rsp_valid,input wire rsp_ready,
    output wire x_ram_en,output wire [15:0] x_ram_addr,input wire [7:0] x_ram_data,
    output wire w_ram_en,output wire [15:0] w_ram_addr,input wire [7:0] w_ram_data,
    output wire y_valid,input wire y_ready,output wire signed [7:0] y_data,
    output wire [15:0] y_index,output wire y_last,
    output wire dbg_req_fire,dbg_req_pad,dbg_term_fire,dbg_term_pad,dbg_acc_fire,
    output wire [31:0] dbg_req_tag,dbg_term_tag,output wire signed [31:0] dbg_acc_data
);
    localparam integer NOUT=COUT*OH*OW,K=CIN*9;
    localparam integer CIW=(CIN>1)?$clog2(CIN):1,COW=(COUT>1)?$clog2(COUT):1;
    localparam integer YW=(OH>1)?$clog2(OH):1,XW=(OW>1)?$clog2(OW):1;
    localparam IDLE=3'd0,ISSUE=3'd1,WAIT_PAIR=3'd2,WAIT_Y=3'd3,RESP=3'd4;
    reg [2:0] state;
    reg [CIW-1:0] ci;
    reg [COW-1:0] co;
    reg [YW-1:0] oy;reg [XW-1:0] ox;
    reg [1:0] ky,kx;
    reg [15:0] index,k;
    reg relu_q,pad_q;
    reg signed [31:0] bias_q [0:COUT-1];
    wire signed [31:0] iy=32'(oy)*STRIDE+32'(ky)-PAD;
    wire signed [31:0] ix=32'(ox)*STRIDE+32'(kx)-PAD;
    wire padding=(iy<0)||(iy>=H)||(ix<0)||(ix>=W);
    // The cast of an out-of-range address is never used for a RAM read.
    wire [15:0] x_address=16'(32'(ci)*H*W+iy*W+ix);
    wire [15:0] w_address=16'(32'(co)*K+32'(k));
    wire [31:0] request_tag={index,k};
    wire xr_ready,wr_ready,xv,wv;
    wire [7:0] xd,wd;wire [31:0] xt,wt;
    wire mac_ready,mac_valid,acc_valid,post_ready;
    wire signed [31:0] acc;
    wire pair_ok=pad_q||(xv&&(xt==wt));
    wire x_request=(state==ISSUE)&&!padding&&wr_ready;
    wire w_request=(state==ISSUE)&&(padding||xr_ready);
    assign dbg_req_fire=(state==ISSUE)&&wr_ready&&(padding||xr_ready)&&!rst;
    assign dbg_req_pad=padding;assign dbg_req_tag=request_tag;
    assign mac_valid=(state==WAIT_PAIR)&&wv&&pair_ok;
    assign dbg_term_fire=mac_valid&&mac_ready;
    assign dbg_term_pad=pad_q;assign dbg_term_tag=wt;
    assign dbg_acc_fire=acc_valid&&post_ready;assign dbg_acc_data=acc;
    assign cmd_ready=(state==IDLE)&&prepared&&!rst;
    assign busy=(state!=IDLE)&&(state!=RESP);
    assign rsp_valid=(state==RESP)&&!rst;
    read_hold #(.AW(16),.TW(32)) xr(
        .clk(clk),.rst(rst),.req_valid(x_request),.req_ready(xr_ready),
        .req_addr(x_address),.req_tag(request_tag),.ram_en(x_ram_en),.ram_addr(x_ram_addr),
        .ram_data(x_ram_data),.rsp_valid(xv),
        .rsp_ready((state==WAIT_PAIR)&&wv&&mac_ready&&pair_ok&&!pad_q),
        .rsp_data(xd),.rsp_tag(xt));
    read_hold #(.AW(16),.TW(32)) wr(
        .clk(clk),.rst(rst),.req_valid(w_request),.req_ready(wr_ready),
        .req_addr(w_address),.req_tag(request_tag),.ram_en(w_ram_en),.ram_addr(w_ram_addr),
        .ram_data(w_ram_data),.rsp_valid(wv),
        .rsp_ready((state==WAIT_PAIR)&&mac_ready&&pair_ok),.rsp_data(wd),.rsp_tag(wt));
    mac_scalar mac(.clk(clk),.rst(rst),.term_valid(mac_valid),.term_ready(mac_ready),
        .x(pad_q?8'sd0:$signed(xd)),.w($signed(wd)),.first(k==0),.last(k==16'(K-1)),
        .bias(bias_q[co]),.acc_valid(acc_valid),.acc_ready(post_ready),.acc_data(acc));
    postprocess_index #(.NOUT(NOUT)) post(.clk(clk),.rst(rst),
        .acc_valid(acc_valid),.acc_ready(post_ready),.acc_data(acc),.relu_mode(relu_q),
        .index_in(index),.y_valid(y_valid),.y_ready(y_ready),.y_data(y_data),
        .y_index(y_index),.y_last(y_last));
    always @(posedge clk)begin
        if(rst)begin
            state<=IDLE;ci<=0;co<=0;oy<=0;ox<=0;ky<=0;kx<=0;index<=0;k<=0;
            relu_q<=0;pad_q<=0;
            for(integer b=0;b<COUT;b=b+1)bias_q[b]<=0;
        end else case(state)
            IDLE:if(cmd_valid&&cmd_ready)begin
                relu_q<=relu_mode;index<=0;k<=0;ci<=0;co<=0;oy<=0;ox<=0;ky<=0;kx<=0;
                for(integer b=0;b<COUT;b=b+1)bias_q[b]<=bias_cfg[b];
                state<=ISSUE;
            end
            ISSUE:if(dbg_req_fire)begin pad_q<=padding;state<=WAIT_PAIR;end
            WAIT_PAIR:if(dbg_term_fire)begin
                if(k==16'(K-1))state<=WAIT_Y;
                else begin
                    k<=k+1;
                    if(kx==2)begin
                        kx<=0;
                        if(ky==2)begin ky<=0;ci<=ci+1;end
                        else ky<=ky+1;
                    end else kx<=kx+1;
                    state<=ISSUE;
                end
            end
            WAIT_Y:if(y_valid&&y_ready)begin
                if(index==16'(NOUT-1))state<=RESP;
                else begin
                    index<=index+1;k<=0;ci<=0;ky<=0;kx<=0;
                    if(ox==XW'(OW-1))begin
                        ox<=0;
                        if(oy==YW'(OH-1))begin oy<=0;co<=co+1;end
                        else oy<=oy+1;
                    end else ox<=ox+1;
                    state<=ISSUE;
                end
            end
            RESP:if(rsp_valid&&rsp_ready)state<=IDLE;
            default:state<=IDLE;
        endcase
    end
endmodule
`default_nettype wire
