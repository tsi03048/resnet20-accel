`timescale 1ns/1ps
`default_nettype none
// Custom single-outstanding same-clock MMIO endpoint. NOT AXI/APB.
module mmio_transition #(parameter integer C=2,H=4)(
 input wire clk,rst,
 input wire req_valid,output wire req_ready,input wire req_write,
 input wire [11:0] req_addr,input wire [31:0] req_wdata,input wire [3:0] req_wstrb,
 output reg rsp_valid,input wire rsp_ready,output reg [31:0] rsp_rdata,output reg [2:0] rsp_code,
 output wire y_valid,input wire y_ready,output wire signed [7:0] y_data,
 output wire [15:0] y_index,output wire y_last
);
 reg [31:0] gen,cmdgen,shape,claim,selector,data_word;
 reg [255:0] digest;
 reg [31:0] native_write_count;
 wire br,wr,cr,sr,done,prepared,busy,err;
 wire [2:0] ec;wire [255:0] active_digest;wire [31:0] active_gen;
 wire unused_b,unused_w,unused_c,unused_s;
 wire fire=req_valid&&req_ready;
 reg [2:0] code;reg [31:0] read_value;
 wire command=fire&&req_write&&(req_addr==12'h000)&&(req_wstrb==4'hf);
 wire bv=command&&(req_wdata==1)&&br,wv=command&&(req_wdata==2)&&wr;
 wire cv=command&&(req_wdata==3)&&cr,sv=command&&(req_wdata==4)&&sr,dv=command&&(req_wdata==5)&&done;
 assign req_ready=!rst&&!rsp_valid;
 always @* begin
   code=0;read_value=0;
   if(req_addr[1:0]!=0)code=1;
   else if(req_write&&req_wstrb!=4'hf)code=2;
   else case(req_addr)
     12'h000:if(!req_write)code=3;else case(req_wdata)
       1:if(!br)code=4;
       2:if(!wr)code=4;
       3:if(!cr)code=4;
       4:if(!sr)code=4;
       5:if(!done)code=4;
       default:code=5;
     endcase
     12'h004:if(req_write)code=3;else read_value={23'b0,ec,err,done,busy,1'b0,prepared,1'b0};
     12'h008:read_value=gen;
     12'h00c:read_value=cmdgen;
     12'h010:read_value=shape;
     12'h014:begin read_value=claim;if(req_write&&req_wdata>1)code=5;end
     12'h018:begin read_value=selector;if(req_write&&req_wdata[31:20]!=0)code=5;end
     12'h01c:read_value=data_word;
     12'h020:if(req_write)code=3;else read_value=active_gen;
     12'h024:if(req_write)code=3;else read_value=native_write_count;
     12'h040,12'h044,12'h048,12'h04c,12'h050,12'h054,12'h058,12'h05c:
       read_value=digest[integer'(req_addr[4:2])*32+:32];
     12'h060,12'h064,12'h068,12'h06c,12'h070,12'h074,12'h078,12'h07c:
       if(req_write)code=3;else read_value=active_digest[integer'(req_addr[4:2])*32+:32];
     default:code=1;
   endcase
 end
 loaded_transition #(.C(C),.H(H)) loader(.clk(clk),.rst(rst),
  .begin_valid(bv),.begin_ready(br),.host_validated(claim[0]),.manifest_digest(digest),.generation(gen),
  .begin_c(shape[15:0]),.begin_h(shape[31:16]),.wr_valid(wv),.wr_ready(wr),
  .wr_role(selector[19:16]),.wr_addr(selector[15:0]),.wr_data(data_word),
  .commit_valid(cv),.commit_ready(cr),.cmd_valid(sv),.cmd_ready(sr),.cmd_generation(cmdgen),
  .prepared(prepared),.busy(busy),.error(err),.error_code(ec),.active_digest(active_digest),.active_generation(active_gen),
  .rsp_valid(done),.rsp_ready(dv),.y_valid(y_valid),.y_ready(y_ready),.y_data(y_data),.y_index(y_index),.y_last(y_last),
  .dbg_begin_fire(unused_b),.dbg_wr_fire(unused_w),.dbg_commit_fire(unused_c),.dbg_core_cmd_fire(unused_s));
 always @(posedge clk)begin
   if(rst)begin
     gen<=0;cmdgen<=0;shape<=0;claim<=0;selector<=0;data_word<=0;digest<=0;
     rsp_valid<=0;rsp_rdata<=0;rsp_code<=0;native_write_count<=0;
   end else begin
     if(rsp_valid&&rsp_ready)rsp_valid<=0;
     if(fire)begin
       rsp_valid<=1;rsp_rdata<=req_write?32'b0:read_value;rsp_code<=code;
       if(req_write&&code==0)case(req_addr)
         12'h000:begin
           if(bv)native_write_count<=0;
           else if(wv)native_write_count<=native_write_count+1;
         end
         12'h008:gen<=req_wdata;
         12'h00c:cmdgen<=req_wdata;
         12'h010:shape<=req_wdata;
         12'h014:claim<=req_wdata;
         12'h018:selector<=req_wdata;
         12'h01c:data_word<=req_wdata;
         12'h040,12'h044,12'h048,12'h04c,12'h050,12'h054,12'h058,12'h05c:
           digest[integer'(req_addr[4:2])*32+:32]<=req_wdata;
         default:begin end
       endcase
     end
   end
 end
endmodule
`default_nettype wire
