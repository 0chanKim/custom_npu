//-----------------------------------------------------------------------------
// Module: mac_unit
// Description: Multiply-Accumulate Unit for INT8 operations
//              Performs: output = input * weight + accumulator
//              2-stage pipeline:
//                Stage 1: Multiplication -> mult_reg
//                Stage 2: Accumulation   -> acc_reg
//              Latency: 2 cycles from enable to acc_reg update
//-----------------------------------------------------------------------------

module mac_unit #(
    parameter int INPUT_WIDTH  = 8,
    parameter int WEIGHT_WIDTH = 8,
    parameter int OUTPUT_WIDTH = 32
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // Control signals
    input  logic                      enable,
    input  logic                      clear_acc,   // Clear accumulator

    // Data inputs
    input  logic [INPUT_WIDTH-1:0]    data_in,     // Input activation
    input  logic [WEIGHT_WIDTH-1:0]   weight_in,   // Weight value

    // Data output
    output logic [OUTPUT_WIDTH-1:0]   data_out,    // Accumulated result
    output logic                      valid_out    // Accumulator updated
);

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    // Pipeline Stage 1: Multiplication register
    logic signed [INPUT_WIDTH+WEIGHT_WIDTH-1:0] mult_reg;
    logic                             enable_d1;

    // Pipeline Stage 2: Accumulator
    logic signed [OUTPUT_WIDTH-1:0]   acc_reg;

    //-------------------------------------------------------------------------
    // Pipeline Stage 1: Register multiplication result
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_reg  <= '0;
            enable_d1 <= 1'b0;
        end else if (clear_acc) begin
            mult_reg  <= '0;
            enable_d1 <= 1'b0;
        end else begin
            enable_d1 <= enable;
            if (enable) begin
                mult_reg <= $signed(data_in) * $signed(weight_in);
            end
        end
    end

    //-------------------------------------------------------------------------
    // Pipeline Stage 2: Accumulator Register
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_reg   <= '0;
            valid_out <= 1'b0;
        end else if (clear_acc) begin
            acc_reg   <= '0;
            valid_out <= 1'b0;
        end else begin
            valid_out <= enable_d1;
            if (enable_d1) begin
                acc_reg <= acc_reg + OUTPUT_WIDTH'(mult_reg);
            end
        end
    end

    //-------------------------------------------------------------------------
    // Output Assignment
    //-------------------------------------------------------------------------
    assign data_out = acc_reg;

endmodule
