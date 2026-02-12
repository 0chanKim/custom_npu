//-----------------------------------------------------------------------------
// Module: top_pe
// Description: PE-level integration module
//              Combines PE_ctrl + gemv_subarray + 3 BRAM buffers
//              BRAM widths matched to PE array dimensions for max utilization
//              BRAM: HIGH_PERFORMANCE mode (2-cycle read latency)
//              - Weight buffer: ROWS*COLS*WEIGHT_WIDTH = 2048-bit
//              - Input buffer:  COLS*INPUT_WIDTH = 64-bit
//              - Output buffer: ROWS*OUTPUT_WIDTH = 1024-bit
//-----------------------------------------------------------------------------

module top_pe #(
    parameter int SUBARRAY_ROWS = 32,
    parameter int SUBARRAY_COLS = 8,
    parameter int INPUT_WIDTH   = 8,
    parameter int WEIGHT_WIDTH  = 8,
    parameter int OUTPUT_WIDTH  = 32,
    parameter int BUF_DEPTH     = 4
)(
    input  logic clk,
    input  logic rst_n,

    // Upper-level control
    input  logic start,
    input  logic clear_acc,
    output logic busy,
    output logic done,

    // Weight buffer external write (Port A) — full matrix width
    input  logic [$clog2(BUF_DEPTH)-1:0]                        wbuf_wr_addr,
    input  logic [SUBARRAY_ROWS*SUBARRAY_COLS*WEIGHT_WIDTH-1:0] wbuf_wr_data,
    input  logic                                                 wbuf_wr_en,

    // Input buffer external write (Port A) — full vector width
    input  logic [$clog2(BUF_DEPTH)-1:0]                        ibuf_wr_addr,
    input  logic [SUBARRAY_COLS*INPUT_WIDTH-1:0]                ibuf_wr_data,
    input  logic                                                 ibuf_wr_en,

    // Output buffer external read (Port B) — full vector width
    input  logic [$clog2(BUF_DEPTH)-1:0]                        obuf_rd_addr,
    input  logic                                                 obuf_rd_en,
    output logic [SUBARRAY_ROWS*OUTPUT_WIDTH-1:0]               obuf_rd_data
);

    //-------------------------------------------------------------------------
    // Local Parameters
    //-------------------------------------------------------------------------
    localparam int WEIGHT_BUF_WIDTH = SUBARRAY_ROWS * SUBARRAY_COLS * WEIGHT_WIDTH; // 2048
    localparam int INPUT_BUF_WIDTH  = SUBARRAY_COLS * INPUT_WIDTH;                   // 64
    localparam int OUTPUT_BUF_WIDTH = SUBARRAY_ROWS * OUTPUT_WIDTH;                  // 1024

    //-------------------------------------------------------------------------
    // Internal Wires: PE_ctrl ↔ Buffers
    //-------------------------------------------------------------------------
    // Weight buffer read (PE_ctrl → buffer Port B)
    logic [$clog2(BUF_DEPTH)-1:0]  wbuf_rd_addr;
    logic                           wbuf_rd_en;
    logic [WEIGHT_BUF_WIDTH-1:0]   wbuf_rd_data;

    // Input buffer read (PE_ctrl → buffer Port B)
    logic [$clog2(BUF_DEPTH)-1:0]  ibuf_rd_addr;
    logic                           ibuf_rd_en;
    logic [INPUT_BUF_WIDTH-1:0]    ibuf_rd_data;

    // Output buffer write (PE_ctrl → buffer Port A)
    logic [$clog2(BUF_DEPTH)-1:0]  obuf_wr_addr_ctrl;
    logic                           obuf_wr_en_ctrl;
    logic [OUTPUT_BUF_WIDTH-1:0]   obuf_wr_data_ctrl;

    //-------------------------------------------------------------------------
    // Internal Wires: PE_ctrl ↔ gemv_subarray
    //-------------------------------------------------------------------------
    logic                                                            gemv_enable;
    logic                                                            gemv_clear_acc;
    logic [SUBARRAY_COLS-1:0][INPUT_WIDTH-1:0]                      gemv_input_vector;
    logic [SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][WEIGHT_WIDTH-1:0] gemv_weight_matrix;
    logic [SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0]                     gemv_output_vector;
    logic                                                            gemv_valid_out;

    //-------------------------------------------------------------------------
    // PE Controller
    //-------------------------------------------------------------------------
    PE_ctrl #(
        .SUBARRAY_ROWS (SUBARRAY_ROWS),
        .SUBARRAY_COLS (SUBARRAY_COLS),
        .INPUT_WIDTH   (INPUT_WIDTH),
        .WEIGHT_WIDTH  (WEIGHT_WIDTH),
        .OUTPUT_WIDTH  (OUTPUT_WIDTH),
        .BUF_DEPTH     (BUF_DEPTH)
    ) u_pe_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),
        .start            (start),
        .clear_acc        (clear_acc),
        .busy             (busy),
        .done             (done),
        // Weight buffer read
        .wbuf_addr        (wbuf_rd_addr),
        .wbuf_rd_en       (wbuf_rd_en),
        .wbuf_rdata       (wbuf_rd_data),
        // Input buffer read
        .ibuf_addr        (ibuf_rd_addr),
        .ibuf_rd_en       (ibuf_rd_en),
        .ibuf_rdata       (ibuf_rd_data),
        // Output buffer write
        .obuf_addr        (obuf_wr_addr_ctrl),
        .obuf_wr_en       (obuf_wr_en_ctrl),
        .obuf_wdata       (obuf_wr_data_ctrl),
        // gemv control
        .gemv_enable       (gemv_enable),
        .gemv_clear_acc    (gemv_clear_acc),
        .gemv_input_vector (gemv_input_vector),
        .gemv_weight_matrix(gemv_weight_matrix),
        .gemv_output_vector(gemv_output_vector),
        .gemv_valid_out    (gemv_valid_out)
    );

    //-------------------------------------------------------------------------
    // GeMV Sub-array (Datapath)
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
        .enable        (gemv_enable),
        .clear_acc     (gemv_clear_acc),
        .input_vector  (gemv_input_vector),
        .weight_matrix (gemv_weight_matrix),
        .output_vector (gemv_output_vector),
        .valid_out     (gemv_valid_out)
    );

    //-------------------------------------------------------------------------
    // Weight Buffer (full matrix width = 2048-bit)
    //   Port A: external write
    //   Port B: PE_ctrl read
    //-------------------------------------------------------------------------
    sim_dual_port_bram #(
        .RAM_WIDTH       (WEIGHT_BUF_WIDTH),
        .RAM_DEPTH       (BUF_DEPTH),
        .RAM_PERFORMANCE ("HIGH_PERFORMANCE"),
        .INIT_FILE       ("")
    ) u_weight_buffer (
        .addra  (wbuf_wr_addr),
        .addrb  (wbuf_rd_addr),
        .dina   (wbuf_wr_data),
        .clka   (clk),
        .wea    (wbuf_wr_en),
        .enb    (wbuf_rd_en),
        .rstb   (rst_n),
        .regceb (1'b1),
        .doutb  (wbuf_rd_data)
    );

    //-------------------------------------------------------------------------
    // Input Buffer (full vector width = 64-bit)
    //   Port A: external write
    //   Port B: PE_ctrl read (HIGH_PERFORMANCE: 2-cycle latency)
    //-------------------------------------------------------------------------
    sim_dual_port_bram #(
        .RAM_WIDTH       (INPUT_BUF_WIDTH),
        .RAM_DEPTH       (BUF_DEPTH),
        .RAM_PERFORMANCE ("HIGH_PERFORMANCE"),
        .INIT_FILE       ("")
    ) u_input_buffer (
        .addra  (ibuf_wr_addr),
        .addrb  (ibuf_rd_addr),
        .dina   (ibuf_wr_data),
        .clka   (clk),
        .wea    (ibuf_wr_en),
        .enb    (ibuf_rd_en),
        .rstb   (rst_n),
        .regceb (1'b1),
        .doutb  (ibuf_rd_data)
    );

    //-------------------------------------------------------------------------
    // Output Buffer (full vector width = 1024-bit)
    //   Port A: PE_ctrl write
    //   Port B: external read (HIGH_PERFORMANCE: 2-cycle latency)
    //-------------------------------------------------------------------------
    sim_dual_port_bram #(
        .RAM_WIDTH       (OUTPUT_BUF_WIDTH),
        .RAM_DEPTH       (BUF_DEPTH),
        .RAM_PERFORMANCE ("HIGH_PERFORMANCE"),
        .INIT_FILE       ("")
    ) u_output_buffer (
        .addra  (obuf_wr_addr_ctrl),
        .addrb  (obuf_rd_addr),
        .dina   (obuf_wr_data_ctrl),
        .clka   (clk),
        .wea    (obuf_wr_en_ctrl),
        .enb    (obuf_rd_en),
        .rstb   (rst_n),
        .regceb (1'b1),
        .doutb  (obuf_rd_data)
    );

endmodule
