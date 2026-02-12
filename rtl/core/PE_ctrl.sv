//-----------------------------------------------------------------------------
// Module: PE_ctrl
// Description: PE Controller FSM for single-tile GeMV operation
//              Controls gemv_subarray directly via full-width BRAM buffers
//              BRAM output is wired directly to gemv (no intermediate registers)
//              BRAM: HIGH_PERFORMANCE mode (2-cycle read latency)
//              FSM: IDLE → LOAD → LOAD_WAIT → COMPUTE → WAIT → STORE → DONE
//              - LOAD:      BRAM enb=1 (read request + clear_acc if needed)
//              - LOAD_WAIT: BRAM output register pipeline (2nd cycle)
//              - COMPUTE:   BRAM doutb_reg valid → gemv_enable=1
//              K-tiling is handled by upper-level controller
//-----------------------------------------------------------------------------

module PE_ctrl #(
    parameter int SUBARRAY_ROWS = 32,
    parameter int SUBARRAY_COLS = 8,
    parameter int INPUT_WIDTH   = 8,
    parameter int WEIGHT_WIDTH  = 8,
    parameter int OUTPUT_WIDTH  = 32,
    parameter int BUF_DEPTH     = 4
)(
    input  logic clk,
    input  logic rst_n,

    // Upper-level control interface
    input  logic start,
    input  logic clear_acc,
    output logic busy,
    output logic done,

    // Weight buffer read port (Port B) — full matrix width
    output logic [$clog2(BUF_DEPTH)-1:0]                                    wbuf_addr,
    output logic                                                             wbuf_rd_en,
    input  logic [SUBARRAY_ROWS*SUBARRAY_COLS*WEIGHT_WIDTH-1:0]             wbuf_rdata,

    // Input buffer read port (Port B) — full vector width
    output logic [$clog2(BUF_DEPTH)-1:0]                                    ibuf_addr,
    output logic                                                             ibuf_rd_en,
    input  logic [SUBARRAY_COLS*INPUT_WIDTH-1:0]                            ibuf_rdata,

    // Output buffer write port (Port A) — full vector width
    output logic [$clog2(BUF_DEPTH)-1:0]                                    obuf_addr,
    output logic                                                             obuf_wr_en,
    output logic [SUBARRAY_ROWS*OUTPUT_WIDTH-1:0]                           obuf_wdata,

    // gemv_subarray direct control
    output logic                                                             gemv_enable,
    output logic                                                             gemv_clear_acc,
    output logic [SUBARRAY_COLS-1:0][INPUT_WIDTH-1:0]                       gemv_input_vector,
    output logic [SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][WEIGHT_WIDTH-1:0]  gemv_weight_matrix,
    input  logic [SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0]                      gemv_output_vector,
    input  logic                                                             gemv_valid_out
);

    //-------------------------------------------------------------------------
    // FSM States
    //-------------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE      = 3'd0,
        S_LOAD      = 3'd1,  // BRAM enb=1 (read request), clear_acc if needed
        S_LOAD_WAIT = 3'd2,  // BRAM output register latency (2nd cycle)
        S_COMPUTE   = 3'd3,  // BRAM doutb_reg valid → gemv_enable=1
        S_WAIT      = 3'd4,  // Wait for gemv_valid_out
        S_STORE     = 3'd5,  // Write output to buffer
        S_DONE      = 3'd6   // Signal completion
    } state_t;

    state_t state, next_state;

    //-------------------------------------------------------------------------
    // Internal Registers
    //-------------------------------------------------------------------------
    logic clear_acc_reg;  // Latched clear_acc at start

    //-------------------------------------------------------------------------
    // State Register
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    //-------------------------------------------------------------------------
    // Next State Logic
    //-------------------------------------------------------------------------
    always_comb begin
        if (!rst_n) begin
            next_state = S_IDLE;
        end
        else begin
            next_state = state;
            case (state)
                S_IDLE:      if (start) next_state = S_LOAD;
                S_LOAD:      next_state = S_LOAD_WAIT;
                S_LOAD_WAIT: next_state = S_COMPUTE;
                S_COMPUTE:   next_state = S_WAIT;
                S_WAIT:      if (gemv_valid_out) next_state = S_STORE;
                S_STORE:     next_state = S_DONE;
                S_DONE:      next_state = S_IDLE;
                default:     next_state = S_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Latch clear_acc on start
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            clear_acc_reg <= 1'b0;
        else if (state == S_IDLE && start)
            clear_acc_reg <= clear_acc;
    end

    //-------------------------------------------------------------------------
    // BRAM Read Control (HIGH_PERFORMANCE: 2-cycle latency)
    //   Cycle 0 (S_LOAD):      enb=1 → ram_data <= BRAM[addr]
    //   Cycle 1 (S_LOAD_WAIT): regceb=1 → doutb_reg <= ram_data
    //   Cycle 2 (S_COMPUTE):   doutb = doutb_reg → valid data
    //-------------------------------------------------------------------------
    assign wbuf_rd_en = (state == S_LOAD);
    assign ibuf_rd_en = (state == S_LOAD);
    assign wbuf_addr  = '0;
    assign ibuf_addr  = '0;

    //-------------------------------------------------------------------------
    // gemv Data Path — BRAM output wired directly (combinational reinterpret)
    //   doutb_reg is stable from S_COMPUTE onward (no new read until next tile)
    //-------------------------------------------------------------------------
    always_comb begin
        for (int r = 0; r < SUBARRAY_ROWS; r++) begin
            for (int c = 0; c < SUBARRAY_COLS; c++) begin
                gemv_weight_matrix[r][c] = wbuf_rdata[(r*SUBARRAY_COLS + c)*WEIGHT_WIDTH +: WEIGHT_WIDTH];
            end
        end
        for (int c = 0; c < SUBARRAY_COLS; c++) begin
            gemv_input_vector[c] = ibuf_rdata[c*INPUT_WIDTH +: INPUT_WIDTH];
        end
    end

    //-------------------------------------------------------------------------
    // gemv Control — pipelined with BRAM 2-cycle latency
    //   S_LOAD:      BRAM enb + clear_acc (if first K-tile)
    //   S_LOAD_WAIT: BRAM output register pipeline
    //   S_COMPUTE:   doutb_reg valid → gemv_enable=1
    //-------------------------------------------------------------------------
    assign gemv_enable    = (state == S_COMPUTE);
    assign gemv_clear_acc = (state == S_LOAD && clear_acc_reg);

    //-------------------------------------------------------------------------
    // Output Buffer Write
    //-------------------------------------------------------------------------
    assign obuf_wr_en = (state == S_STORE);
    assign obuf_addr  = '0;

    always_comb begin
        for (int r = 0; r < SUBARRAY_ROWS; r++) begin
            obuf_wdata[r*OUTPUT_WIDTH +: OUTPUT_WIDTH] = gemv_output_vector[r];
        end
    end

    //-------------------------------------------------------------------------
    // Status
    //-------------------------------------------------------------------------
    assign busy = (state != S_IDLE);
    assign done = (state == S_DONE);

endmodule
