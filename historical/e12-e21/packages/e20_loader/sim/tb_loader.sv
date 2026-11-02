`timescale 1ns/1ps
module tb_loader;
    parameter integer FULL=0;
    localparam integer C=(FULL==0)?2:((FULL==1)?16:32),H=(FULL==0)?4:((FULL==1)?32:16),D=2*C,OH=H/2,N=D*OH*OH,NX=C*H*H,NW1=C*D*9,NW2=D*D*9,K1=C*9,K2=D*9;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,begin_valid=0,host_validated=0,wr_valid=0,commit_valid=0,cmd_valid=0,y_ready=0,rsp_ready=0;
    reg [255:0] digest=0;reg [31:0] generation=0,cmd_generation=0,wr_data=0;
    reg [15:0] wr_addr=0,begin_c=16'(C),begin_h=16'(H);reg [3:0] wr_role=0;
    wire begin_ready,wr_ready,commit_ready,cmd_ready,prepared,busy,error,rsp_valid,yv,yl,core_fire;
    wire [2:0] error_code;wire [255:0] active_digest;wire [31:0] active_generation;
    wire signed[7:0] yd;wire[15:0] yi;
    wire unused_begin_fire,unused_wr_fire,unused_commit_fire;
    loaded_transition #(.C(C),.H(H)) dut(.clk(clk),.rst(rst),.begin_valid(begin_valid),.begin_ready(begin_ready),
        .host_validated(host_validated),.manifest_digest(digest),.generation(generation),.begin_c(begin_c),.begin_h(begin_h),
        .wr_valid(wr_valid),.wr_ready(wr_ready),.wr_role(wr_role),.wr_addr(wr_addr),.wr_data(wr_data),
        .commit_valid(commit_valid),.commit_ready(commit_ready),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_generation(cmd_generation),
        .prepared(prepared),.busy(busy),.error(error),.error_code(error_code),.active_digest(active_digest),.active_generation(active_generation),
        .rsp_valid(rsp_valid),.rsp_ready(rsp_ready),.y_valid(yv),.y_ready(y_ready),.y_data(yd),.y_index(yi),.y_last(yl),
        .dbg_begin_fire(unused_begin_fire),.dbg_wr_fire(unused_wr_fire),.dbg_commit_fire(unused_commit_fire),.dbg_core_cmd_fire(core_fire));
    wire load_ready=wr_ready;
    wire[3:0] stage=dut.core.state;
    wire cyf=dut.core.dbg_conv_y_fire,caf=dut.core.dbg_conv_acc_fire,tf=dut.core.dbg_term_fire;
    wire[15:0] cyi=dut.core.dbg_conv_y_index;
    wire signed[7:0] cyd=dut.core.dbg_conv_y_data;
    wire signed[31:0] cad=dut.core.dbg_conv_acc;
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
            if(dut.core.amem[integer'(pending_index)]!==pending_data)$fatal(1,"Y not committed into B");
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
            if(core_fire)begin
                if(active)$fatal(1,"overlap");active=1;
                requests1=0;requests2=0;terms1=0;terms2=0;acc1=0;acc2=0;hcount=0;mcount=0;ycount=0;
            end
            if(active&&load_ready)$fatal(1,"load allowed during block");
            if(dut.core.unused_req_fire)begin
                if(!active||(stage!=2&&stage!=4))$fatal(1,"request outside Conv stage");
                request_no=stage==2?requests1:requests2;ks=stage==2?K1:K2;ih=stage==2?H:OH;ss=stage==2?2:1;
                if(request_no>=N*ks)$fatal(1,"extra request");
                o=request_no/ks;k=request_no%ks;co=o/(OH*OH);oy=(o/OH)%OH;ox=o%OH;
                ci=k/9;ky=(k%9)/3;kx=k%3;iy=oy*ss+ky-1;ix=ox*ss+kx-1;
                expected_pad=(iy<0||iy>=ih||ix<0||ix>=ih);
                if(dut.core.unused_req_tag!={16'(o),16'(k)}||dut.core.wa!=16'(co*ks+k)||dut.core.unused_req_pad!=expected_pad)
                    $fatal(1,"Conv request tag/weight/padding");
                if(dut.core.xe==expected_pad)$fatal(1,"padding RAM read");
                if(dut.core.xe&&dut.core.xa!=16'((ci*ih+iy)*ih+ix))$fatal(1,"Conv input address");
                if(stage==2)requests1=requests1+1;else requests2=requests2+1;
            end
            if(tf)begin
                if(!active||(stage!=2&&stage!=4))$fatal(1,"term outside stage");
                k=stage==2?terms1:terms2;ks=stage==2?K1:K2;
                if(dut.core.unused_term_tag!={16'(k/ks),16'(k%ks)})$fatal(1,"Conv term order");
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
            if(dut.core.core_rsp)begin
                if(stage==2&&(hcount!=N||acc1!=N||terms1!=N*K1||requests1!=N*K1))$fatal(1,"Conv1 early done");
                if(stage==4&&(mcount!=N||acc2!=N||terms2!=N*K2||requests2!=N*K2))$fatal(1,"Conv2 early done");
            end
            if(yv)begin
                if(hcount!=N||mcount!=N||terms2!=N*K2)$fatal(1,"Add before Conv2 drained");
                if(dut.core.skip_q!==skipref[integer'(yi)]||dut.core.main_q!==mref[integer'(yi)])$fatal(1,"Add pair wrong index");
            end
            if(yv&&y_ready)begin
                if(dut.core.skip_zero)zero_checks=zero_checks+1;else read_checks=read_checks+1;
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
    integer errors_checked=0,reset_loads=0;
    always @(posedge clk)if(!rst)begin
        if(!prepared&&cmd_ready)$fatal(1,"command ready before prepared");
        if(error&&(prepared||busy||core_fire||yv||rsp_valid))$fatal(1,"error leaked execution");
        if(core_fire&&(!prepared||active_generation!=cmd_generation||active_digest!=digest))$fatal(1,"wrong transaction started");
        if((busy||rsp_valid)&&(wr_ready||begin_ready||commit_ready))$fatal(1,"writes allowed while executing/responding");
    end
    task automatic require_file(input string p);
        integer f;
        begin f=$fopen(p,"r");if(f==0)$fatal(1,"missing reference file: %s",p);$fclose(f);end
    endtask
    task automatic begin_load(input reg approved,input integer gen);
        begin
            @(negedge clk);host_validated=approved;generation=32'(gen);begin_valid=1;
            while(!begin_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);begin_valid=0;
            if(prepared||cmd_ready)$fatal(1,"begin did not clear preparation");
        end
    endtask
    task automatic put(input integer role,input integer addr,input reg[31:0] data);
        begin
            @(negedge clk);wr_role=4'(role);wr_addr=16'(addr);wr_data=data;wr_valid=1;
            while(!wr_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);wr_valid=0;
        end
    endtask
    task automatic commit_load;
        begin
            @(negedge clk);commit_valid=1;while(!commit_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);commit_valid=0;
        end
    endtask
    task automatic expect_error(input integer code);
        begin
            if(!error||integer'(error_code)!=code||prepared||cmd_ready)$fatal(1,"error expected code=%0d got=%0d",code,error_code);
            repeat(3)@(negedge clk);
            if(!error||core_fire||yv||rsp_valid)$fatal(1,"error not sticky");
            errors_checked=errors_checked+1;$display("REJECT PASS error_code=%0d",code);
        end
    endtask
    reg[255:0] digest_mem[0:0];
    task automatic prepare_case(input integer j,input integer mutation_role);
        string p;integer f,rc,role,addr,row;reg[31:0] data;reg stop;
        begin
            if(FULL==0)p=j==0?"vectors/small_compat/":"vectors/small_varied/";
            else if(FULL==1)p="vectors/stage12_varied/";
            else p="vectors/stage23_varied/";
            require_file({p,"input.hex"});$readmemh({p,"input.hex"},xref);
            require_file({p,"acc1.hex"});$readmemh({p,"acc1.hex"},a1ref);
            require_file({p,"acc2.hex"});$readmemh({p,"acc2.hex"},a2ref);
            require_file({p,"middle.hex"});$readmemh({p,"middle.hex"},href);
            require_file({p,"main.hex"});$readmemh({p,"main.hex"},mref);
            require_file({p,"skip.hex"});$readmemh({p,"skip.hex"},skipref);
            require_file({p,"output.hex"});$readmemh({p,"output.hex"},yref);
            require_file({p,"digest.hex"});$readmemh({p,"digest.hex"},digest_mem);
            digest=digest_mem[0];begin_load(1,FULL==0?100+j:101+FULL);
            require_file({p,"writes.txt"});f=$fopen({p,"writes.txt"},"r");stop=0;row=0;
            while(!$feof(f)&&!stop)begin
                rc=$fscanf(f,"%d %d %h\n",role,addr,data);if(rc!=3)$fatal(1,"malformed writes");
                if(role==mutation_role)begin data=role==5?32'd65536:32'd32;stop=1;end
                put(role,addr,data);row=row+1;
                if(prepared||cmd_ready)$fatal(1,"partial table prepared");
                if(row%41==0)repeat(2)@(negedge clk);
            end
            $fclose(f);
            if(mutation_role<0)begin
                commit_load();
                if(!prepared||!cmd_ready||error)$fatal(1,"complete load not prepared");
            end
        end
    endtask
    task automatic launch(input reg stale);
        begin
            @(negedge clk);cmd_generation=stale?active_generation-1:active_generation;cmd_valid=1;
            while(!cmd_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);cmd_valid=0;
        end
    endtask
    reg[31:0] rng=32'he20e20;
    task automatic finish_job;
        integer guard,last_hold;
        begin
            guard=0;last_hold=6;
            while(!rsp_valid)begin
                @(negedge clk);guard=guard+1;
                if(guard>N*((K1+K2)*4+50))$fatal(1,"timeout");
                rng=(rng<<1)^(rng[31]?32'h04c11db7:0);
                if(yv&&yl&&last_hold>0)begin y_ready=0;last_hold=last_hold-1;end
                else y_ready=rng[1]||rng[4];
            end
            y_ready=0;
            for(integer i=0;i<N;i=i+1)begin
                if(dut.core.amem[i]!==yref[i]||dut.core.fmem[i]!==mref[i])$fatal(1,"stored Y/M");
            end
            for(integer i=0;i<NX;i=i+1)if(dut.core.xmem[i]!==xref[i])$fatal(1,"X overwritten");
            repeat(4)@(negedge clk);rsp_ready=1;@(posedge clk);@(negedge clk);rsp_ready=0;
            if(prepared||cmd_ready)$fatal(1,"old transaction remained prepared");
        end
    endtask
    task automatic reset_now;
        begin
            rst=1;wr_valid=0;begin_valid=0;commit_valid=0;cmd_valid=0;y_ready=0;rsp_ready=0;
            repeat(2)@(negedge clk);rst=0;
            repeat(4)begin @(negedge clk);if(prepared||cmd_ready||yv||rsp_valid||error)$fatal(1,"old state after reset");end
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        if(cmd_ready||prepared)$fatal(1,"ready after reset");
        if(FULL==0)begin
            begin_load(0,90);expect_error(1);
            begin_h=16'(H+2);begin_load(1,91);expect_error(7);begin_h=16'(H);
            begin_load(1,92);put(1,0,0);expect_error(2);
            begin_load(1,93);put(0,1,0);expect_error(3);
            begin_load(1,94);put(0,0,256);expect_error(4);
            begin_load(1,95);put(0,0,0);commit_load();expect_error(5);
            begin_load(1,96);put(0,0,0);put(0,0,0);expect_error(3);
            prepare_case(1,5);expect_error(4);
            prepare_case(1,9);expect_error(4);
            begin_load(1,97);put(0,0,0);reset_now();reset_loads=reset_loads+1;
            prepare_case(0,-1);launch(1);expect_error(6);
        end
        prepare_case(0,-1);launch(0);finish_job();
        if(FULL==0)begin
            prepare_case(1,-1);launch(0);finish_job();
            prepare_case(1,-1);launch(0);while(terms1<9)@(negedge clk);reset_now();
            prepare_case(1,-1);launch(0);finish_job();
            prepare_case(0,-1);launch(0);y_ready=1;while(!rsp_valid)@(negedge clk);reset_now();
            prepare_case(0,-1);launch(0);finish_job();
        end
        if(jobs!=((FULL==0)?4:1)||cancelled!=((FULL==0)?2:0)||errors_checked!=((FULL==0)?10:0))$fatal(1,"test counts");
        $display("PASS full=%0d jobs=%0d cancelled=%0d rejected_transactions=%0d reset_during_load=%0d accepted_terms=%0d accepted_outputs=%0d hold_checks=%0d local_write_checks=%0d",FULL,jobs,cancelled,errors_checked,reset_loads,total_terms,total_outputs,hold_checks,local_write_checks);
        $finish;
    end
    initial begin
        if($test$plusargs("TRACE"))begin $dumpfile("results/small_window.vcd");$dumpvars(0,tb_loader);#100000;$display("TRACE WINDOW ONLY");$finish;end
    end
    initial begin #2000000000;$fatal(1,"global timeout");end
endmodule
