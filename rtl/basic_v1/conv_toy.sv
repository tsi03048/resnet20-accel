// Basic v1: fixed B1 fixture, signed MAC, request register, backpressure.
// A teaching implementation; not a trained-model accelerator.
module conv_toy(
    input logic clk, rst, start, mac_ready, y_ready,
    output logic busy, done, y_valid,
    output logic [1:0] y_addr,
    output logic signed [31:0] y_data,
    output logic mac_fire
);
    typedef enum logic [1:0] {IDLE, READ_PAIR, MAC, STORE} state_t;
    state_t state;
    logic [1:0] out_idx;
    logic [3:0] term_idx;
    logic signed [7:0] pair_x, pair_w;
    logic signed [15:0] product;
    logic signed [31:0] psum, next_psum;
    integer xa, wa;

    function automatic logic signed [7:0] input_rom(input integer a);
        case(a)
            0: input_rom=5; 1: input_rom=4; 2: input_rom=1; 3: input_rom=0;
            4: input_rom=4; 5: input_rom=3; 6: input_rom=1; 7: input_rom=0;
            8: input_rom=3; 9: input_rom=2; 10: input_rom=0; 11: input_rom=0;
            12: input_rom=2; 13: input_rom=1; 14: input_rom=0; 15: input_rom=0;
            default: input_rom=0;
        endcase
    endfunction
    function automatic logic signed [7:0] weight_rom(input integer a);
        case(a % 3)
            0: weight_rom=1;
            1: weight_rom=0;
            default: weight_rom=-1;
        endcase
    endfunction

    always_comb begin
        xa = (int'(out_idx) / 2 + int'(term_idx) / 3) * 4
             + int'(out_idx) % 2 + int'(term_idx) % 3;
        wa = int'(term_idx);
        product = pair_x * pair_w;
        next_psum = psum + {{16{product[15]}}, product};
        busy = state != IDLE;
        mac_fire = state == MAC && mac_ready;
        y_valid = state == STORE;
        y_addr = out_idx;
        y_data = psum;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE; done <= 0; psum <= 0;
            out_idx <= 0; term_idx <= 0; pair_x <= 0; pair_w <= 0;
        end else begin
            done <= 0;
            case (state)
                IDLE: if(start) begin
                    out_idx <= 0; term_idx <= 0; psum <= 0; state <= READ_PAIR;
                end
                READ_PAIR: begin
                    pair_x <= input_rom(xa); pair_w <= weight_rom(wa); state <= MAC;
                end
                MAC: if(mac_ready) begin
                    psum <= next_psum;
                    if(term_idx == 8) state <= STORE;
                    else begin term_idx <= term_idx + 1; state <= READ_PAIR; end
                end
                STORE: if(y_ready) begin
                    if(out_idx == 3) begin state <= IDLE; done <= 1; end
                    else begin
                        out_idx <= out_idx + 1; term_idx <= 0; psum <= 0;
                        state <= READ_PAIR;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
