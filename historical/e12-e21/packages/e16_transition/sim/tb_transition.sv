`timescale 1ns/1ps
module tb_transition;
    parameter integer FULL=0;
    localparam integer C=(FULL==0)?2:((FULL==1)?16:32),H=(FULL==0)?4:((FULL==1)?32:16),D=2*C,OH=H/2,N=D*OH*OH,NX=C*H*H,NW1=C*D*9,NW2=D*D*9,K1=C*9,K2=D*9;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,prepared=0,cmd_valid=0,load_we=0,rsp_ready=0,y_ready=0;
    reg [1:0] load_sel=0;reg [15:0] load_addr=0;reg [7:0] load_data=0;
    reg signed [31:0] b1[0:D-1],b2[0:D-1];
    wire cmd_ready,load_ready,busy,rsp_valid,yv,yl,cyf,caf,tf;
    wire [15:0] yi,cyi;wire signed [7:0] yd,cyd;wire signed [31:0] cad;wire [3:0] stage;
    transition_block #(.C(C),.H(H)) dut(.clk(clk),.rst(rst),.prepared(prepared),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.load_we(load_we),.load_sel(load_sel),
        .load_addr(load_addr),.load_data(load_data),.load_ready(load_ready),
        .bias1_cfg(b1),.bias2_cfg(b2),.busy(busy),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),
        .y_valid(yv),.y_ready(y_ready),.y_data(yd),.y_index(yi),.y_last(yl),
        .dbg_stage(stage),.dbg_conv_y_fire(cyf),.dbg_conv_acc_fire(caf),
        .dbg_conv_y_index(cyi),.dbg_conv_y_data(cyd),.dbg_conv_acc(cad),.dbg_term_fire(tf));
    reg [7:0] xref[0:NX-1],w1ref[0:NW1-1],w2ref[0:NW2-1],href[0:N-1],mref[0:N-1],yref[0:N-1];
    reg [7:0] skipref[0:N-1];
    reg [31:0] a1ref[0:N-1],a2ref[0:N-1],b1ref[0:D-1],b2ref[0:D-1];
    integer requests1=0,requests2=0,terms1=0,terms2=0,acc1=0,acc2=0,hcount=0,mcount=0,ycount=0;
    integer jobs=0,cancelled=0,hold_checks=0,negative_checks=0,local_write_checks=0;
    longint total_terms=0,total_outputs=0;
    reg active=0,held=0,rsp_held=0;reg [24:0] payload;
    reg pending_write=0;reg [15:0] pending_index;reg [7:0] pending_data;
    integer request_no,o,k,co,oy,ox,ci,ky,kx,iy,ix,ks,ih,ss;
    integer zero_checks=0,read_checks=0;
    reg expected_pad;
    always @(negedge clk)begin
        if(pending_write)begin
            if(dut.amem[integer'(pending_index)]!==pending_data)$fatal(1,"Y not committed into B");
            pending_write=0;local_write_checks=local_write_checks+1;
        end
    end
    always @(posedge clk)begin
        if(rst)begin
            if(active)cancelled=cancelled+1;
            active=0;held=0;rsp_held=0;pending_write=0;
        end else begin
            if(held)begin if(!yv||payload!=={yl,yi,yd})$fatal(1,"held output changed");hold_checks=hold_checks+1;end
            if(rsp_held&&!rsp_valid)$fatal(1,"held response vanished");
            held=yv&&!y_ready;payload={yl,yi,yd};rsp_held=rsp_valid&&!rsp_ready;
            if(cmd_valid&&cmd_ready)begin
                if(active)$fatal(1,"overlap");active=1;
                requests1=0;requests2=0;terms1=0;terms2=0;acc1=0;acc2=0;hcount=0;mcount=0;ycount=0;
            end
            if(active&&load_ready)$fatal(1,"load allowed during block");
            if(dut.unused_req_fire)begin
                if(!active||(stage!=2&&stage!=4))$fatal(1,"request outside Conv stage");
                request_no=stage==2?requests1:requests2;ks=stage==2?K1:K2;ih=stage==2?H:OH;ss=stage==2?2:1;
                if(request_no>=N*ks)$fatal(1,"extra request");
                o=request_no/ks;k=request_no%ks;co=o/(OH*OH);oy=(o/OH)%OH;ox=o%OH;
                ci=k/9;ky=(k%9)/3;kx=k%3;iy=oy*ss+ky-1;ix=ox*ss+kx-1;
                expected_pad=(iy<0||iy>=ih||ix<0||ix>=ih);
                if(dut.unused_req_tag!={16'(o),16'(k)}||dut.wa!=16'(co*ks+k)||dut.unused_req_pad!=expected_pad)
                    $fatal(1,"Conv request tag/weight/padding");
                if(dut.xe==expected_pad)$fatal(1,"padding RAM read");
                if(dut.xe&&dut.xa!=16'((ci*ih+iy)*ih+ix))$fatal(1,"Conv input address");
                if(stage==2)requests1=requests1+1;else requests2=requests2+1;
            end
            if(tf)begin
                if(!active||(stage!=2&&stage!=4))$fatal(1,"term outside stage");
                k=stage==2?terms1:terms2;ks=stage==2?K1:K2;
                if(dut.unused_term_tag!={16'(k/ks),16'(k%ks)})$fatal(1,"Conv term order");
                if(stage==2)terms1=terms1+1;else terms2=terms2+1;
                total_terms=total_terms+1;
            end
            if(caf)begin
                if(stage==2)begin
                    if(acc1>=N||cad!==a1ref[acc1])$fatal(1,"Conv1 wide acc %0d",acc1);acc1=acc1+1;
                end else if(stage==4)begin
                    if(acc2>=N||cad!==a2ref[acc2])$fatal(1,"Conv2 wide acc %0d",acc2);acc2=acc2+1;
                end else $fatal(1,"acc outside stage");
            end
            if(cyf)begin
                if(stage==2)begin
                    if(hcount>=N||integer'(cyi)!=hcount||cyd!==href[hcount])$fatal(1,"H mismatch");hcount=hcount+1;
                end else if(stage==4)begin
                    if(mcount>=N||integer'(cyi)!=mcount||cyd!==mref[mcount])$fatal(1,"M mismatch/ReLU before Add");mcount=mcount+1;
                end else $fatal(1,"Conv output outside stage");
            end
            if(dut.core_rsp)begin
                if(stage==2&&(hcount!=N||acc1!=N||terms1!=N*K1||requests1!=N*K1))$fatal(1,"Conv1 early done");
                if(stage==4&&(mcount!=N||acc2!=N||terms2!=N*K2||requests2!=N*K2))$fatal(1,"Conv2 early done");
            end
            if(yv)begin
                if(hcount!=N||mcount!=N||terms2!=N*K2)$fatal(1,"Add before Conv2 drained");
                if(dut.skip_q!==skipref[integer'(yi)]||dut.main_q!==mref[integer'(yi)])$fatal(1,"Add pair wrong index");
            end
            if(yv&&y_ready)begin
                if(dut.skip_zero)zero_checks=zero_checks+1;else read_checks=read_checks+1;
                if(!active||ycount>=N||integer'(yi)!=ycount||yd!==yref[ycount]||yl!=(ycount==N-1))$fatal(1,"Y mismatch %0d",ycount);
                if($signed(mref[ycount])<0&&$signed(skipref[ycount])>0)negative_checks=negative_checks+1;
                pending_write=1;pending_index=yi;pending_data=yd;
                ycount=ycount+1;total_outputs=total_outputs+1;
            end
            if(rsp_valid)begin
                if(!active||ycount!=N||acc1!=N||acc2!=N||cmd_ready||busy)$fatal(1,"block completion boundary");
            end
            if(rsp_valid&&rsp_ready)begin active=0;jobs=jobs+1;
                $display("BLOCK PASS full=%0d job=%0d Conv1_terms=%0d Conv2_terms=%0d H=%0d M=%0d Y=%0d",FULL,jobs,terms1,terms2,hcount,mcount,ycount);
            end
        end
    end
    task automatic require_file(input string name);
        integer fd;
        begin
            fd=$fopen(name,"r");
            if(fd==0)$fatal(1,"missing reference file: %s",name);
            $fclose(fd);
        end
    endtask
    task automatic prepare_case(input integer j);
        string p;
        begin
            @(negedge clk);prepared=0;
            if(FULL==1)p=$sformatf("reference/stage12/job%0d/",j);
            else if(FULL==2)p=$sformatf("reference/stage23/job%0d/",j);
            else p=$sformatf("reference/small/job%0d/",j);
            require_file({p,"input.hex"});$readmemh({p,"input.hex"},xref);require_file({p,"weight1.hex"});$readmemh({p,"weight1.hex"},w1ref);require_file({p,"weight2.hex"});$readmemh({p,"weight2.hex"},w2ref);
            require_file({p,"bias1.hex"});$readmemh({p,"bias1.hex"},b1ref);require_file({p,"bias2.hex"});$readmemh({p,"bias2.hex"},b2ref);
            require_file({p,"acc1.hex"});$readmemh({p,"acc1.hex"},a1ref);require_file({p,"acc2.hex"});$readmemh({p,"acc2.hex"},a2ref);
            require_file({p,"middle.hex"});$readmemh({p,"middle.hex"},href);require_file({p,"main.hex"});$readmemh({p,"main.hex"},mref);require_file({p,"output.hex"});$readmemh({p,"output.hex"},yref);
            for(integer i=0;i<D;i=i+1)begin b1[i]=$signed(b1ref[i]);b2[i]=$signed(b2ref[i]);end
            require_file({p,"skip.hex"});$readmemh({p,"skip.hex"},skipref);
            for(integer i=0;i<NX;i=i+1)begin
                @(negedge clk);if(!load_ready)$fatal(1,"load not ready");
                load_we=1;load_sel=0;load_addr=16'(i);load_data=xref[i];
            end
            for(integer i=0;i<NW1;i=i+1)begin @(negedge clk);load_we=1;load_sel=1;load_addr=16'(i);load_data=w1ref[i];end
            for(integer i=0;i<NW2;i=i+1)begin @(negedge clk);load_we=1;load_sel=2;load_addr=16'(i);load_data=w2ref[i];end
            @(negedge clk);load_we=0;prepared=1;
        end
    endtask
    task automatic launch;
        begin @(negedge clk);cmd_valid=1;while(!cmd_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);cmd_valid=0;end
    endtask
    reg [31:0] rng=32'he14e14;
    task automatic finish_job;
        integer guard,last_hold;
        begin
            guard=0;last_hold=6;
            while(!rsp_valid)begin
                @(negedge clk);guard=guard+1;
                if(guard>N*((K1+K2)*4+50))$fatal(1,"block timeout");
                rng=(rng<<1)^(rng[31]?32'h04c11db7:0);
                for(integer i=0;i<D;i=i+1)begin b1[i]=9999;b2[i]=-9999;end
                if(yv&&yl&&last_hold>0)begin y_ready=0;last_hold=last_hold-1;end
                else y_ready=rng[1]||rng[4];
            end
            y_ready=0;
            for(integer i=0;i<N;i=i+1)begin
                
                if(dut.amem[i]!==yref[i])$fatal(1,"B role change H->Y failed");
                if(dut.fmem[i]!==mref[i])$fatal(1,"M storage");
            end
            for(integer i=0;i<NX;i=i+1)if(dut.xmem[i]!==xref[i])$fatal(1,"X overwritten");
            repeat(4)@(negedge clk);rsp_ready=1;
            @(posedge clk);@(negedge clk);rsp_ready=0;
            if(!cmd_ready)$fatal(1,"not idle");
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        cmd_valid=1;repeat(3)@(negedge clk);if(cmd_ready||busy)$fatal(1,"prepared gate");cmd_valid=0;
        for(integer j=0;j<((FULL!=0)?1:4);j=j+1)begin prepare_case(j);launch();finish_job();end
        if(FULL==0)begin
            // Repeat without reloading X/W; H and Y share B across jobs.
            prepare_case(1);launch();finish_job();
            for(integer i=0;i<D;i=i+1)begin b1[i]=$signed(b1ref[i]);b2[i]=$signed(b2ref[i]);end
            launch();finish_job();
            for(integer r=0;r<5;r=r+1)begin
                prepare_case(1);y_ready=0;launch();
                case(r)
                    0:while(terms1<9)@(negedge clk);
                    1:while(terms2<9)@(negedge clk);
                    2:while(stage!=6)@(negedge clk);
                    3:while(!yv)@(negedge clk);
                    4:begin y_ready=1;while(!rsp_valid)@(negedge clk);end
                endcase
                rst=1;prepared=0;cmd_valid=0;y_ready=0;rsp_ready=0;load_we=0;
                repeat(2)@(negedge clk);rst=0;
                repeat(4)begin @(negedge clk);if(yv||rsp_valid||cmd_ready)$fatal(1,"stale result");end
            end
            prepare_case(1);launch();finish_job();
        end
        if(jobs!=((FULL!=0)?1:7)||cancelled!=((FULL!=0)?0:5)||negative_checks==0)$fatal(1,"test count/witness");
        $display("PASS full=%0d jobs=%0d cancelled=%0d accepted_terms=%0d accepted_outputs=%0d hold_checks=%0d negative_main_checks=%0d local_write_checks=%0d zero_tokens=%0d skip_reads=%0d",FULL,jobs,cancelled,total_terms,total_outputs,hold_checks,negative_checks,local_write_checks,zero_checks,read_checks);
        $finish;
    end
    initial begin
        if($test$plusargs("TRACE"))begin
            $dumpfile("results/small_block_window.vcd");$dumpvars(0,tb_transition);
            #100000;$display("TRACE WINDOW ONLY: not a full regression");$finish;
        end
    end
    initial begin #2000000000;$fatal(1,"global timeout");end
endmodule
