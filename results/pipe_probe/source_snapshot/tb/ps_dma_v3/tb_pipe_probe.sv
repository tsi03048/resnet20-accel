`timescale 1ns/1ps
module tb_pipe_probe;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,load_begin=0,cfg_valid=0,start=0,compute_ready=1,trace_ready=1,rsp_ready=1;
    logic cfg_ready,load_error,prepared,start_ready,start_rejected,busy,done,fault;
    logic [2:0] cfg_kind=0,fault_code;
    logic [18:0] cfg_addr=0,weight_count;
    logic [31:0] cfg_data=0;
    logic [12:0] input_count;
    logic [9:0] bias_count,n_count,shift_count;
    logic step_valid,mac_fire,gap_fire,trace_valid,trace_skip_from_x,rsp_valid,result_valid;
    logic [4:0] trace_op;
    logic [13:0] trace_addr,trace_skip_addr;
    logic signed [31:0] trace_acc,trace_code,score_read_data;
    logic signed [7:0] trace_skip;
    logic signed [63:0] trace_wide;
    logic [3:0] prediction,score_read_addr=0;
    full_model dut(.*);
    logic [7:0] input_vec[0:3071],weight_vec[0:26];
    logic signed [15:0] product_vec[0:107];
    logic signed [31:0] prefix_vec[0:107],acc_vec[0:3],code_vec[0:3];
    logic signed [63:0] wide_vec[0:3];
    integer cycles=0,pixel=0,term=0,macs=0,compute_stalls=0,trace_stalls=0,held_edges=0,fd;
    bit checking=0,trace_waited=0,hold_pipe=0;
    logic [203:0] old_pipe;
    wire [203:0] current_pipe={dut.acc,dut.term_idx,dut.issue_idx,dut.ic,dut.ky,dut.kx,dut.out_idx,dut.op_id,dut.pair_x,dut.weight_q,dut.product,dut.v_addr,dut.v_ram,dut.v_pair,dut.v_product,dut.issued_all,dut.read_a_address,dut.read_weight_address,dut.read_a_inside,dut.inside_ram,dut.last_addr,dut.last_ram,dut.last_pair,dut.last_product,dut.ram_a_q,dut.weights.low_mem.raw_q,dut.weights.high_mem.raw_q,dut.weights.low_mem.q,dut.weights.high_mem.q,dut.weights.low_mem.read_pending,dut.weights.high_mem.read_pending,dut.weights.bank_first,dut.weights.read_pending,dut.weights.read_bank};
    string root=".";
    always @(negedge clk) begin
        cycles=cycles+1;if(cycles>400000) $fatal(1,"PIPE_PROBE_TIMEOUT");
        compute_ready=cycles%5!=0;
        trace_ready=!(trace_valid && !trace_waited);
        if(!trace_valid || trace_ready) trace_waited=0;else trace_waited=1;
    end
    always @(posedge clk) begin
        integer index;
        if(rst) hold_pipe=0;
        else begin
            if(hold_pipe && current_pipe!==old_pipe) $fatal(1,"PIPE_PROBE_HOLD_CHANGED");
            if(hold_pipe) held_edges=held_edges+1;
            hold_pipe=!dut.pipe_ce;old_pipe=current_pipe;
            if(checking) begin
                if(fault) $fatal(1,"PIPE_PROBE_FAULT code=%0d",fault_code);
                if(step_valid && !compute_ready) compute_stalls=compute_stalls+1;
                if(trace_valid && !trace_ready) trace_stalls=trace_stalls+1;
                if(mac_fire) begin
                    index=pixel*27+term;
                    if(trace_op!=0 || trace_addr!=14'(pixel) || dut.term_idx!=10'(term)) $fatal(1,"PIPE_PROBE_ORDER");
                    if(dut.product!==product_vec[index]) $fatal(1,"PIPE_PROBE_PRODUCT pixel=%0d term=%0d got=%0d expected=%0d",pixel,term,dut.product,product_vec[index]);
                    if($signed(dut.acc_next)!=$signed(prefix_vec[index])) $fatal(1,"PIPE_PROBE_PREFIX pixel=%0d term=%0d got=%0d expected=%0d",pixel,term,dut.acc_next,prefix_vec[index]);
                    $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d",pixel,term,dut.product,dut.acc,dut.acc_next);
                    macs=macs+1;term=term+1;
                end
                if(trace_valid && trace_ready) begin
                    if(term!=27 || trace_acc!==acc_vec[pixel] || trace_code!==code_vec[pixel] || trace_wide!==wide_vec[pixel]) $fatal(1,"PIPE_PROBE_OUTPUT pixel=%0d acc=%0d code=%0d",pixel,trace_acc,trace_code);
                    $display("PIPE_PROBE_PIXEL_PASS pixel=%0d acc=%0d code=%0d",pixel,trace_acc,trace_code);
                    term=0;pixel=pixel+1;
                    if(pixel==4) begin
                        if(macs!=108 || compute_stalls==0 || trace_stalls==0 || held_edges==0) $fatal(1,"PIPE_PROBE_COUNTS");
                        $fclose(fd);
                        $display("PIPE_PROBE_PASS pixels=4 macs=108 signed_products=1 ordered_prefix=1 compute_stalls=%0d trace_stalls=%0d held_edges=%0d",compute_stalls,trace_stalls,held_edges);
                        $finish;
                    end
                end
            end
        end
    end
    task automatic put(input integer typ,address,input logic [31:0] value);
        @(negedge clk);cfg_valid=1;cfg_kind=3'(typ);cfg_addr=19'(address);cfg_data=value;
        if(!cfg_ready) $fatal(1,"PIPE_PROBE_CFG_NOT_READY");
        @(posedge clk);#1;if(load_error) $fatal(1,"PIPE_PROBE_LOAD_ERROR kind=%0d address=%0d",typ,address);
    endtask
    initial begin
        if($value$plusargs("ROOT=%s",root)) begin end
        $readmemh($sformatf("%s/reference/pipe_probe/input.hex",root),input_vec);
        $readmemh($sformatf("%s/reference/pipe_probe/weight.hex",root),weight_vec);
        $readmemh($sformatf("%s/reference/pipe_probe/product.hex",root),product_vec);
        $readmemh($sformatf("%s/reference/pipe_probe/prefix.hex",root),prefix_vec);
        $readmemh($sformatf("%s/reference/pipe_probe/acc.hex",root),acc_vec);
        $readmemh($sformatf("%s/reference/pipe_probe/code.hex",root),code_vec);
        $readmemh($sformatf("%s/reference/pipe_probe/wide.hex",root),wide_vec);
        fd=$fopen($sformatf("%s/results/pipe_probe/mac.csv",root),"w");if(fd==0) $fatal(1,"PIPE_PROBE_CSV_OPEN");
        $fdisplay(fd,"pixel,term,product,acc_before,acc_after");
        repeat(3) @(negedge clk);rst=0;@(negedge clk);load_begin=1;@(negedge clk);load_begin=0;
        for(integer i=0;i<3072;i=i+1) put(0,i,{24'd0,input_vec[i]});
        for(integer i=0;i<268336;i=i+1) put(1,i,i<27?{24'd0,weight_vec[i]}:32'd0);
        for(integer i=0;i<698;i=i+1) put(2,i,i==0?32'd7:32'd0);
        for(integer i=0;i<698;i=i+1) put(3,i,i==0?32'd3:32'd1);
        for(integer i=0;i<698;i=i+1) put(4,i,i==0?32'd2:32'd0);
        @(negedge clk);cfg_valid=0;repeat(3) @(negedge clk);
        if(!prepared || !start_ready) $fatal(1,"PIPE_PROBE_NOT_PREPARED");
        checking=1;start=1;@(negedge clk);start=0;
    end
endmodule
