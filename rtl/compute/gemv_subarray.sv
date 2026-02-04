//-----------------------------------------------------------------------------
// Module: gemv_subarray
// Description: 32x8 GeMV (General Matrix-Vector Multiplication) Sub-array
//              Computes: output_vector = weight_matrix * input_vector
//              - Weight matrix: 32 rows x 8 cols
//              - Input vector: 8 elements
//              - Output vector: 32 elements
//-----------------------------------------------------------------------------

module gemv_subarray #(
    parameter int INPUT_WIDTH   = 8,
    parameter int WEIGHT_WIDTH  = 8,
    parameter int OUTPUT_WIDTH  = 32,
    parameter int SUBARRAY_ROWS = 32,  // Output vector size
    parameter int SUBARRAY_COLS = 8    // Input vector size
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // Control signals
    input  logic                      enable,
    input  logic                      clear_acc,

    // Data inputs
    input  logic [SUBARRAY_COLS-1:0][INPUT_WIDTH-1:0]  input_vector,
    input  logic [SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][WEIGHT_WIDTH-1:0] weight_matrix,

    // Data output
    output logic [SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0] output_vector,

    // Status
    output logic                      valid_out
);

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    logic [SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][OUTPUT_WIDTH-1:0] mac_outputs;
    logic [SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0] mac_valid;
    logic [SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0] row_sums;

    // Valid pipeline (1 stage for output register after MAC valid)
    logic mac_valid_ref;

    //-------------------------------------------------------------------------
    // Generate MAC Units - One per weight element
    //-------------------------------------------------------------------------
    genvar row, col;
    generate
        for (row = 0; row < SUBARRAY_ROWS; row++) begin : gen_row
            for (col = 0; col < SUBARRAY_COLS; col++) begin : gen_col
                mac_unit #(
                    .INPUT_WIDTH  (INPUT_WIDTH),
                    .WEIGHT_WIDTH (WEIGHT_WIDTH),
                    .OUTPUT_WIDTH (OUTPUT_WIDTH)
                ) u_mac (
                    .clk        (clk),
                    .rst_n      (rst_n),
                    .enable     (enable),
                    .clear_acc  (clear_acc),
                    .data_in    (input_vector[col]),
                    .weight_in  (weight_matrix[row][col]),
                    .data_out   (mac_outputs[row][col]),
                    .valid_out  (mac_valid[row][col])
                );
            end
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Row Sum - Accumulate MAC outputs for each row
    //-------------------------------------------------------------------------
    generate
        for (row = 0; row < SUBARRAY_ROWS; row++) begin : gen_row_sum
            always_comb begin
                row_sums[row] = '0;
                for (int c = 0; c < SUBARRAY_COLS; c++) begin
                    row_sums[row] = row_sums[row] + mac_outputs[row][c];
                end
            end
        end
    endgenerate

    //-------------------------------------------------------------------------
    // MAC Valid Reference (all MACs share the same timing)
    //-------------------------------------------------------------------------
    assign mac_valid_ref = mac_valid[0][0];

    //-------------------------------------------------------------------------
    // Output Register - capture when MAC results are valid
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_vector <= '0;
        end else if (mac_valid_ref) begin
            output_vector <= row_sums;
        end
    end

    //-------------------------------------------------------------------------
    // Valid Signal Pipeline
    // MAC valid_out fires 2 cycles after enable (mult_reg + acc_reg)
    // Output register adds 1 more cycle -> total 3 cycles from enable
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= 1'b0;
        end else begin
            valid_out <= mac_valid_ref;
        end
    end

endmodule
