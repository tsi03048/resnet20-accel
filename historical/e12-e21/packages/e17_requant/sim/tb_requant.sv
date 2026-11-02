`timescale 1ns/1ps
module tb_requant;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,iv=0,ready=0,add_mode=0,relu_mode=0,last=0;
    reg signed[31:0] a=0,b=0;reg[15:0] n=0,m=0,ch=0;reg[4:0] sh=0;
    reg signed[7:0] z=0;
    wire ir,ov,ol;wire signed[7:0] oc;wire[15:0] och;
    requant_join dut(.clk(clk),.rst(rst),.in_valid(iv),.in_ready(ir),
        .main_value(a),.skip_value(b),.main_multiplier(n),.skip_multiplier(m),
        .right_shift(sh),.add_mode(add_mode),.relu_mode(relu_mode),.output_zero(z),
        .channel(ch),.last(last),.out_valid(ov),.out_ready(ready),.out_code(oc),.out_channel(och),.out_last(ol));
    integer accepted=0,outputs=0,cancelled=0,holds=0;
    reg active=0,was_hold=0;reg[24:0] saved;
    integer expected=0,expected_ch=0,expected_last=0;
    always @(posedge clk)begin
        if(rst)begin if(active)cancelled=cancelled+1;active=0;was_hold=0;end
        else begin
            if(was_hold)begin if(!ov||saved!=={ol,och,oc})$fatal(1,"payload changed under stall");holds=holds+1;end
            was_hold=ov&&!ready;saved={ol,och,oc};
            if(iv&&ir)begin if(active)$fatal(1,"overlap");active=1;accepted=accepted+1;end
            if(ov&&ready)begin
                if(!active||integer'($signed(oc))!=expected||integer'(och)!=expected_ch||integer'(ol)!=expected_last)
                    $fatal(1,"mismatch token=%0d got=%0d expected=%0d",outputs,oc,expected);
                active=0;outputs=outputs+1;
            end
        end
    end
    task automatic send_token;
        begin
            iv=1;while(!ir)@(negedge clk);
            @(posedge clk);@(negedge clk);iv=0;
        end
    endtask
    integer fd,rc,va,vb,vn,vm,vs,vadd,vr,vz,vc,vl,ve,rows=0;
    initial begin
        repeat(3)@(negedge clk);rst=0;
        fd=$fopen("reference/vectors.txt","r");if(fd==0)$fatal(1,"missing reference");
        while(!$feof(fd))begin
            rc=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d\n",va,vb,vn,vm,vs,vadd,vr,vz,vc,vl,ve);
            if(rc!=11)$fatal(1,"malformed vector");
            @(negedge clk);a=va;b=vb;n=16'(vn);m=16'(vm);sh=5'(vs);add_mode=1'(vadd);relu_mode=1'(vr);z=8'(vz);ch=16'(vc);last=1'(vl);
            expected=ve;expected_ch=vc;expected_last=vl;send_token();
            // Live unrelated configuration changes while a registered result is held.
            a=32'sh7fffffff;b=32'sh80000000;n=65535;m=65535;sh=0;z=127;ch=999;last=~last;
            repeat(rows%5)@(negedge clk);
            ready=1;@(posedge clk);@(negedge clk);ready=0;rows=rows+1;
        end
        $fclose(fd);
        // Reset cancels a held result; no old output may leak into recovery.
        a=5;b=0;n=1;m=0;sh=3;add_mode=0;relu_mode=0;z=0;ch=9;last=1;
        expected=1;expected_ch=9;expected_last=1;send_token();
        repeat(3)@(negedge clk);rst=1;repeat(2)@(negedge clk);rst=0;
        repeat(3)begin @(negedge clk);if(ov)$fatal(1,"stale result");end
        send_token();ready=1;@(posedge clk);@(negedge clk);ready=0;
        if(outputs!=rows+1||accepted!=rows+2||cancelled!=1)$fatal(1,"count");
        $display("PASS vectors=%0d accepted=%0d outputs=%0d cancelled=%0d hold_checks=%0d",rows,accepted,outputs,cancelled,holds);
        $finish;
    end
    initial begin
        if($test$plusargs("TRACE"))begin $dumpfile("results/first_window.vcd");$dumpvars(0,tb_requant);#10000;$display("TRACE WINDOW ONLY");$finish;end
    end
    initial begin #10000000;$fatal(1,"timeout");end
endmodule
