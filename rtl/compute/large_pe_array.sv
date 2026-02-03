//-----------------------------------------------------------------------------
// Module: large_pe_array
// Description: 2x2 PE Array containing 4 PE Units
//              Each PE Unit has a 32x8 GeMV sub-array
//-----------------------------------------------------------------------------

module large_pe_array #(
    parameter int INPUT_WIDTH    = 8,
    parameter int WEIGHT_WIDTH   = 8,
    parameter int OUTPUT_WIDTH   = 32,
    parameter int SUBARRAY_ROWS  = 32,
    parameter int SUBARRAY_COLS  = 8,
    parameter int PE_ARRAY_ROWS  = 2,
    parameter int PE_ARRAY_COLS  = 2
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // Control signals
    input  logic                      array_enable,  // Enable entire array
    input  logic [PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_enable,  // Individual PE enables
    input  logic                      start,
    input  logic                      clear,

    // Data inputs - shared input vector, separate weights per PE
    input  logic [PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0][SUBARRAY_COLS-1:0][INPUT_WIDTH-1:0] input_vectors,
    input  logic [PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0][SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][WEIGHT_WIDTH-1:0] weight_matrices,

    // Data outputs
    output logic [PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0][SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0] output_vectors,

    // Status signals
    output logic [PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_busy,
    output logic [PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_done,
    output logic [PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_valid,
    output logic                      array_busy,
    output logic                      array_done
);

    //-------------------------------------------------------------------------
    // Generate PE Units
    //-------------------------------------------------------------------------
    genvar r, c;
    generate
        for (r = 0; r < PE_ARRAY_ROWS; r++) begin : gen_pe_row
            for (c = 0; c < PE_ARRAY_COLS; c++) begin : gen_pe_col
                pe_unit #(
                    .INPUT_WIDTH   (INPUT_WIDTH),
                    .WEIGHT_WIDTH  (WEIGHT_WIDTH),
                    .OUTPUT_WIDTH  (OUTPUT_WIDTH),
                    .SUBARRAY_ROWS (SUBARRAY_ROWS),
                    .SUBARRAY_COLS (SUBARRAY_COLS)
                ) u_pe_unit (
                    .clk           (clk),
                    .rst_n         (rst_n),
                    .pe_enable     (array_enable & pe_enable[r][c]),
                    .start         (start),
                    .clear         (clear),
                    .input_vector  (input_vectors[r][c]),
                    .weight_matrix (weight_matrices[r][c]),
                    .output_vector (output_vectors[r][c]),
                    .busy          (pe_busy[r][c]),
                    .done          (pe_done[r][c]),
                    .valid_out     (pe_valid[r][c])
                );
            end
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Array Status
    //-------------------------------------------------------------------------
    // Array is busy if any PE is busy
    always_comb begin
        array_busy = 1'b0;
        for (int i = 0; i < PE_ARRAY_ROWS; i++) begin
            for (int j = 0; j < PE_ARRAY_COLS; j++) begin
                array_busy = array_busy | pe_busy[i][j];
            end
        end
    end

    // Array is done when all enabled PEs are done
    always_comb begin
        array_done = 1'b1;
        for (int i = 0; i < PE_ARRAY_ROWS; i++) begin
            for (int j = 0; j < PE_ARRAY_COLS; j++) begin
                if (pe_enable[i][j]) begin
                    array_done = array_done & pe_done[i][j];
                end
            end
        end
    end

endmodule
