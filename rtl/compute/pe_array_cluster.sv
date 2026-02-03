//-----------------------------------------------------------------------------
// Module: pe_array_cluster
// Description: Cluster of 4 Large PE Arrays
//              Total: 4 x (2x2 PE Array) x (32x8 Sub-array) = 4096 MACs
//-----------------------------------------------------------------------------

module pe_array_cluster #(
    parameter int INPUT_WIDTH     = 8,
    parameter int WEIGHT_WIDTH    = 8,
    parameter int OUTPUT_WIDTH    = 32,
    parameter int SUBARRAY_ROWS   = 32,
    parameter int SUBARRAY_COLS   = 8,
    parameter int PE_ARRAY_ROWS   = 2,
    parameter int PE_ARRAY_COLS   = 2,
    parameter int NUM_LARGE_ARRAYS = 4
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // Global control
    input  logic                      cluster_enable,
    input  logic                      start,
    input  logic                      clear,

    // Per-array enable
    input  logic [NUM_LARGE_ARRAYS-1:0] large_array_enable,

    // Per-PE enable for each large array
    input  logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_enable,

    // Data inputs
    input  logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0][SUBARRAY_COLS-1:0][INPUT_WIDTH-1:0] input_vectors,
    input  logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0][SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][WEIGHT_WIDTH-1:0] weight_matrices,

    // Data outputs
    output logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0][SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0] output_vectors,

    // Status signals
    output logic [NUM_LARGE_ARRAYS-1:0] array_busy,
    output logic [NUM_LARGE_ARRAYS-1:0] array_done,
    output logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_busy,
    output logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_done,
    output logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_valid,
    output logic                        cluster_busy,
    output logic                        cluster_done
);

    //-------------------------------------------------------------------------
    // Generate Large PE Arrays
    //-------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_LARGE_ARRAYS; i++) begin : gen_large_array
            large_pe_array #(
                .INPUT_WIDTH   (INPUT_WIDTH),
                .WEIGHT_WIDTH  (WEIGHT_WIDTH),
                .OUTPUT_WIDTH  (OUTPUT_WIDTH),
                .SUBARRAY_ROWS (SUBARRAY_ROWS),
                .SUBARRAY_COLS (SUBARRAY_COLS),
                .PE_ARRAY_ROWS (PE_ARRAY_ROWS),
                .PE_ARRAY_COLS (PE_ARRAY_COLS)
            ) u_large_pe_array (
                .clk            (clk),
                .rst_n          (rst_n),
                .array_enable   (cluster_enable & large_array_enable[i]),
                .pe_enable      (pe_enable[i]),
                .start          (start),
                .clear          (clear),
                .input_vectors  (input_vectors[i]),
                .weight_matrices(weight_matrices[i]),
                .output_vectors (output_vectors[i]),
                .pe_busy        (pe_busy[i]),
                .pe_done        (pe_done[i]),
                .pe_valid       (pe_valid[i]),
                .array_busy     (array_busy[i]),
                .array_done     (array_done[i])
            );
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Cluster Status
    //-------------------------------------------------------------------------
    // Cluster is busy if any array is busy
    always_comb begin
        cluster_busy = 1'b0;
        for (int j = 0; j < NUM_LARGE_ARRAYS; j++) begin
            cluster_busy = cluster_busy | array_busy[j];
        end
    end

    // Cluster is done when all enabled arrays are done
    always_comb begin
        cluster_done = 1'b1;
        for (int j = 0; j < NUM_LARGE_ARRAYS; j++) begin
            if (large_array_enable[j]) begin
                cluster_done = cluster_done & array_done[j];
            end
        end
    end

endmodule
