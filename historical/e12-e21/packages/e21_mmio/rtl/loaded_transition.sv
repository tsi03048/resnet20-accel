`timescale 1ns/1ps
`default_nettype none
// Native same-clock ordered preload. Host authenticates/validates manifest; RTL does not hash JSON.
module loaded_transition #(parameter integer C=2,H=4,D=2*C,NX=C*H*H,NW1=C*D*9,NW2=D*D*9)(
    input wire clk,rst,
    input wire begin_valid,output wire begin_ready,input wire host_validated,
    input wire [255:0] manifest_digest,input wire [31:0] generation,
    input wire [15:0] begin_c,begin_h,
    input wire wr_valid,output wire wr_ready,input wire [3:0] wr_role,
    input wire [15:0] wr_addr,input wire [31:0] wr_data,
    input wire commit_valid,output wire commit_ready,
    input wire cmd_valid,output wire cmd_ready,input wire [31:0] cmd_generation,
    output wire prepared,busy,error,output reg [2:0] error_code,
    output reg [255:0] active_digest,output reg [31:0] active_generation,
    output wire rsp_valid,input wire rsp_ready,
    output wire y_valid,input wire y_ready,output wire signed [7:0] y_data,
    output wire [15:0] y_index,output wire y_last,
    output wire dbg_begin_fire,dbg_wr_fire,dbg_commit_fire,dbg_core_cmd_fire
);
    localparam IDLE=3'd0,LOAD=3'd1,READY=3'd2,RUN=3'd3,RESP=3'd4,ERROR=3'd5;
    reg [2:0] state;reg [3:0] expected_role;reg [15:0] expected_addr;
    reg [31:0] role_limit;
    always @*case(expected_role)
        0:role_limit=NX;
        1:role_limit=NW1;
        2:role_limit=NW2;
        3,4,5,6,7,8,9,10,11:role_limit=D;
        default:role_limit=0;
    endcase
    wire core_cmd_ready,core_load_ready,core_rsp;
    wire unused_busy;
    wire [3:0] unused_stage;
    wire unused_y_fire,unused_acc_fire,unused_term;
    wire [15:0] unused_index;wire signed [7:0] unused_data;wire signed [31:0] unused_acc;
    reg signed [31:0] b1[0:D-1],b2[0:D-1];
    reg [15:0] n1[0:D-1],n2[0:D-1],nm[0:D-1],ns[0:D-1];
    reg [4:0] s1[0:D-1],s2[0:D-1],sa[0:D-1];
    wire begin_priority=begin_valid&&begin_ready;
    assign begin_ready=(state!=RUN)&&(state!=RESP)&&!rst;
    assign wr_ready=(state==LOAD)&&core_load_ready&&!begin_priority&&!commit_valid&&!rst;
    assign commit_ready=(state==LOAD)&&!begin_priority&&!rst;
    assign cmd_ready=(state==READY)&&!begin_priority&&!rst;
    assign dbg_begin_fire=begin_valid&&begin_ready;
    assign dbg_wr_fire=wr_valid&&wr_ready;
    assign dbg_commit_fire=commit_valid&&commit_ready;
    wire ordered=(wr_role==expected_role)&&(expected_role<12);
    wire address_ok=(wr_addr==expected_addr)&&(32'(wr_addr)<role_limit);
    wire range_ok=(wr_role<=2)?(wr_data[31:8]==0):
                  ((wr_role>=5)&&(wr_role<=8))?(wr_data<=65535):
                  ((wr_role>=9)&&(wr_role<=11))?(wr_data<=31):1'b1;
    wire write_ok=dbg_wr_fire&&ordered&&address_ok&&range_ok;
    wire core_command=cmd_valid&&cmd_ready&&(cmd_generation==active_generation);
    assign dbg_core_cmd_fire=core_command;
    assign prepared=(state==READY)&&!rst;
    assign busy=(state==RUN);assign error=(state==ERROR);
    assign rsp_valid=(state==RESP)&&!rst;
    transition_block #(.C(C),.H(H)) core(.clk(clk),.rst(rst),.prepared(prepared),
        .cmd_valid(core_command),.cmd_ready(core_cmd_ready),
        .load_we(write_ok&&(wr_role<=2)),.load_sel(wr_role[1:0]),.load_addr(wr_addr),
        .load_data(wr_data[7:0]),.load_ready(core_load_ready),
        .bias1_cfg(b1),.bias2_cfg(b2),.n1_cfg(n1),.n2_cfg(n2),.nm_cfg(nm),.ns_cfg(ns),
        .s1_cfg(s1),.s2_cfg(s2),.sa_cfg(sa),
        .busy(unused_busy),.rsp_valid(core_rsp),.rsp_ready(state==RUN),
        .y_valid(y_valid),.y_ready(y_ready),.y_data(y_data),.y_index(y_index),.y_last(y_last),
        .dbg_stage(unused_stage),.dbg_conv_y_fire(unused_y_fire),.dbg_conv_acc_fire(unused_acc_fire),
        .dbg_conv_y_index(unused_index),.dbg_conv_y_data(unused_data),.dbg_conv_acc(unused_acc),.dbg_term_fire(unused_term));
    always @(posedge clk)if(!rst&&core_command&&!core_cmd_ready)$error("core command ownership");
    always @(posedge clk)begin
        if(rst)begin
            state<=IDLE;expected_role<=0;expected_addr<=0;error_code<=0;active_digest<=0;active_generation<=0;
            for(integer i=0;i<D;i=i+1)begin b1[i]<=0;b2[i]<=0;n1[i]<=0;n2[i]<=0;nm[i]<=0;ns[i]<=0;s1[i]<=0;s2[i]<=0;sa[i]<=0;end
        end else if(dbg_begin_fire)begin
            expected_role<=0;expected_addr<=0;active_digest<=manifest_digest;active_generation<=generation;
            if(!host_validated)begin state<=ERROR;error_code<=1;end
            else if(begin_c!=16'(C)||begin_h!=16'(H))begin state<=ERROR;error_code<=7;end
            else begin state<=LOAD;error_code<=0;end
        end else case(state)
            LOAD:begin
                if(dbg_commit_fire)begin
                    if(expected_role==12)state<=READY;
                    else begin state<=ERROR;error_code<=5;end
                end else if(dbg_wr_fire)begin
                    if(!ordered)begin state<=ERROR;error_code<=2;end
                    else if(!address_ok)begin state<=ERROR;error_code<=3;end
                    else if(!range_ok)begin state<=ERROR;error_code<=4;end
                    else begin
                        case(wr_role)
                            3:b1[integer'(wr_addr)]<=$signed(wr_data);
                            4:b2[integer'(wr_addr)]<=$signed(wr_data);
                            5:n1[integer'(wr_addr)]<=wr_data[15:0];
                            6:n2[integer'(wr_addr)]<=wr_data[15:0];
                            7:nm[integer'(wr_addr)]<=wr_data[15:0];
                            8:ns[integer'(wr_addr)]<=wr_data[15:0];
                            9:s1[integer'(wr_addr)]<=wr_data[4:0];
                            10:s2[integer'(wr_addr)]<=wr_data[4:0];
                            11:sa[integer'(wr_addr)]<=wr_data[4:0];
                            default:begin end
                        endcase
                        if(32'(expected_addr)==role_limit-1)begin expected_role<=expected_role+1;expected_addr<=0;end
                        else expected_addr<=expected_addr+1;
                    end
                end
            end
            READY:if(cmd_valid&&cmd_ready)begin
                if(cmd_generation==active_generation)state<=RUN;
                else begin state<=ERROR;error_code<=6;end
            end
            RUN:if(core_rsp)state<=RESP;
            RESP:if(rsp_valid&&rsp_ready)state<=IDLE;
            default:begin end
        endcase
    end
endmodule
`default_nettype wire
