//-----------------------------------------------------------------------------
// Module: pe_unit
// Description: Processing Element Unit containing a 32x8 GeMV sub-array
//              Provides control interface and data management
//-----------------------------------------------------------------------------

module pe_unit #(
    parameter int INPUT_WIDTH   = 8,
    parameter int WEIGHT_WIDTH  = 8,
    parameter int OUTPUT_WIDTH  = 32,
    parameter int SUBARRAY_ROWS = 32,
    parameter int SUBARRAY_COLS = 8
)(
    input  logic                      clk,
    input  logic                      rst_n,

    // Control signals
    input  logic                      pe_enable,    // PE enable from controller
    input  logic                      start,        // Start computation
    input  logic                      clear,        // Clear accumulators

    // Data inputs
    input  logic [SUBARRAY_COLS-1:0][INPUT_WIDTH-1:0]  input_vector,
    input  logic [SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][WEIGHT_WIDTH-1:0] weight_matrix,

    // Data output
    output logic [SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0] output_vector,

    // Status signals
    output logic                      busy,
    output logic                      done,
    output logic                      valid_out
);

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE    = 2'b00,
        COMPUTE = 2'b01,
        OUTPUT  = 2'b10
    } state_t;

    state_t state, next_state;

    logic subarray_enable;
    logic subarray_clear;
    logic subarray_valid;
    logic [SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0] subarray_output;

    //-------------------------------------------------------------------------
    // GeMV Sub-array Instance
    //-------------------------------------------------------------------------
    gemv_subarray #(
        .INPUT_WIDTH   (INPUT_WIDTH),
        .WEIGHT_WIDTH  (WEIGHT_WIDTH),
        .OUTPUT_WIDTH  (OUTPUT_WIDTH),
        .SUBARRAY_ROWS (SUBARRAY_ROWS),
        .SUBARRAY_COLS (SUBARRAY_COLS)
    ) u_gemv_subarray (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (subarray_enable),
        .clear_acc     (subarray_clear),
        .input_vector  (input_vector),
        .weight_matrix (weight_matrix),
        .output_vector (subarray_output),
        .valid_out     (subarray_valid)
    );

    //-------------------------------------------------------------------------
    // State Machine
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (pe_enable && start) begin
                    next_state = COMPUTE;
                end
            end
            COMPUTE: begin
                if (subarray_valid) begin
                    next_state = OUTPUT;
                end
            end
            OUTPUT: begin
                next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    //-------------------------------------------------------------------------
    // Control Logic
    //-------------------------------------------------------------------------
    always_comb begin
        subarray_enable = 1'b0;
        subarray_clear  = 1'b0;
        busy            = 1'b0;
        done            = 1'b0;

        case (state)
            IDLE: begin
                if (clear) begin
                    subarray_clear = 1'b1;
                end
                if (pe_enable && start) begin
                    subarray_enable = 1'b1;
                    busy = 1'b1;
                end
            end
            COMPUTE: begin
                subarray_enable = pe_enable;
                busy = 1'b1;
            end
            OUTPUT: begin
                done = 1'b1;
            end
            default: ;
        endcase
    end

    //-------------------------------------------------------------------------
    // Output Assignment
    //-------------------------------------------------------------------------
    assign output_vector = subarray_output;
    assign valid_out     = subarray_valid;

endmodule
