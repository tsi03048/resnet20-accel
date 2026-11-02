`timescale 1ns/1ps
module tb_mmio;
 parameter integer FULL=0;
 localparam integer C=(FULL!=0)?16:2,H=(FULL!=0)?32:4,N=2*C*(H/2)*(H/2);
 reg clk=0;always #5 clk=~clk;
 reg rst=1,qv=0,qw=0,rr=0,yr=0;reg[11:0]qa=0;reg[31:0]qd=0;reg[3:0]qs=15;
 wire qr,rv,yv,yl;wire[31:0]rd;wire[2:0]rc;wire signed[7:0]yd;wire[15:0]yi;
 mmio_transition #(.C(C),.H(H)) dut(.clk(clk),.rst(rst),.req_valid(qv),.req_ready(qr),.req_write(qw),.req_addr(qa),.req_wdata(qd),.req_wstrb(qs),.rsp_valid(rv),.rsp_ready(rr),.rsp_rdata(rd),.rsp_code(rc),.y_valid(yv),.y_ready(yr),.y_data(yd),.y_index(yi),.y_last(yl));
 integer transactions=0,rejections=0,holds=0,starts=0,writes=0,outputs=0,jobs=0;
 reg[7:0]expected[0:N-1];reg[255:0]dg[0:0];string folder;reg running=0;
 always @(posedge clk)if(!rst)begin
   if(dut.unused_s)starts=starts+1;
   if(dut.unused_w)writes=writes+1;
   if(yv&&yr)begin
     if(!running||integer'(yi)!=outputs||yd!==expected[outputs]||yl!=(outputs==N-1))$fatal(1,"output %0d",outputs);
     outputs=outputs+1;
   end
 end
 task automatic tick;@(posedge clk);#1;endtask
 task automatic reset_dut;
   @(negedge clk);rst=1;qv=0;rr=0;yr=0;repeat(3)tick();@(negedge clk);rst=0;tick();
 endtask
 task automatic bus(input bit w,input reg[11:0]a,input reg[31:0]d,input reg[3:0]st,input integer expcode,input integer stall,output reg[31:0]value);
   reg[31:0]saved;reg[2:0]savedcode;
   @(negedge clk);qv=1;qw=w;qa=a;qd=d;qs=st;rr=0;
   if(!qr)$fatal(1,"unexpected request backpressure");tick();
   if(!rv||integer'(rc)!=expcode)$fatal(1,"response addr=%h expected=%0d actual=%0d",a,expcode,rc);
   saved=rd;savedcode=rc;transactions=transactions+1;if(expcode!=0)rejections=rejections+1;
   // Keep original request asserted while response is stalled: no replay permitted.
   repeat(stall)begin tick();if(qr||!rv||rd!==saved||rc!==savedcode)$fatal(1,"response hold");holds=holds+1;end
   value=rd;@(negedge clk);qv=0;rr=1;tick();@(negedge clk);rr=0;
 endtask
 reg[31:0]v;
 task automatic put(input reg[11:0]a,input reg[31:0]d);bus(1,a,d,15,0,0,v);endtask
 task automatic get(input reg[11:0]a);bus(0,a,0,15,0,1,v);endtask
 task automatic begin_load;
   put('h008,100);put('h00c,100);put('h010,(32'(H)<<16)|32'(C));put('h014,1);
   for(integer i=0;i<8;i=i+1)put(12'('h040+i*4),dg[0][i*32+:32]);
   bus(1,0,1,15,0,5,v);get('h020);if(v!=100)$fatal(1,"active generation");
   for(integer i=0;i<8;i=i+1)begin get(12'('h060+i*4));if(v!==dg[0][i*32+:32])$fatal(1,"active digest");end
 endtask
 task automatic fill;
   integer f,rcount,role,addr,count;reg[31:0]word;
   f=$fopen({folder,"/writes.txt"},"r");if(f==0)$fatal(1,"fixture missing");count=0;
   while(!$feof(f))begin
     rcount=$fscanf(f,"%d %d %h\n",role,addr,word);
     if(rcount==3)begin
       put('h018,(32'(role)<<16)|32'(addr));put('h01c,word);
       bus(1,0,2,15,0,(count%97==0)?3:0,v);count=count+1;
     end else $fatal(1,"malformed fixture");
   end
   $fclose(f);get('h024);if(v!=32'(count))$fatal(1,"write count duplicate");
 endtask
 task automatic execute_job;
   begin_load();fill();put(0,3);get(4);if(!v[1]||v[5])$fatal(1,"not prepared");
   running=1;outputs=0;bus(1,0,4,15,0,7,v);
   bus(1,0,1,15,4,2,v); // Begin while RUN: explicit reject, no deadlock
   bus(1,0,2,15,4,2,v);
   put('h008,999);get('h020);if(v!=100)$fatal(1,"shadow modified active");
   // deterministic output stalls, including final beat
   while(outputs<N)begin @(negedge clk);yr=($time%70!=0)&&($time%110!=0);tick();end
   @(negedge clk);yr=0;running=0;
   get(4);while(!v[4])get(4);
   bus(1,0,1,15,4,3,v);bus(1,0,5,15,0,6,v);get(4);if(v[4]||v[1]||v[3])$fatal(1,"ack not idle");jobs=jobs+1;
 endtask
 initial begin
   folder=(FULL!=0)?"vectors/stage12_varied":"vectors/small_compat";
   $readmemh({folder,"/digest.hex"},dg);$readmemh({folder,"/output.hex"},expected);
   reset_dut();get(4);if(v!=0)$fatal(1,"reset status");
   bus(1,1,0,15,1,2,v);bus(0,'h080,0,15,1,2,v);bus(1,8,1,3,2,2,v);
   bus(1,4,0,15,3,2,v);bus(0,0,0,15,3,2,v);bus(1,0,9,15,5,2,v);
   bus(1,0,4,15,4,2,v);bus(1,'h014,2,15,5,2,v);bus(1,'h018,'h100000,15,5,2,v);
   begin_load();put(0,3);get(4);if(!v[5]||v[8:6]!=5)$fatal(1,"incomplete commit not semantic error");
   begin_load();put('h018,0);put('h01c,256);put(0,2);get(4);if(!v[5]||v[8:6]!=4)$fatal(1,"range not semantic error");
   // Reset with an unconsumed bus response and partial Loader session.
   begin_load();@(negedge clk);qv=1;qw=1;qa=8;qd=123;qs=15;tick();if(!rv)$fatal(1,"missing pending");
   reset_dut();if(rv)$fatal(1,"stale response after reset");get(8);if(v!=0)$fatal(1,"shadow reset");get('h020);if(v!=0)$fatal(1,"identity reset");
   execute_job();
   if(FULL==0)begin folder="vectors/small_varied";$readmemh({folder,"/digest.hex"},dg);$readmemh({folder,"/output.hex"},expected);execute_job();end
   if(FULL==0)begin
     begin_load();fill();put(0,3);put('h00c,99);put(0,4);get(4);
     if(!v[5]||v[8:6]!=6)$fatal(1,"generation not semantic error");
   end
   if(starts!=jobs)$fatal(1,"duplicate Start");
   $display("PASS FULL=%0d jobs=%0d starts=%0d transactions=%0d bus_rejections=%0d held_response_cycles=%0d native_writes=%0d",FULL,jobs,starts,transactions,rejections,holds,writes);$finish;
 end
 initial begin #2000000000;$fatal(1,"timeout");end
endmodule
