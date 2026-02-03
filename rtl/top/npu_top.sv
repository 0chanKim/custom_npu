//-----------------------------------------------------------------------------
// Module: npu_top
// Description: NPU Top-Level Module
//              Integrates AXI-Lite interface with PE Array Cluster
//-----------------------------------------------------------------------------

module npu_top
    import npu_pkg::*;
#(
    parameter int INPUT_WIDTH      = npu_pkg::INPUT_WIDTH,
    parameter int WEIGHT_WIDTH     = npu_pkg::WEIGHT_WIDTH,
    parameter int OUTPUT_WIDTH     = npu_pkg::OUTPUT_WIDTH,
    parameter int SUBARRAY_ROWS    = npu_pkg::SUBARRAY_ROWS,
    parameter int SUBARRAY_COLS    = npu_pkg::SUBARRAY_COLS,
    parameter int PE_ARRAY_ROWS    = npu_pkg::PE_ARRAY_ROWS,
    parameter int PE_ARRAY_COLS    = npu_pkg::PE_ARRAY_COLS,
    parameter int NUM_LARGE_ARRAYS = npu_pkg::NUM_LARGE_ARRAYS,
    parameter int AXI_ADDR_WIDTH   = npu_pkg::AXI_ADDR_WIDTH,
    parameter int AXI_DATA_WIDTH   = npu_pkg::AXI_DATA_WIDTH
)(
    input  logic                      clk,
    input  logic                      rst_n,

    //-------------------------------------------------------------------------
    // AXI4-Lite Slave Interface (Control/Status)
    //-------------------------------------------------------------------------
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,

    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    //-------------------------------------------------------------------------
    // Data Interface (to be extended with AXI-Stream or memory interface)
    //-------------------------------------------------------------------------
    input  logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0][SUBARRAY_COLS-1:0][INPUT_WIDTH-1:0] input_vectors,
    input  logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0][SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][WEIGHT_WIDTH-1:0] weight_matrices,
    output logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0][SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0] output_vectors,

    //-------------------------------------------------------------------------
    // Status Outputs
    //-------------------------------------------------------------------------
    output logic                      npu_busy,
    output logic                      npu_done,
    output logic                      interrupt
);

    //-------------------------------------------------------------------------
    // Internal Signals
    //-------------------------------------------------------------------------
    // Control signals from AXI-Lite
    logic                      ctrl_start;
    logic                      ctrl_clear;
    logic [NUM_LARGE_ARRAYS-1:0] cluster_enable;
    logic [NUM_LARGE_ARRAYS-1:0][3:0] pe_enable_flat;
    logic [AXI_DATA_WIDTH-1:0] config_reg;

    // PE enable conversion (flat to 2D)
    logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_enable;

    // Status signals to AXI-Lite
    logic                      status_busy;
    logic                      status_done;
    logic                      status_error;

    // Cluster status signals
    logic [NUM_LARGE_ARRAYS-1:0] array_busy;
    logic [NUM_LARGE_ARRAYS-1:0] array_done;
    logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_busy;
    logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_done;
    logic [NUM_LARGE_ARRAYS-1:0][PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0] pe_valid;
    logic                      cluster_busy;
    logic                      cluster_done;

    //-------------------------------------------------------------------------
    // PE Enable Conversion
    //-------------------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < NUM_LARGE_ARRAYS; i++) begin : gen_pe_enable
            assign pe_enable[i][0][0] = pe_enable_flat[i][0];
            assign pe_enable[i][0][1] = pe_enable_flat[i][1];
            assign pe_enable[i][1][0] = pe_enable_flat[i][2];
            assign pe_enable[i][1][1] = pe_enable_flat[i][3];
        end
    endgenerate

    //-------------------------------------------------------------------------
    // AXI-Lite Slave Instance
    //-------------------------------------------------------------------------
    axi_lite_slave #(
        .AXI_ADDR_WIDTH   (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH   (AXI_DATA_WIDTH),
        .NUM_LARGE_ARRAYS (NUM_LARGE_ARRAYS)
    ) u_axi_lite_slave (
        .clk              (clk),
        .rst_n            (rst_n),

        // AXI4-Lite Interface
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),

        // Control Outputs
        .ctrl_start       (ctrl_start),
        .ctrl_clear       (ctrl_clear),
        .cluster_enable   (cluster_enable),
        .pe_enable        (pe_enable_flat),
        .config_reg       (config_reg),

        // Status Inputs
        .status_busy      (status_busy),
        .status_done      (status_done),
        .status_error     (status_error)
    );

    //-------------------------------------------------------------------------
    // PE Array Cluster Instance
    //-------------------------------------------------------------------------
    pe_array_cluster #(
        .INPUT_WIDTH      (INPUT_WIDTH),
        .WEIGHT_WIDTH     (WEIGHT_WIDTH),
        .OUTPUT_WIDTH     (OUTPUT_WIDTH),
        .SUBARRAY_ROWS    (SUBARRAY_ROWS),
        .SUBARRAY_COLS    (SUBARRAY_COLS),
        .PE_ARRAY_ROWS    (PE_ARRAY_ROWS),
        .PE_ARRAY_COLS    (PE_ARRAY_COLS),
        .NUM_LARGE_ARRAYS (NUM_LARGE_ARRAYS)
    ) u_pe_array_cluster (
        .clk               (clk),
        .rst_n             (rst_n),
        .cluster_enable    (|cluster_enable),  // Enable if any array enabled
        .start             (ctrl_start),
        .clear             (ctrl_clear),
        .large_array_enable(cluster_enable),
        .pe_enable         (pe_enable),
        .input_vectors     (input_vectors),
        .weight_matrices   (weight_matrices),
        .output_vectors    (output_vectors),
        .array_busy        (array_busy),
        .array_done        (array_done),
        .pe_busy           (pe_busy),
        .pe_done           (pe_done),
        .pe_valid          (pe_valid),
        .cluster_busy      (cluster_busy),
        .cluster_done      (cluster_done)
    );

    //-------------------------------------------------------------------------
    // Status Signal Assignment
    //-------------------------------------------------------------------------
    assign status_busy  = cluster_busy;
    assign status_done  = cluster_done;
    assign status_error = 1'b0;  // TODO: Add error detection logic

    assign npu_busy = cluster_busy;
    assign npu_done = cluster_done;

    //-------------------------------------------------------------------------
    // Interrupt Generation
    //-------------------------------------------------------------------------
    logic cluster_done_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cluster_done_d <= 1'b0;
        end else begin
            cluster_done_d <= cluster_done;
        end
    end

    // Rising edge of cluster_done generates interrupt
    assign interrupt = cluster_done & ~cluster_done_d;

endmodule
