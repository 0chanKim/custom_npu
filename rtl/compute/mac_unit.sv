//-----------------------------------------------------------------------------
// Module: mac_unit
// Description: Multiply-Accumulate Unit for INT8 operations
//              Performs: output = input * weight + accumulator
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
    output logic [OUTPUT_WIDTH-1:0]   data_out     // Accumulated result
);

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    logic signed [INPUT_WIDTH-1:0]    data_signed;
    logic signed [WEIGHT_WIDTH-1:0]   weight_signed;
    logic signed [INPUT_WIDTH+WEIGHT_WIDTH-1:0] mult_result;
    logic signed [OUTPUT_WIDTH-1:0]   acc_reg;

    //-------------------------------------------------------------------------
    // Sign Extension
    //-------------------------------------------------------------------------
    assign data_signed   = $signed(data_in);
    assign weight_signed = $signed(weight_in);

    //-------------------------------------------------------------------------
    // Multiplication
    //-------------------------------------------------------------------------
    assign mult_result = data_signed * weight_signed;

    //-------------------------------------------------------------------------
    // Accumulator Register
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_reg <= '0;
        end else if (clear_acc) begin
            acc_reg <= '0;
        end else if (enable) begin
            acc_reg <= acc_reg + OUTPUT_WIDTH'(mult_result);
        end
    end

    //-------------------------------------------------------------------------
    // Output Assignment
    //-------------------------------------------------------------------------
    assign data_out = acc_reg;

endmodule
