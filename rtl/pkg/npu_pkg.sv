//-----------------------------------------------------------------------------
// Module: npu_pkg
// Description: NPU common parameters and type definitions
//-----------------------------------------------------------------------------

package npu_pkg;

    //-------------------------------------------------------------------------
    // Data Width Parameters
    //-------------------------------------------------------------------------
    parameter int INPUT_WIDTH  = 8;   // Input activation bit-width
    parameter int WEIGHT_WIDTH = 8;   // Weight bit-width
    parameter int OUTPUT_WIDTH = 32;  // Output/Accumulator bit-width

    //-------------------------------------------------------------------------
    // Array Size Parameters
    //-------------------------------------------------------------------------
    parameter int SUBARRAY_ROWS    = 32;  // Sub-array rows (output vector size)
    parameter int SUBARRAY_COLS    = 8;   // Sub-array cols (input vector size)
    parameter int PE_ARRAY_ROWS    = 2;   // PE array rows
    parameter int PE_ARRAY_COLS    = 2;   // PE array cols
    parameter int NUM_LARGE_ARRAYS = 4;   // Number of large PE arrays

    //-------------------------------------------------------------------------
    // Derived Parameters
    //-------------------------------------------------------------------------
    parameter int TOTAL_PE_UNITS = PE_ARRAY_ROWS * PE_ARRAY_COLS * NUM_LARGE_ARRAYS;
    parameter int MACS_PER_PE    = SUBARRAY_ROWS * SUBARRAY_COLS;  // 256
    parameter int TOTAL_MACS     = TOTAL_PE_UNITS * MACS_PER_PE;   // 4096

    //-------------------------------------------------------------------------
    // AXI-Lite Parameters
    //-------------------------------------------------------------------------
    parameter int AXI_ADDR_WIDTH = 12;
    parameter int AXI_DATA_WIDTH = 32;

    //-------------------------------------------------------------------------
    // Register Address Map
    //-------------------------------------------------------------------------
    parameter logic [11:0] REG_CTRL       = 12'h000;  // Control register
    parameter logic [11:0] REG_STATUS     = 12'h004;  // Status register
    parameter logic [11:0] REG_CLUSTER_EN = 12'h008;  // Large PE Array enable [3:0]
    parameter logic [11:0] REG_PE_EN_0    = 12'h00C;  // Array[0] PE enable [3:0]
    parameter logic [11:0] REG_PE_EN_1    = 12'h010;  // Array[1] PE enable [3:0]
    parameter logic [11:0] REG_PE_EN_2    = 12'h014;  // Array[2] PE enable [3:0]
    parameter logic [11:0] REG_PE_EN_3    = 12'h018;  // Array[3] PE enable [3:0]
    parameter logic [11:0] REG_CONFIG     = 12'h01C;  // Configuration register
    parameter logic [11:0] REG_DIM_M      = 12'h020;  // M dimension (output rows)
    parameter logic [11:0] REG_DIM_K      = 12'h024;  // K dimension (shared/accumulate)
    parameter logic [11:0] REG_DIM_N      = 12'h028;  // N dimension (output cols)
    parameter logic [11:0] REG_ADDR_INPUT = 12'h02C;  // Input data base address
    parameter logic [11:0] REG_ADDR_WEIGHT= 12'h030;  // Weight data base address
    parameter logic [11:0] REG_ADDR_OUTPUT= 12'h034;  // Output data base address

    //-------------------------------------------------------------------------
    // Status Bits
    //-------------------------------------------------------------------------
    typedef struct packed {
        logic [28:0] reserved;
        logic        error;
        logic        done;
        logic        busy;
    } status_t;

    //-------------------------------------------------------------------------
    // Control Bits
    //-------------------------------------------------------------------------
    typedef struct packed {
        logic [29:0] reserved;
        logic        clear;
        logic        start;
    } ctrl_t;

endpackage
