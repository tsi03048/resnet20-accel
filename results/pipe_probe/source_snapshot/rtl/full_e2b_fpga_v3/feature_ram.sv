`timescale 1ns/1ps
// True dual-port synchronous RAM. Port A read/write, port B read-only.
// No reset/initialization of payload. The native loader prepares valid inputs.
module feature_ram(
    input logic clk,ce,a_en,a_we,b_en,
    input logic [15:0] a_addr,b_addr,
    input logic signed [7:0] a_data,
    output logic signed [7:0] a_q,b_q
);
    (* ram_style="block" *) logic signed [7:0] mem[0:49151];
    always_ff @(posedge clk) begin
        if(ce) begin
            if(a_en) begin
                if(a_we) mem[a_addr]<=a_data;
                a_q<=mem[a_addr];
            end
            if(b_en) b_q<=mem[b_addr];
        end
    end
endmodule
