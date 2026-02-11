`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Testbench: gemv_subarray_tb
// Description: GeMV Sub-array verification with C reference comparison
//              Loads test data via $readmemh and compares results
//              For Vivado simulation
//-----------------------------------------------------------------------------

module gemv_subarray_tb;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter int INPUT_WIDTH   = 8;
    parameter int WEIGHT_WIDTH  = 8;
    parameter int OUTPUT_WIDTH  = 32;
    parameter int SUBARRAY_ROWS = 32;
    parameter int SUBARRAY_COLS = 8;
    parameter int CLK_PERIOD    = 10;
    parameter int NUM_TESTS     = 20;  // seed=42 기준, C reference 재생성 시 업데이트 필요

    // Test data path (update this path for your environment)
    parameter string DATA_PATH = "/home/yc/yc_npu/sw/ref/hex_data/";

    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    logic                      clk;
    logic                      rst_n;
    logic                      enable;
    logic                      clear_acc;
    logic [SUBARRAY_COLS-1:0][INPUT_WIDTH-1:0]  input_vector;
    logic [SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][WEIGHT_WIDTH-1:0] weight_matrix;
    logic [SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0] output_vector;
    logic                      valid_out;

    //-------------------------------------------------------------------------
    // Reference Data Memory
    //-------------------------------------------------------------------------
    logic [INPUT_WIDTH-1:0]  ref_input  [0:NUM_TESTS*SUBARRAY_COLS-1];
    logic [WEIGHT_WIDTH-1:0] ref_weight [0:NUM_TESTS*SUBARRAY_ROWS*SUBARRAY_COLS-1];
    logic [OUTPUT_WIDTH-1:0] ref_output [0:NUM_TESTS*SUBARRAY_ROWS-1];

    //-------------------------------------------------------------------------
    // Test Variables
    //-------------------------------------------------------------------------
    int test_count;
    int pass_count;
    int fail_count;

    //-------------------------------------------------------------------------
    // DUT Instance
    //-------------------------------------------------------------------------
    gemv_subarray #(
        .INPUT_WIDTH   (INPUT_WIDTH),
        .WEIGHT_WIDTH  (WEIGHT_WIDTH),
        .OUTPUT_WIDTH  (OUTPUT_WIDTH),
        .SUBARRAY_ROWS (SUBARRAY_ROWS),
        .SUBARRAY_COLS (SUBARRAY_COLS)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (enable),
        .clear_acc     (clear_acc),
        .input_vector  (input_vector),
        .weight_matrix (weight_matrix),
        .output_vector (output_vector),
        .valid_out     (valid_out)
    );

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // Test Tasks
    //-------------------------------------------------------------------------

    // Initialize signals (blocking OK for initial values)
    task automatic init_signals();
        rst_n     = 0;
        enable    = 0;
        clear_acc = 0;
        input_vector  = '0;
        weight_matrix = '0;
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
    endtask

    // Reset sequence
    task automatic do_reset();
        @(posedge clk);
        rst_n <= 0;
        repeat(5) @(posedge clk);
        rst_n <= 1;
        repeat(2) @(posedge clk);
    endtask

    //-------------------------------------------------------------------------
    // Load Reference Data
    //-------------------------------------------------------------------------
    task automatic load_test_data();
        $display("  Loading: %sgemv_test_input.hex", DATA_PATH);
        $readmemh({DATA_PATH, "gemv_test_input.hex"},  ref_input);

        $display("  Loading: %sgemv_test_weight.hex", DATA_PATH);
        $readmemh({DATA_PATH, "gemv_test_weight.hex"}, ref_weight);

        $display("  Loading: %sgemv_test_output.hex", DATA_PATH);
        $readmemh({DATA_PATH, "gemv_test_output.hex"}, ref_output);
    endtask

    //-------------------------------------------------------------------------
    // Single GEMV operation from reference data
    //-------------------------------------------------------------------------
    task automatic do_gemv_op(int idx);
        int input_base, weight_base;

        input_base  = idx * SUBARRAY_COLS;
        weight_base = idx * SUBARRAY_ROWS * SUBARRAY_COLS;

        @(posedge clk);
        // Apply input vector
        for (int c = 0; c < SUBARRAY_COLS; c++) begin
            input_vector[c] <= ref_input[input_base + c];
        end

        // Apply weight matrix (convert from linear to 2D)
        for (int r = 0; r < SUBARRAY_ROWS; r++) begin
            for (int c = 0; c < SUBARRAY_COLS; c++) begin
                weight_matrix[r][c] <= ref_weight[weight_base + r * SUBARRAY_COLS + c];
            end
        end

        // Clear accumulator
        @(posedge clk);
        clear_acc <= 1;
        @(posedge clk);
        clear_acc <= 0;

        // Enable computation
        @(posedge clk);
        enable <= 1;
        @(posedge clk);
        enable <= 0;

        // Wait for valid output
        wait(valid_out);
        @(posedge clk);
    endtask

    //-------------------------------------------------------------------------
    // Check result against reference
    //-------------------------------------------------------------------------
    task automatic check_result(int idx);
        int output_base;
        int mismatch_found;

        output_base    = idx * SUBARRAY_ROWS;
        mismatch_found = 0;

        test_count++;

        for (int r = 0; r < SUBARRAY_ROWS; r++) begin
            if ($signed(output_vector[r]) !== $signed(ref_output[output_base + r])) begin
                if (!mismatch_found) begin
                    fail_count++;
                    mismatch_found = 1;
                    $display("===========================================================");
                    $display("[FAIL] Test #%0d", idx);
                    $display("===========================================================");
                    $display("  First mismatch at row [%0d]:", r);
                    $display("    RTL Output:   %0d (0x%08X)",
                             $signed(output_vector[r]), output_vector[r]);
                    $display("    C Reference:  %0d (0x%08X)",
                             $signed(ref_output[output_base + r]), ref_output[output_base + r]);
                    $display("");
                end
            end
        end

        if (!mismatch_found) begin
            pass_count++;
        end else begin
            // Print all mismatches
            $display("  All mismatches:");
            for (int r = 0; r < SUBARRAY_ROWS; r++) begin
                if ($signed(output_vector[r]) !== $signed(ref_output[output_base + r])) begin
                    $display("    [%2d] RTL=%0d, REF=%0d",
                             r, $signed(output_vector[r]),
                             $signed(ref_output[output_base + r]));
                end
            end
            $display("===========================================================");
            $display("");
            $display("!!! SIMULATION STOPPED DUE TO MISMATCH !!!");
            $display("");
            $finish;
        end
    endtask

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("");
        $display("=============================================================");
        $display("      GeMV Sub-array Testbench - Vivado Simulation");
        $display("=============================================================");
        $display("  SUBARRAY_ROWS: %0d", SUBARRAY_ROWS);
        $display("  SUBARRAY_COLS: %0d", SUBARRAY_COLS);
        $display("  INPUT_WIDTH:   %0d", INPUT_WIDTH);
        $display("  WEIGHT_WIDTH:  %0d", WEIGHT_WIDTH);
        $display("  OUTPUT_WIDTH:  %0d", OUTPUT_WIDTH);
        $display("  NUM_TESTS:     %0d", NUM_TESTS);
        $display("  DATA_PATH:     %s", DATA_PATH);
        $display("=============================================================");
        $display("");

        // Initialize
        init_signals();

        // Load reference data from C-generated hex files
        $display("--- Loading C Reference Data ---");
        load_test_data();
        $display("");

        // Reset
        do_reset();

        //=====================================================================
        // Run all GEMV operations from reference data
        //=====================================================================
        $display("--- Running %0d GEMV Operations ---", NUM_TESTS);

        for (int i = 0; i < NUM_TESTS; i++) begin
            do_gemv_op(i);
            check_result(i);
        end

        //=====================================================================
        // Test Summary
        //=====================================================================
        $display("");
        $display("=============================================================");
        $display("                    TEST SUMMARY");
        $display("=============================================================");
        $display("  Total tests:  %0d", test_count);
        $display("  Passed:       %0d", pass_count);
        $display("  Failed:       %0d", fail_count);
        $display("=============================================================");

        if (fail_count == 0) begin
            $display("");
            $display("  *** ALL TESTS PASSED ***");
            $display("");
        end

        $finish;
    end

    //-------------------------------------------------------------------------
    // Timeout Watchdog
    //-------------------------------------------------------------------------
    initial begin
        #(CLK_PERIOD * 100000);
        $display("");
        $display("!!! SIMULATION TIMEOUT !!!");
        $display("");
        $finish;
    end

    //-------------------------------------------------------------------------
    // Waveform Dump (for Vivado)
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("gemv_subarray_tb.vcd");
        $dumpvars(0, gemv_subarray_tb);
    end

endmodule
