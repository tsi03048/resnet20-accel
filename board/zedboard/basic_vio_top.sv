// ROM fixture + JTAG VIO: no PS, DDR or DMA is needed for the first board check.
module basic_vio_top(input logic GCLK);
    logic start, reset_request;
    logic start_d=0;
    logic [7:0] power_on=0;
    wire rst = !(&power_on) || reset_request;
    wire start_pulse = start && !start_d;
    wire busy, done, y_valid, mac_fire;
    wire [1:0] y_addr;
    wire signed [31:0] y_data;
    logic [31:0] result0=0, result1=0, result2=0, result3=0;
    logic [3:0] stored=0;
    logic completed=0;
    always_ff @(posedge GCLK) begin
        if(!(&power_on)) power_on <= power_on+1;
        start_d <= start;
        if(rst || (start_pulse && !busy)) begin
            stored <= 0; completed <= 0;
            result0 <= 0; result1 <= 0; result2 <= 0; result3 <= 0;
        end else begin
            if(y_valid) begin
                stored[y_addr] <= 1;
                case(y_addr)
                    0: result0 <= y_data;
                    1: result1 <= y_data;
                    2: result2 <= y_data;
                    3: result3 <= y_data;
                endcase
            end
            if(done) completed <= 1;
        end
    end
    conv_toy core(.clk(GCLK), .rst(rst), .start(start_pulse), .mac_ready(1'b1),
        .y_ready(1'b1), .busy(busy), .done(done), .y_valid(y_valid),
        .y_addr(y_addr), .y_data(y_data), .mac_fire(mac_fire));
    vio_basic observe(.clk(GCLK), .probe_in0(result0), .probe_in1(result1),
        .probe_in2(result2), .probe_in3(result3), .probe_in4({busy,completed}),
        .probe_in5(stored), .probe_out0(start), .probe_out1(reset_request));
endmodule
