"""Generate the BRAM-port adapter from frozen integer RTL; preserve old v1."""
import hashlib,json
from pathlib import Path
from tools.prepare_full_flat import generate as flatten

def generate():
    flatten();text=Path('rtl/full_e2b_flat_v1/full_model.sv').read_text()
    def replace(old,new):
        nonlocal text
        if old not in text:raise ValueError('FPGA transformation missing source fragment: '+old[:60])
        text=text.replace(old,new)
    replace('logic signed [7:0] act_mem_flat[0:49151],w_mem[0:268335];','logic signed [7:0] w_mem[0:268335];')
    replace('ADD_READ,RESP,FAILED','ADD_READ,RESP,FAILED,READ_LATCH,ADD_LATCH')
    insert='''    logic ram_a_en,ram_a_we,ram_b_en;
    logic [15:0] ram_a_addr,ram_b_addr;
    logic signed [7:0] ram_data,ram_a_q,ram_b_q;
    feature_ram feature_mem(.clk(clk),.a_en(ram_a_en),.a_we(ram_a_we),.b_en(ram_b_en),
        .a_addr(ram_a_addr),.b_addr(ram_b_addr),.a_data(ram_data),.a_q(ram_a_q),.b_q(ram_b_q));
    always_comb begin
        ram_a_en=0;ram_a_we=0;ram_b_en=0;ram_a_addr=0;ram_b_addr=0;ram_data=0;
        if(!rst) begin
            if(cfg_valid && cfg_ready && cfg_kind==0 && cfg_addr==19'(input_count) && cfg_addr<3072 && cfg_data[31:8]==0) begin
                ram_a_en=1;ram_a_we=1;ram_a_addr={2'd0,cfg_addr[13:0]};ram_data=cfg_data[7:0];
            end else if(state==TRACE_HOLD && trace_ready && d_kind!=3) begin
                ram_a_en=1;ram_a_we=1;ram_a_addr={2'(d_dst),out_idx};ram_data=trace_code[7:0];
            end else if(state==READ_PAIR && inside_input && x_address>=0 && x_address<16384) begin
                ram_a_en=1;ram_a_addr={2'(d_src),14'(x_address)};
            end else if(state==ADD_READ) begin
                ram_a_en=1;ram_a_addr={2'(d_src),out_idx};
                if(skip_inside && skip_address>=0 && skip_address<16384) begin
                    ram_b_en=1;ram_b_addr={d_skip,14'(skip_address)};
                end
            end
        end
    end
'''
    replace('    always_ff @(posedge clk) begin\n',insert+'    always_ff @(posedge clk) begin\n')
    replace("                        act_mem_flat[{2'd0,cfg_addr[13:0]}]<=cfg_data[7:0];input_count<=input_count+1;","                        input_count<=input_count+1;")
    replace("                            pair_x<=inside_input?act_mem_flat[(d_src<<14)+x_address]:8'sd0;\n                            pair_w<=d_kind==2?8'sd0:w_mem[w_address];state<=MAC;","                            pair_w<=d_kind==2?8'sd0:w_mem[w_address];state<=READ_LATCH;")
    replace('                    MAC: if(compute_ready) begin',"                    READ_LATCH: begin pair_x<=inside_input?ram_a_q:8'sd0;state<=MAC;end\n                    MAC: if(compute_ready) begin")
    replace('                    ADD_READ: begin','                    ADD_READ: state<=ADD_LATCH;\n                    ADD_LATCH: begin')
    replace("act_mem_flat[(int'(d_skip)<<14)+skip_address]",'ram_b_q')
    replace("act_mem_flat[(d_src<<14)+int'(out_idx)]",'ram_a_q')
    replace("                        else act_mem_flat[(d_dst<<14)+int'(out_idx)]<=trace_code[7:0];",'                        // Feature output is committed by feature_mem port A on this edge.')
    if 'act_mem_flat' in text:raise ValueError('Remaining direct feature memory access')
    tb=Path('tb/full_e2b_flat_v1/tb_full.sv').read_text().replace('dut.act_mem_flat[','dut.feature_mem.mem[')
    outputs={'rtl/full_e2b_fpga_v1/full_model.sv':text,'tb/full_e2b_fpga_v1/tb_full.sv':tb}
    for name,value in outputs.items():
        out=Path(name);out.parent.mkdir(parents=True,exist_ok=True);out.write_text(value,encoding='ascii',newline='\n')
    meta=dict(baseline_sha256=hashlib.sha256(Path('rtl/full_e2b_v1/full_model.sv').read_bytes()).hexdigest(),
        change='Explicit synchronous true dual-port feature RAM. READ_LATCH and ADD_LATCH consume registered RAM outputs. Arithmetic/graph/Golden unchanged.',
        source_sha256={k:hashlib.sha256(v.encode()).hexdigest() for k,v in outputs.items()})
    Path('rtl/full_e2b_fpga_v1/manifest.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='ascii',newline='\n')
    return meta
if __name__=='__main__':print(json.dumps(generate(),indent=2))
