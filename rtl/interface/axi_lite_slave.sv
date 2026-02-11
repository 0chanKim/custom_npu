//-----------------------------------------------------------------------------
// Module: axi_lite_slave
// Description: AXI4-Lite Slave Interface for NPU control and configuration
//-----------------------------------------------------------------------------

module axi_lite_slave #(
    parameter int AXI_ADDR_WIDTH = 12,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int NUM_LARGE_ARRAYS = 4
)(
    input  logic                      clk,
    input  logic                      rst_n,

    //-------------------------------------------------------------------------
    // AXI4-Lite Interface
    //-------------------------------------------------------------------------
    // Write Address Channel
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    // Write Data Channel
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,

    // Write Response Channel
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    // Read Address Channel
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    // Read Data Channel
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    //-------------------------------------------------------------------------
    // Control Outputs to NPU
    //-------------------------------------------------------------------------
    output logic                      ctrl_start,
    output logic                      ctrl_clear,
    output logic [NUM_LARGE_ARRAYS-1:0] cluster_enable,
    output logic [NUM_LARGE_ARRAYS-1:0][3:0] pe_enable,  // 4 PEs per array (2x2)
    output logic [AXI_DATA_WIDTH-1:0] config_reg,

    // Dimension registers
    output logic [AXI_DATA_WIDTH-1:0] dim_m,
    output logic [AXI_DATA_WIDTH-1:0] dim_k,
    output logic [AXI_DATA_WIDTH-1:0] dim_n,

    // Address registers
    output logic [AXI_DATA_WIDTH-1:0] addr_input,
    output logic [AXI_DATA_WIDTH-1:0] addr_weight,
    output logic [AXI_DATA_WIDTH-1:0] addr_output,

    //-------------------------------------------------------------------------
    // Status Inputs from NPU
    //-------------------------------------------------------------------------
    input  logic                      status_busy,
    input  logic                      status_done,
    input  logic                      status_error
);

    //-------------------------------------------------------------------------
    // Register Address Map (from npu_pkg)
    //-------------------------------------------------------------------------
    localparam logic [11:0] REG_CTRL       = 12'h000;
    localparam logic [11:0] REG_STATUS     = 12'h004;
    localparam logic [11:0] REG_CLUSTER_EN = 12'h008;
    localparam logic [11:0] REG_PE_EN_0    = 12'h00C;
    localparam logic [11:0] REG_PE_EN_1    = 12'h010;
    localparam logic [11:0] REG_PE_EN_2    = 12'h014;
    localparam logic [11:0] REG_PE_EN_3    = 12'h018;
    localparam logic [11:0] REG_CONFIG     = 12'h01C;
    localparam logic [11:0] REG_DIM_M      = 12'h020;
    localparam logic [11:0] REG_DIM_K      = 12'h024;
    localparam logic [11:0] REG_DIM_N      = 12'h028;
    localparam logic [11:0] REG_ADDR_INPUT = 12'h02C;
    localparam logic [11:0] REG_ADDR_WEIGHT= 12'h030;
    localparam logic [11:0] REG_ADDR_OUTPUT= 12'h034;

    //-------------------------------------------------------------------------
    // Internal Registers
    //-------------------------------------------------------------------------
    logic [AXI_DATA_WIDTH-1:0] reg_ctrl;
    logic [AXI_DATA_WIDTH-1:0] reg_cluster_en;
    logic [AXI_DATA_WIDTH-1:0] reg_pe_en [NUM_LARGE_ARRAYS];
    logic [AXI_DATA_WIDTH-1:0] reg_config;
    logic [AXI_DATA_WIDTH-1:0] reg_dim_m;
    logic [AXI_DATA_WIDTH-1:0] reg_dim_k;
    logic [AXI_DATA_WIDTH-1:0] reg_dim_n;
    logic [AXI_DATA_WIDTH-1:0] reg_addr_input;
    logic [AXI_DATA_WIDTH-1:0] reg_addr_weight;
    logic [AXI_DATA_WIDTH-1:0] reg_addr_output;

    // AXI state machine
    typedef enum logic [1:0] {
        AXI_IDLE  = 2'b00,
        AXI_WRITE = 2'b01,
        AXI_READ  = 2'b10
    } axi_state_t;

    axi_state_t axi_state;
    logic [AXI_ADDR_WIDTH-1:0] addr_reg;

    //-------------------------------------------------------------------------
    // AXI State Machine
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_state <= AXI_IDLE;
            addr_reg  <= '0;
        end else begin
            case (axi_state)
                AXI_IDLE: begin
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        axi_state <= AXI_WRITE;
                        addr_reg  <= s_axi_awaddr;
                    end else if (s_axi_arvalid) begin
                        axi_state <= AXI_READ;
                        addr_reg  <= s_axi_araddr;
                    end
                end
                AXI_WRITE: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        axi_state <= AXI_IDLE;
                    end
                end
                AXI_READ: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        axi_state <= AXI_IDLE;
                    end
                end
                default: axi_state <= AXI_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // AXI Handshake Signals
    //-------------------------------------------------------------------------
    assign s_axi_awready = (axi_state == AXI_IDLE);
    assign s_axi_wready  = (axi_state == AXI_IDLE);
    assign s_axi_arready = (axi_state == AXI_IDLE) && !s_axi_awvalid;
    assign s_axi_bvalid  = (axi_state == AXI_WRITE);
    assign s_axi_rvalid  = (axi_state == AXI_READ);
    assign s_axi_bresp   = 2'b00;  // OKAY
    assign s_axi_rresp   = 2'b00;  // OKAY

    //-------------------------------------------------------------------------
    // Write Logic
    //-------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl        <= '0;
            reg_cluster_en  <= '0;
            reg_pe_en[0]    <= 4'hF;  // Default: all PEs enabled
            reg_pe_en[1]    <= 4'hF;
            reg_pe_en[2]    <= 4'hF;
            reg_pe_en[3]    <= 4'hF;
            reg_config      <= '0;
            reg_dim_m       <= '0;
            reg_dim_k       <= '0;
            reg_dim_n       <= '0;
            reg_addr_input  <= '0;
            reg_addr_weight <= '0;
            reg_addr_output <= '0;
        end else if (axi_state == AXI_IDLE && s_axi_awvalid && s_axi_wvalid) begin
            case (s_axi_awaddr[11:0])
                REG_CTRL:        reg_ctrl        <= s_axi_wdata;
                REG_CLUSTER_EN:  reg_cluster_en  <= s_axi_wdata;
                REG_PE_EN_0:     reg_pe_en[0]    <= s_axi_wdata;
                REG_PE_EN_1:     reg_pe_en[1]    <= s_axi_wdata;
                REG_PE_EN_2:     reg_pe_en[2]    <= s_axi_wdata;
                REG_PE_EN_3:     reg_pe_en[3]    <= s_axi_wdata;
                REG_CONFIG:      reg_config      <= s_axi_wdata;
                REG_DIM_M:       reg_dim_m       <= s_axi_wdata;
                REG_DIM_K:       reg_dim_k       <= s_axi_wdata;
                REG_DIM_N:       reg_dim_n       <= s_axi_wdata;
                REG_ADDR_INPUT:  reg_addr_input  <= s_axi_wdata;
                REG_ADDR_WEIGHT: reg_addr_weight <= s_axi_wdata;
                REG_ADDR_OUTPUT: reg_addr_output <= s_axi_wdata;
                default: ;
            endcase
        end else begin
            // Auto-clear start and clear bits
            reg_ctrl[0] <= 1'b0;  // start
            reg_ctrl[1] <= 1'b0;  // clear
        end
    end

    //-------------------------------------------------------------------------
    // Read Logic
    //-------------------------------------------------------------------------
    always_comb begin
        s_axi_rdata = '0;
        case (addr_reg[11:0])
            REG_CTRL:       s_axi_rdata = reg_ctrl;
            REG_STATUS:     s_axi_rdata = {29'b0, status_error, status_done, status_busy};
            REG_CLUSTER_EN: s_axi_rdata = reg_cluster_en;
            REG_PE_EN_0:    s_axi_rdata = reg_pe_en[0];
            REG_PE_EN_1:    s_axi_rdata = reg_pe_en[1];
            REG_PE_EN_2:    s_axi_rdata = reg_pe_en[2];
            REG_PE_EN_3:    s_axi_rdata = reg_pe_en[3];
            REG_CONFIG:      s_axi_rdata = reg_config;
            REG_DIM_M:       s_axi_rdata = reg_dim_m;
            REG_DIM_K:       s_axi_rdata = reg_dim_k;
            REG_DIM_N:       s_axi_rdata = reg_dim_n;
            REG_ADDR_INPUT:  s_axi_rdata = reg_addr_input;
            REG_ADDR_WEIGHT: s_axi_rdata = reg_addr_weight;
            REG_ADDR_OUTPUT: s_axi_rdata = reg_addr_output;
            default:         s_axi_rdata = '0;
        endcase
    end

    //-------------------------------------------------------------------------
    // Control Output Assignment
    //-------------------------------------------------------------------------
    assign ctrl_start      = reg_ctrl[0];
    assign ctrl_clear      = reg_ctrl[1];
    assign cluster_enable  = reg_cluster_en[NUM_LARGE_ARRAYS-1:0];
    assign pe_enable[0]    = reg_pe_en[0][3:0];
    assign pe_enable[1]    = reg_pe_en[1][3:0];
    assign pe_enable[2]    = reg_pe_en[2][3:0];
    assign pe_enable[3]    = reg_pe_en[3][3:0];
    assign config_reg      = reg_config;

    assign dim_m           = reg_dim_m;
    assign dim_k           = reg_dim_k;
    assign dim_n           = reg_dim_n;
    assign addr_input      = reg_addr_input;
    assign addr_weight     = reg_addr_weight;
    assign addr_output     = reg_addr_output;

endmodule
