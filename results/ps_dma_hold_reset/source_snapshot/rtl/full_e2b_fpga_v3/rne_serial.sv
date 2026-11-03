`timescale 1ns/1ps
// Floor arithmetic shift, guard/sticky bits, one ties-to-even increment, clip.
module rne_serial(
    input logic clk,clear,start,
    output logic ready,busy,valid,
    input logic take,
    input logic signed [63:0] wide,
    input logic [4:0] shift,
    input logic [1:0] mode,
    output logic signed [63:0] rounded,
    output logic signed [31:0] code
);
    typedef enum logic [2:0] {IDLE,SHIFT,INCREMENT,CLIP,OUT} state_t;
    state_t state;
    logic signed [63:0] q;
    logic [4:0] left;
    logic [1:0] active_mode;
    logic guard_bit,sticky;
    assign ready=!clear && state==IDLE;
    assign busy=!clear && state!=IDLE && state!=OUT;
    assign valid=!clear && state==OUT;
    always_ff @(posedge clk) begin
        if(clear) begin state<=IDLE;q<=0;left<=0;active_mode<=0;guard_bit<=0;sticky<=0;rounded<=0;code<=0;end
        else case(state)
            IDLE:if(start) begin q<=wide;left<=shift;active_mode<=mode;guard_bit<=0;sticky<=0;state<=shift==0?INCREMENT:SHIFT;end
            SHIFT:begin
                q<=q>>>1;sticky<=sticky|guard_bit;guard_bit<=q[0];left<=left-1;
                if(left==1) state<=INCREMENT;
            end
            INCREMENT:begin rounded<=q+((guard_bit && (sticky || q[0]))?64'sd1:64'sd0);state<=CLIP;end
            CLIP:begin
                if(active_mode==2) begin
                    if(rounded>64'sd2147483647) code<=32'sh7fffffff;
                    else if(rounded< -64'sd2147483648) code<=32'sh80000000;
                    else code<=rounded[31:0];
                end else if(active_mode==1) begin
                    if(rounded<0) code<=0;else if(rounded>127) code<=127;else code<=rounded[31:0];
                end else begin
                    if(rounded< -128) code<=-128;else if(rounded>127) code<=127;else code<=rounded[31:0];
                end
                state<=OUT;
            end
            OUT:if(take) state<=IDLE;
            default:state<=IDLE;
        endcase
    end
endmodule
