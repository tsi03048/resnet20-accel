// E2-B v1: wide signed product -> ONE ties-to-even rounding -> ReLU -> INT8 clip.
module requant_rne_relu(
    input logic signed [31:0] acc,
    input logic signed [31:0] multiplier,
    input logic [4:0] shift,
    output logic signed [63:0] rounded,
    output logic signed [7:0] code
);
    logic signed [63:0] wide, quotient, remainder, half;
    always_comb begin
        wide = {{32{acc[31]}},acc} * {{32{multiplier[31]}},multiplier};
        quotient = wide >>> shift;
        remainder = wide - (quotient <<< shift);
        half = 64'sd0;
        rounded = quotient;
        if(shift != 0) begin
            half = 64'sd1 <<< (shift-1);
            if(remainder > half || (remainder == half && quotient[0]))
                rounded = quotient + 64'sd1;
        end
        if(rounded < 0) code = 8'sd0;
        else if(rounded > 127) code = 8'sd127;
        else code = rounded[7:0];
    end
endmodule
