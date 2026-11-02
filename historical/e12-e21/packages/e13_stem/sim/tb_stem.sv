`timescale 1ns/1ps
module tb_stem;
    parameter integer TINY=0;
    localparam integer CIN=(TINY!=0)?2:3,COUT=(TINY!=0)?2:16,H=(TINY!=0)?4:32,W=H,PAD=(TINY!=0)?0:1;
    localparam integer OH=H+2*PAD-2,OW=W+2*PAD-2,K=CIN*9,NOUT=COUT*OH*OW;
    localparam integer NX=CIN*H*W,NW=COUT*K,NC=(TINY!=0)?2:4;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,prepared=0,cmd_valid=0,relu_mode=0,y_ready=0,rsp_ready=0;
    reg signed [31:0] bias_cfg[0:COUT-1];
    wire cmd_ready,busy,rsp_valid,xe,we,yv,yl,rf,rp,tf,tp,af;
    wire [15:0] xa,wa,yi;wire [31:0] rt,tt;
    wire signed [7:0] yd;wire signed [31:0] ad;
    reg [7:0] xd=0,wd=0,xmem[0:NX-1],wmem[0:NW-1],gold_y[0:NOUT-1];
    reg [31:0] gold_acc[0:NOUT-1],bias_mem[0:COUT-1];
    conv3x3_core #(.CIN(CIN),.COUT(COUT),.H(H),.W(W),.PAD(PAD)) dut(
        .clk(clk),.rst(rst),.prepared(prepared),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),
        .relu_mode(relu_mode),.bias_cfg(bias_cfg),.busy(busy),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),
        .x_ram_en(xe),.x_ram_addr(xa),.x_ram_data(xd),.w_ram_en(we),.w_ram_addr(wa),.w_ram_data(wd),
        .y_valid(yv),.y_ready(y_ready),.y_data(yd),.y_index(yi),.y_last(yl),
        .dbg_req_fire(rf),.dbg_req_pad(rp),.dbg_term_fire(tf),.dbg_term_pad(tp),
        .dbg_acc_fire(af),.dbg_req_tag(rt),.dbg_term_tag(tt),.dbg_acc_data(ad));
    always @(posedge clk)begin
        if(xe)begin if(integer'(xa)>=NX)$fatal(1,"input address OOB");xd<=xmem[integer'(xa)];end
        if(we)begin if(integer'(wa)>=NW)$fatal(1,"weight address OOB");wd<=wmem[integer'(wa)];end
    end
    integer reqs=0,terms=0,accs=0,outs=0,reads=0,pads=0,jobs=0,cancelled=0;
    longint total_terms=0,total_outputs=0,total_pads=0,total_reads=0;
    integer holds=0,corner=0,edge_count=0,interior=0;
    reg active=0,held=0,rsp_held=0;reg [24:0] payload;
    integer o,k,co,oy,ox,ci,ky,kx,iy,ix,expected_pad,expected_addr;
    always @(posedge clk)begin
        if(rst)begin
            if(active)cancelled=cancelled+1;
            active=0;reqs=0;terms=0;accs=0;outs=0;reads=0;pads=0;held=0;rsp_held=0;
        end else begin
            if(held)begin
                if(!yv||{yl,yi,yd}!==payload)$fatal(1,"output hold");holds=holds+1;
            end
            if(rsp_held&&!rsp_valid)$fatal(1,"response hold");
            held=yv&&!y_ready;payload={yl,yi,yd};rsp_held=rsp_valid&&!rsp_ready;
            if(cmd_valid&&cmd_ready)begin
                if(active)$fatal(1,"overlapping command");
                active=1;reqs=0;terms=0;accs=0;outs=0;reads=0;pads=0;
                corner=0;edge_count=0;interior=0;
            end
            if(xe&&!rf)$fatal(1,"stray input request");
            if(we!=rf)$fatal(1,"weight request missing/duplicate");
            if(rf)begin
                if(!active||reqs>=NOUT*K)$fatal(1,"unexpected logical request");
                o=reqs/K;k=reqs%K;co=o/(OH*OW);oy=(o/OW)%OH;ox=o%OW;
                ci=k/9;ky=(k%9)/3;kx=k%3;iy=oy+ky-PAD;ix=ox+kx-PAD;
                expected_pad=(iy<0||iy>=H||ix<0||ix>=W)?1:0;
                expected_addr=(ci*H+iy)*W+ix;
                if(rt!={16'(o),16'(k)}||integer'(wa)!=co*K+k||integer'(rp)!=expected_pad)
                    $fatal(1,"request tag/weight/padding mismatch term=%0d",reqs);
                if(xe==1'(expected_pad))$fatal(1,"RAM read on padding or missing real read");
                if(xe)begin
                    if(integer'(xa)!=expected_addr)$fatal(1,"input address mismatch");
                    reads=reads+1;total_reads=total_reads+1;
                end else begin pads=pads+1;total_pads=total_pads+1;end
                reqs=reqs+1;
            end
            if(tf)begin
                if(!active||terms>=NOUT*K||tt!={16'(terms/K),16'(terms%K)})$fatal(1,"term tag/order");
                o=terms/K;k=terms%K;oy=(o/OW)%OH;ox=o%OW;
                iy=oy+(k%9)/3-PAD;ix=ox+k%3-PAD;
                if(tp!=(iy<0||iy>=H||ix<0||ix>=W))$fatal(1,"term pad tag");
                if(tp&&dut.mac.x!==8'sd0)$fatal(1,"padding is not integer zero");
                terms=terms+1;total_terms=total_terms+1;
            end
            if(af)begin
                if(accs>=NOUT||ad!==gold_acc[accs])$fatal(1,"wide acc index=%0d got=%0d expected=%0d",accs,ad,$signed(gold_acc[accs]));
                accs=accs+1;
            end
            if(yv&&y_ready)begin
                if(!active||outs>=NOUT||integer'(yi)!=outs||yd!==gold_y[outs]||yl!=(outs==NOUT-1))
                    $fatal(1,"output mismatch index=%0d got=%0d expected=%0d",outs,yd,$signed(gold_y[outs]));
                oy=(outs/OW)%OH;ox=outs%OW;
                if((oy==0||oy==OH-1)&&(ox==0||ox==OW-1))corner=corner+1;
                else if(oy==0||oy==OH-1||ox==0||ox==OW-1)edge_count=edge_count+1;
                else interior=interior+1;
                outs=outs+1;total_outputs=total_outputs+1;
            end
            if(rsp_valid)begin
                if(!active||reqs!=NOUT*K||terms!=NOUT*K||accs!=NOUT||outs!=NOUT||reads+pads!=NOUT*K)
                    $fatal(1,"completion boundary");
                if((TINY==0)&&(pads!=18240||reads!=424128||corner!=64||edge_count!=1920||interior!=14400))
                    $fatal(1,"geometry coverage");
                if(cmd_ready||busy)$fatal(1,"response state");
            end
            if(rsp_valid&&rsp_ready)begin
                $display("JOB PASS tiny=%0d job=%0d terms=%0d outputs=%0d valid_reads=%0d padding=%0d corners=%0d edges=%0d interior=%0d",TINY,jobs,terms,outs,reads,pads,corner,edge_count,interior);
                active=0;jobs=jobs+1;
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
        string path;
        begin
            path=$sformatf("reference/%s/job%0d/",(TINY!=0)?"tiny":"stem",j);
            require_file({path,"input.hex"});$readmemh({path,"input.hex"},xmem);require_file({path,"weight.hex"});$readmemh({path,"weight.hex"},wmem);
            require_file({path,"bias.hex"});$readmemh({path,"bias.hex"},bias_mem);require_file({path,"acc.hex"});$readmemh({path,"acc.hex"},gold_acc);require_file({path,"output.hex"});$readmemh({path,"output.hex"},gold_y);
            for(integer i=0;i<COUT;i=i+1)bias_cfg[i]=$signed(bias_mem[i]);
            relu_mode=(TINY!=0)?1'(j):1'(j==2);prepared=1;
        end
    endtask
    task automatic launch;
        begin
            @(negedge clk);cmd_valid=1;
            while(!cmd_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);cmd_valid=0;
        end
    endtask
    reg [31:0] rng=32'h13a513a5;
    task automatic finish_job;
        integer guard,last_hold;
        begin
            guard=0;last_hold=7;
            while(!rsp_valid)begin
                @(negedge clk);guard=guard+1;
                if(guard>NOUT*(K*4+25))$fatal(1,"timeout");
                rng=(rng<<1)^((rng[31])?32'h04c11db7:32'd0);
                // Alter live inputs after command latch; no new command is pending.
                for(integer i=0;i<COUT;i=i+1)bias_cfg[i]=9999;
                relu_mode=~relu_mode;
                if(yv&&yl&&last_hold>0)begin y_ready=0;last_hold=last_hold-1;end
                else y_ready=rng[0]||rng[3];
            end
            y_ready=0;
            repeat(4)@(negedge clk);
            rsp_ready=1;@(posedge clk);@(negedge clk);rsp_ready=0;
            if(!cmd_ready)$fatal(1,"not idle");
        end
    endtask
    task automatic reset_cancel;
        begin
            rst=1;prepared=0;cmd_valid=0;y_ready=0;rsp_ready=0;
            repeat(2)@(negedge clk);rst=0;
            repeat(4)begin @(negedge clk);if(yv||rsp_valid||cmd_ready)$fatal(1,"stale valid after reset");end
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        cmd_valid=1;repeat(3)@(negedge clk);
        if(cmd_ready||busy)$fatal(1,"prepared gate");cmd_valid=0;
        for(integer j=0;j<NC;j=j+1)begin prepare_case(j);launch();finish_job();end
        if((TINY==0))begin
            // Cancel padded read pending, valid read pending, middle dot, held y, held response.
            for(integer r=0;r<5;r=r+1)begin
                prepare_case(1);y_ready=0;launch();
                case(r)
                    0:while(!(dut.wr.state==1&&dut.pad_q))@(negedge clk);
                    1:while(!(dut.xr.state==1&&!dut.pad_q))@(negedge clk);
                    2:while(terms<14)@(negedge clk);
                    3:while(!yv)@(negedge clk);
                    4:begin y_ready=1;while(!rsp_valid)@(negedge clk);end
                endcase
                reset_cancel();
            end
            prepare_case(1);launch();finish_job();
        end
        if(jobs!=((TINY!=0)?2:5)||cancelled!=((TINY!=0)?0:5))$fatal(1,"test count");
        $display("PASS tiny=%0d jobs=%0d cancelled=%0d accepted_terms=%0d accepted_outputs=%0d real_reads=%0d padding_terms=%0d hold_checks=%0d",TINY,jobs,cancelled,total_terms,total_outputs,total_reads,total_pads,holds);
        $finish;
    end
    initial begin
        if($test$plusargs("TRACE"))begin
            $dumpfile((TINY!=0)?"results/tiny.vcd":"results/stem_first_window.vcd");$dumpvars(0,tb_stem);
            #40000;$display("TRACE WINDOW ONLY: not a full regression");$finish;
        end
    end
    initial begin #2000000000;$fatal(1,"global timeout");end
endmodule
