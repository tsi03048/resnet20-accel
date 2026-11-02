`timescale 1ns/1ps
module tb_conv_fixed;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,prepared=0,cmd_valid=0,relu_mode=0,rsp_ready=0,y_ready=0;
    reg signed [31:0] bias0=3,bias1=-1;
    wire cmd_ready,busy,rsp_valid,x_en,w_en,y_valid,y_last;
    wire [4:0] xa;wire [5:0] wa;
    reg [7:0] xd=0,wd=0,xmem[0:31],wmem[0:35];
    wire signed [7:0] y_data;wire [2:0] y_index;
    wire req_fire,term_fire,acc_fire;wire [7:0] req_tag,term_tag;
    wire signed [31:0] acc_data;
    conv_fixed_top dut(.clk(clk),.rst(rst),.prepared(prepared),.cmd_valid(cmd_valid),
        .cmd_ready(cmd_ready),.relu_mode(relu_mode),.bias0(bias0),.bias1(bias1),
        .busy(busy),.rsp_valid(rsp_valid),.rsp_ready(rsp_ready),
        .x_ram_en(x_en),.x_ram_addr(xa),.x_ram_data(xd),
        .w_ram_en(w_en),.w_ram_addr(wa),.w_ram_data(wd),
        .y_valid(y_valid),.y_ready(y_ready),.y_data(y_data),.y_index(y_index),.y_last(y_last),
        .dbg_req_fire(req_fire),.dbg_term_fire(term_fire),.dbg_acc_fire(acc_fire),
        .dbg_req_tag(req_tag),.dbg_term_tag(term_tag),.dbg_acc_data(acc_data));
    always @(posedge clk) begin
        if(x_en) begin if(integer'(xa)>=32)$fatal(1,"input address");xd<=xmem[xa];end
        if(w_en) begin if(wa>=36)$fatal(1,"weight address");wd<=wmem[wa];end
    end

    integer exp_acc[0:7],exp_y[0:7];
    integer req_count=0,term_count=0,acc_count=0,out_count=0;
    integer jobs=0,cancels=0,total_terms=0,total_outputs=0,hold_checks=0;
    reg active=0,old_hold=0,old_rsp_hold=0;
    reg [11:0] held_y;
    integer o,k,ci,ky,kx,oy,ox,ex,ew;
    function automatic integer signed8(input reg [7:0] v);
        signed8=v[7]?integer'(v)-256:integer'(v);
    endfunction
    function automatic integer rne_ref(input integer a);
        longint signed mag;integer q,r;
        begin
            mag=longint'(a);if(mag<0)mag=-mag;
            q=integer'(mag/4);r=integer'(mag%4);
            if(r>2||(r==2&&(q%2)!=0))q=q+1;
            rne_ref=a<0?-q:q;
        end
    endfunction
    function automatic integer post_ref(input integer a,input reg relu_en);
        integer q;
        begin q=rne_ref(a);if(relu_en&&q<0)q=0;
            if(q>127)q=127;if(q<(-128))q=-128;post_ref=q;end
    endfunction

    always @(posedge clk) begin
        if(rst) begin
            if(active)cancels=cancels+1;
            active=0;req_count=0;term_count=0;acc_count=0;out_count=0;
            old_hold=0;old_rsp_hold=0;
        end else begin
            if(old_hold) begin
                if(!y_valid||{y_last,y_index,y_data}!==held_y)$fatal(1,"unstable y payload");
                hold_checks=hold_checks+1;
            end
            if(old_rsp_hold&&!rsp_valid)$fatal(1,"response vanished");
            old_hold=y_valid&&!y_ready;held_y={y_last,y_index,y_data};
            old_rsp_hold=rsp_valid&&!rsp_ready;
            if(cmd_valid&&cmd_ready) begin
                if(active)$fatal(1,"overlapping command");
                active=1;req_count=0;term_count=0;acc_count=0;out_count=0;
            end
            if(req_fire) begin
                if(!active||req_count>=144)$fatal(1,"unexpected request");
                o=req_count/18;k=req_count%18;ci=k/9;ky=(k%9)/3;kx=k%3;
                oy=(o%4)/2;ox=o%2;
                ex=(ci*4+oy+ky)*4+ox+kx;ew=(o/4)*18+k;
                if(integer'(xa)!=ex||integer'(wa)!=ew||integer'(req_tag)!=(o*32+k))
                    $fatal(1,"request mismatch %0d x=%0d/%0d w=%0d/%0d",req_count,xa,ex,wa,ew);
                req_count=req_count+1;
            end
            if(term_fire) begin
                if(!active||term_count>=144)$fatal(1,"unexpected term");
                if(integer'(term_tag)!=((term_count/18)*32+term_count%18))$fatal(1,"term tag mismatch");
                term_count=term_count+1;total_terms=total_terms+1;
            end
            if(acc_fire) begin
                if(acc_count>=8||$signed(acc_data)!=exp_acc[acc_count])
                    $fatal(1,"wide acc mismatch %0d actual=%0d expected=%0d",acc_count,$signed(acc_data),exp_acc[acc_count]);
                acc_count=acc_count+1;
            end
            if(y_valid&&y_ready) begin
                if(!active||out_count>=8||integer'(y_index)!=out_count||integer'($signed(y_data))!=exp_y[out_count]||y_last!=(out_count==7))
                    $fatal(1,"output mismatch %0d actual=%0d expected=%0d",out_count,$signed(y_data),exp_y[out_count]);
                if(jobs<2)$display("OUTPUT job=%0d index=%0d code=%0d last=%0d",jobs,out_count,$signed(y_data),y_last);
                out_count=out_count+1;total_outputs=total_outputs+1;
            end
            if(rsp_valid) begin
                if(!active||out_count!=8||acc_count!=8||req_count!=144||term_count!=144)
                    $fatal(1,"early/missing completion");
                if(cmd_ready)$fatal(1,"command accepted before response consumed");
            end
            if(rsp_valid&&rsp_ready) begin jobs=jobs+1;active=0;end
        end
    end

    task automatic prepare_case(input integer mode);
        integer i,j,co,yy,xx,a;
        begin
            for(i=0;i<32;i=i+1) begin
                if(mode==0)xmem[i]=8'(i<16?i+1:2);
                else if(mode==1)xmem[i]=8'($urandom_range(0,24)-12);
                else xmem[i]=8'h7f;
            end
            for(i=0;i<36;i=i+1) begin
                if(mode==0)wmem[i]=8'(i<18?(i<9?1:-1):(i<27?-1:2));
                else if(mode==1)wmem[i]=8'($urandom_range(0,8)-4);
                else wmem[i]=8'h7f;
            end
            bias0=mode==1?32'($urandom_range(0,64)-32):3;
            bias1=mode==1?32'($urandom_range(0,64)-32):-1;
            for(co=0;co<2;co=co+1)for(yy=0;yy<2;yy=yy+1)for(xx=0;xx<2;xx=xx+1)begin
                a=co==0?bias0:bias1;
                for(i=0;i<2;i=i+1)for(j=0;j<9;j=j+1)
                    a=a+signed8(xmem[(i*4+yy+j/3)*4+xx+j%3])*signed8(wmem[co*18+i*9+j]);
                exp_acc[co*4+yy*2+xx]=a;
                exp_y[co*4+yy*2+xx]=post_ref(a,relu_mode);
            end
            prepared=1;
        end
    endtask
    task automatic launch;
        begin
            @(negedge clk);cmd_valid=1;
            while(!cmd_ready)@(negedge clk);
            @(posedge clk);@(negedge clk);cmd_valid=0;
        end
    endtask
    task automatic finish_job;
        integer guard,last_hold;
        begin
            guard=0;last_hold=6;
            while(!rsp_valid)begin
                @(negedge clk);guard=guard+1;
                if(guard>5000)$fatal(1,"job timeout");
                // Change unpresented live configuration after command latch.
                bias0=999;bias1=-999;relu_mode=~relu_mode;
                cmd_valid=0;
                if(y_valid&&y_last&&last_hold>0)begin y_ready=0;last_hold=last_hold-1;end
                else y_ready=($urandom_range(0,3)!=0);
            end
            y_ready=0;cmd_valid=0;
            repeat(4)@(negedge clk);
            if(cmd_ready||busy)$fatal(1,"response/idle contract");
            cmd_valid=0;rsp_ready=1;
            @(posedge clk);@(negedge clk);rsp_ready=0;
            if(!cmd_ready)$fatal(1,"not idle after response");
        end
    endtask

    reg mtv=0,mfirst=0,mlast=0,mar=0;
    reg signed[7:0] mx=0,mw=0;reg signed[31:0] mbias=3;
    wire mtr,mav;wire signed[31:0] mad;
    mac_scalar mac_unit(.clk(clk),.rst(rst),.term_valid(mtv),.term_ready(mtr),
        .x(mx),.w(mw),.first(mfirst),.last(mlast),.bias(mbias),
        .acc_valid(mav),.acc_ready(mar),.acc_data(mad));
    task automatic check_mac(input integer count);
        integer j,expected,gaps;
        begin
            expected=3;
            for(j=0;j<count;j=j+1)begin
                gaps=integer'($urandom_range(0,2));repeat(gaps)@(negedge clk);
                @(negedge clk);mx=count==1?-8'sd128:8'($urandom_range(0,255));
                mw=count==1?-8'sd128:8'($urandom_range(0,255));
                expected=expected+integer'(mx)*integer'(mw);
                mfirst=(j==0);mlast=(j==count-1);mtv=1;
                while(!mtr)@(negedge clk);
                @(posedge clk);@(negedge clk);mtv=0;
            end
            while(!mav)@(negedge clk);
            repeat(3)begin if(mad!=expected)$fatal(1,"MAC gap/hold failure");@(negedge clk);end
            mar=1;@(posedge clk);@(negedge clk);mar=0;
            if(mav)$fatal(1,"MAC duplicate");
        end
    endtask

    reg urv=0,urr=0;reg [4:0] ura=3;reg[7:0] urtag=8'ha5,uram=0;
    wire urready,uren,usvalid;wire[4:0] uraddr;wire[7:0] usdata,ustag;
    read_hold read_unit(.clk(clk),.rst(rst),.req_valid(urv),.req_ready(urready),
        .req_addr(ura),.req_tag(urtag),.ram_en(uren),.ram_addr(uraddr),.ram_data(uram),
        .rsp_valid(usvalid),.rsp_ready(urr),.rsp_data(usdata),.rsp_tag(ustag));
    always @(posedge clk)if(uren)uram<=(uraddr==3)?8'hfc:8'h07;
    task automatic check_read;
        begin
            @(negedge clk);urv=1;
            @(posedge clk);if(!urready)$fatal(1,"read request not accepted");
            @(negedge clk);urv=0;
            while(!usvalid)@(negedge clk);
            repeat(4)begin
                if(usdata!==8'hfc||ustag!==8'ha5||urready)$fatal(1,"read response hold/tag");
                @(negedge clk);
            end
            urr=1;@(posedge clk);@(negedge clk);urr=0;
            if(usvalid||!urready)$fatal(1,"read response duplicate");
        end
    endtask

    // Independent postprocess module: ties, saturation and signed extremes.
    reg pav=0,prelu=0,pyr=0;reg signed[31:0] pad=0;
    wire par,pyv,pyl;wire signed[7:0] pyd;wire [2:0] pyi;
    postprocess4 post_unit(.clk(clk),.rst(rst),.acc_valid(pav),.acc_ready(par),.acc_data(pad),
        .relu_mode(prelu),.index_in(3'd7),.y_valid(pyv),.y_ready(pyr),.y_data(pyd),.y_index(pyi),.y_last(pyl));
    task automatic check_post(input integer value,input reg relu_en);
        integer expected;
        begin
            expected=post_ref(value,relu_en);
            @(negedge clk);pad=value;prelu=relu_en;pav=1;
            while(!par)@(negedge clk);
            @(posedge clk);@(negedge clk);pav=0;
            while(!pyv)@(negedge clk);
            repeat(3)begin
                if(integer'($signed(pyd))!=expected||pyi!=7||!pyl)$fatal(1,"post unit mismatch");
                @(negedge clk);
            end
            pyr=1;@(posedge clk);@(negedge clk);pyr=0;
            if(pyv)$fatal(1,"post duplicate");
        end
    endtask

    integer n,seed=2026,unused_seed,reset_case;
    initial begin
        unused_seed=$urandom(seed);
        repeat(3)@(negedge clk);rst=0;
        // Command cannot start before preload is complete.
        cmd_valid=1;repeat(3)@(negedge clk);
        if(cmd_ready||busy)$fatal(1,"started without prepared");cmd_valid=0;
        for(n=0;n<2;n=n+1)begin relu_mode=1'(n);prepare_case(0);launch();finish_job();end
        for(n=0;n<60;n=n+1)begin relu_mode=1'(n);prepare_case(1);launch();finish_job();end
        relu_mode=0;prepare_case(2);launch();finish_job();
        // A legal pending command stays valid until it is actually accepted.
        relu_mode=0;prepare_case(0);launch();
        relu_mode=1;cmd_valid=1;y_ready=1;
        while(!rsp_valid)@(negedge clk);
        prepare_case(0); // Same memories/bias, new ReLU mode; old output already checked.
        rsp_ready=1;@(posedge clk);@(negedge clk);rsp_ready=0;
        if(!cmd_ready)$fatal(1,"queued command not enabled");
        @(posedge clk);@(negedge clk);cmd_valid=0;finish_job();
        // Reset at issue, native RAM pending, mid-dot, held output, held response.
        for(reset_case=0;reset_case<5;reset_case=reset_case+1)begin
            relu_mode=0;prepare_case(0);y_ready=0;launch();
            case(reset_case)
                0: begin end
                1: while(dut.xr.state!=1)@(negedge clk);
                2: while(term_count<3)@(negedge clk);
                3: while(!y_valid)@(negedge clk);
                4: begin y_ready=1;while(!rsp_valid)@(negedge clk);y_ready=0;end
            endcase
            rst=1;prepared=0;cmd_valid=0;rsp_ready=0;
            repeat(2)@(negedge clk);rst=0;
            repeat(4)begin @(negedge clk);if(y_valid||rsp_valid||cmd_ready)$fatal(1,"old result after reset");end
            relu_mode=0;prepare_case(0);launch();finish_job();
        end
        check_post(10,0);check_post(14,0);check_post(-10,0);check_post(-14,0);
        check_post(512,0);check_post(-516,0);check_post(32'sh7fffffff,0);check_post(32'sh80000000,0);
        check_post(-14,1);check_post(512,1);check_post(0,1);
        check_mac(1);check_mac(18);check_mac(18);check_read();
        if(jobs!=70||cancels!=5)$fatal(1,"unexpected test counts %0d %0d",jobs,cancels);
        $display("PASS jobs=%0d cancelled=%0d accepted_terms=%0d accepted_outputs=%0d hold_checks=%0d post_cases=11 mac_cases=3 read_cases=1",jobs,cancels,total_terms,total_outputs,hold_checks);
        $finish;
    end
    initial begin
        if($test$plusargs("TRACE"))begin $dumpfile("results/conv_fixed.vcd");$dumpvars(0,tb_conv_fixed);end
        #10000000;$fatal(1,"global timeout");
    end
endmodule
