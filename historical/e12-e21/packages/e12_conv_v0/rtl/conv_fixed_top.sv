`timescale 1ns/1ps
`default_nettype none
module conv_fixed_top(
    input wire clk,rst,
    input wire prepared,cmd_valid,output wire cmd_ready,
    input wire relu_mode,input wire signed [31:0] bias0,bias1,
    output wire busy,rsp_valid,input wire rsp_ready,
    output wire x_ram_en,output wire [4:0] x_ram_addr,input wire [7:0] x_ram_data,
    output wire w_ram_en,output wire [5:0] w_ram_addr,input wire [7:0] w_ram_data,
    output wire y_valid,input wire y_ready,
    output wire signed [7:0] y_data,output wire [2:0] y_index,output wire y_last,
    output wire dbg_req_fire,dbg_term_fire,dbg_acc_fire,
    output wire [7:0] dbg_req_tag,dbg_term_tag,
    output wire signed [31:0] dbg_acc_data
);
    localparam IDLE=3'd0,ISSUE=3'd1,WAIT_PAIR=3'd2,WAIT_Y=3'd3,RESP=3'd4;
    reg [2:0] state,index;
    reg [4:0] k;
    reg relu_q;
    reg signed [31:0] b0_q,b1_q;
    wire [4:0] remk=(k>=5'd9)?(k-5'd9):k;
    wire ci=(k>=5'd9);
    reg [1:0] ky,kx;
    always @* begin
        case(remk)
            0: begin ky=0;kx=0;end
            1: begin ky=0;kx=1;end
            2: begin ky=0;kx=2;end
            3: begin ky=1;kx=0;end
            4: begin ky=1;kx=1;end
            5: begin ky=1;kx=2;end
            6: begin ky=2;kx=0;end
            7: begin ky=2;kx=1;end
            default: begin ky=2;kx=2;end
        endcase
    end
    wire [1:0] iy={1'b0,index[1]}+ky;
    wire [1:0] ix={1'b0,index[0]}+kx;
    wire [4:0] x_address={ci,4'b0}+{1'b0,iy,2'b0}+{3'b0,ix};
    wire [5:0] w_address=(index[2]?6'd18:6'd0)+{1'b0,k};
    wire [7:0] request_tag={index,k};
    wire xr_ready,wr_ready,xv,wv;
    wire [7:0] xd,wd,xt,wt;
    wire mac_ready,mac_valid,mac_acc_valid,post_ready;
    wire signed [31:0] acc;
    wire x_request=(state==ISSUE)&&wr_ready;
    wire w_request=(state==ISSUE)&&xr_ready;
    assign dbg_req_fire=(state==ISSUE)&&xr_ready&&wr_ready&&!rst;
    assign dbg_req_tag=request_tag;
    assign mac_valid=(state==WAIT_PAIR)&&xv&&wv&&(xt==wt);
    assign dbg_term_fire=mac_valid&&mac_ready;
    assign dbg_term_tag=xt;
    assign dbg_acc_fire=mac_acc_valid&&post_ready;
    assign dbg_acc_data=acc;
    assign cmd_ready=(state==IDLE)&&prepared&&!rst;
    assign busy=(state!=IDLE)&&(state!=RESP);
    assign rsp_valid=(state==RESP)&&!rst;

    read_hold #(.AW(5)) xr(
        .clk(clk),.rst(rst),.req_valid(x_request),.req_ready(xr_ready),
        .req_addr(x_address),.req_tag(request_tag),.ram_en(x_ram_en),.ram_addr(x_ram_addr),
        .ram_data(x_ram_data),.rsp_valid(xv),.rsp_ready((state==WAIT_PAIR)&&wv&&mac_ready),
        .rsp_data(xd),.rsp_tag(xt));
    read_hold #(.AW(6)) wr(
        .clk(clk),.rst(rst),.req_valid(w_request),.req_ready(wr_ready),
        .req_addr(w_address),.req_tag(request_tag),.ram_en(w_ram_en),.ram_addr(w_ram_addr),
        .ram_data(w_ram_data),.rsp_valid(wv),.rsp_ready((state==WAIT_PAIR)&&xv&&mac_ready),
        .rsp_data(wd),.rsp_tag(wt));
    mac_scalar mac(
        .clk(clk),.rst(rst),.term_valid(mac_valid),.term_ready(mac_ready),
        .x($signed(xd)),.w($signed(wd)),.first(k==0),.last(k==17),
        .bias(index[2]?b1_q:b0_q),.acc_valid(mac_acc_valid),.acc_ready(post_ready),.acc_data(acc));
    postprocess4 post(
        .clk(clk),.rst(rst),.acc_valid(mac_acc_valid),.acc_ready(post_ready),.acc_data(acc),
        .relu_mode(relu_q),.index_in(index),.y_valid(y_valid),.y_ready(y_ready),
        .y_data(y_data),.y_index(y_index),.y_last(y_last));

    always @(posedge clk) begin
        if(rst) begin state<=IDLE;index<=0;k<=0;relu_q<=0;b0_q<=0;b1_q<=0;end
        else case(state)
            IDLE: if(cmd_valid&&cmd_ready) begin
                relu_q<=relu_mode;b0_q<=bias0;b1_q<=bias1;index<=0;k<=0;state<=ISSUE;
            end
            ISSUE: if(dbg_req_fire) state<=WAIT_PAIR;
            WAIT_PAIR: if(dbg_term_fire) begin
                if(k==17) state<=WAIT_Y;
                else begin k<=k+1;state<=ISSUE;end
            end
            WAIT_Y: if(y_valid&&y_ready) begin
                if(index==7) state<=RESP;
                else begin index<=index+1;k<=0;state<=ISSUE;end
            end
            RESP: if(rsp_valid&&rsp_ready) state<=IDLE;
            default: state<=IDLE;
        endcase
    end
endmodule
`default_nettype wire
