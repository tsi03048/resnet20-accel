`timescale 1ns/1ps
// Signed32 x nonnegative31; optional sum of two products. One 64-bit add/clock.
module mul_serial(
    input logic clk,clear,start,
    output logic ready,busy,valid,
    input logic take,add_second,
    input logic signed [31:0] lhs1,lhs2,
    input logic [30:0] n1,n2,
    output logic signed [63:0] result
);
    typedef enum logic [2:0] {IDLE,MULTIPLY,SECOND,SUM,OUT} state_t;
    state_t state;
    logic signed [63:0] shifted,acc,next_acc,first;
    logic signed [31:0] second_lhs;
    logic [30:0] bits_left,second_n;
    logic [4:0] count;
    logic second_pending;
    assign ready=!clear && state==IDLE;
    assign busy=!clear && state!=IDLE && state!=OUT;
    assign valid=!clear && state==OUT;
    assign next_acc=acc+(bits_left[0]?shifted:64'sd0);
    always_ff @(posedge clk) begin
        if(clear) begin state<=IDLE;result<=0;shifted<=0;acc<=0;first<=0;count<=0;bits_left<=0;second_lhs<=0;second_n<=0;second_pending<=0;end
        else case(state)
            IDLE:if(start) begin
                shifted<={{32{lhs1[31]}},lhs1};bits_left<=n1;acc<=0;count<=0;first<=0;
                second_lhs<=lhs2;second_n<=n2;second_pending<=add_second;state<=MULTIPLY;
            end
            MULTIPLY:begin
                acc<=next_acc;shifted<=shifted<<<1;bits_left<=bits_left>>1;
                if(count==30) begin
                    if(second_pending) begin first<=next_acc;state<=SECOND;end
                    else state<=SUM;
                end else count<=count+1;
            end
            SECOND:begin shifted<={{32{second_lhs[31]}},second_lhs};bits_left<=second_n;acc<=0;count<=0;second_pending<=0;state<=MULTIPLY;end
            SUM:begin result<=first+acc;state<=OUT;end
            OUT:if(take) state<=IDLE;
            default:state<=IDLE;
        endcase
    end
endmodule
