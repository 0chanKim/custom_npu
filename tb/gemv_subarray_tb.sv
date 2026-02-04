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
    logic [INPUT_WIDTH-1:0]  ref_input  [0:SUBARRAY_COLS-1];
    logic [WEIGHT_WIDTH-1:0] ref_weight [0:SUBARRAY_ROWS*SUBARRAY_COLS-1];
    logic [OUTPUT_WIDTH-1:0] ref_output [0:SUBARRAY_ROWS-1];

    //-------------------------------------------------------------------------
    // Test Variables
    //-------------------------------------------------------------------------
    int test_count;
    int pass_count;
    int fail_count;
    int error_idx;
    string current_test;

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

    // Initialize signals
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

    // Load test data from hex files
    task automatic load_test_data(string test_name);
        string input_file, weight_file, output_file;

        input_file  = {DATA_PATH, test_name, "_input.hex"};
        weight_file = {DATA_PATH, test_name, "_weight.hex"};
        output_file = {DATA_PATH, test_name, "_output.hex"};

        $display("  Loading: %s", input_file);
        $readmemh(input_file, ref_input);

        $display("  Loading: %s", weight_file);
        $readmemh(weight_file, ref_weight);

        $display("  Loading: %s", output_file);
        $readmemh(output_file, ref_output);

        current_test = test_name;
    endtask

    // Apply input data to DUT
    task automatic apply_inputs();
        @(posedge clk);
        // Apply input vector
        for (int c = 0; c < SUBARRAY_COLS; c++) begin
            input_vector[c] <= ref_input[c];
        end

        // Apply weight matrix (convert from linear to 2D)
        for (int r = 0; r < SUBARRAY_ROWS; r++) begin
            for (int c = 0; c < SUBARRAY_COLS; c++) begin
                weight_matrix[r][c] <= ref_weight[r * SUBARRAY_COLS + c];
            end
        end
    endtask

    // Run computation
    task automatic run_computation();
        @(posedge clk);
        clear_acc <= 1;
        @(posedge clk);
        clear_acc <= 0;

        @(posedge clk);
        enable <= 1;
        @(posedge clk);
        enable <= 0;

        // Wait for valid output
        wait(valid_out);
        @(posedge clk);
    endtask

    // Check results against reference
    task automatic check_results();
        int mismatch_found;
        mismatch_found = 0;

        test_count++;

        for (int r = 0; r < SUBARRAY_ROWS; r++) begin
            if ($signed(output_vector[r]) !== $signed(ref_output[r])) begin
                if (!mismatch_found) begin
                    fail_count++;
                    mismatch_found = 1;
                    error_idx = r;
                end
            end
        end

        if (!mismatch_found) begin
            pass_count++;
            $display("[PASS] %s", current_test);
        end else begin
            $display("===========================================================");
            $display("[FAIL] %s", current_test);
            $display("===========================================================");
            $display("  First mismatch at index [%0d]:", error_idx);
            $display("    RTL Output:   %0d (0x%08X)",
                     $signed(output_vector[error_idx]), output_vector[error_idx]);
            $display("    C Reference:  %0d (0x%08X)",
                     $signed(ref_output[error_idx]), ref_output[error_idx]);
            $display("");

            // Print all mismatches
            $display("  All mismatches:");
            for (int r = 0; r < SUBARRAY_ROWS; r++) begin
                if ($signed(output_vector[r]) !== $signed(ref_output[r])) begin
                    $display("    [%2d] RTL=%0d, REF=%0d",
                             r, $signed(output_vector[r]), $signed(ref_output[r]));
                end
            end

            $display("===========================================================");
            $display("");
            $display("!!! SIMULATION STOPPED DUE TO MISMATCH !!!");
            $display("");
            $finish;
        end
    endtask

    // Run single test with file loading
    task automatic run_test(string test_name);
        $display("");
        $display("--- Running Test: %s ---", test_name);

        load_test_data(test_name);
        apply_inputs();
        run_computation();
        check_results();
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
        $display("  DATA_PATH:     %s", DATA_PATH);
        $display("=============================================================");

        // Initialize
        init_signals();
        do_reset();

        //=====================================================================
        // Run Tests with C Reference Data
        //=====================================================================

        // Test 1: Scaled rows pattern (easiest to debug)
        run_test("test_scaled");

        // Test 2: All ones pattern
        run_test("test_allones");

        // Test 3: Identity-like pattern
        run_test("test_identity");

        // Test 4: Alternating signs (cancellation)
        run_test("test_alternating");

        // Test 5: Maximum values stress test
        run_test("test_maxval");

        // Test 6: Minimum values stress test
        run_test("test_minval");

        // Test 7: Mixed signs (max * min)
        run_test("test_mixed");

        // Test 8: Sparse pattern
        run_test("test_sparse");

        // Test 9: Random pattern (seed 42)
        run_test("test_random42");

        // Test 10: Boundary - single element
        run_test("test_single");

        // Test 11: Boundary - last element
        run_test("test_last");

        // Test 12: Boundary - first/last row
        run_test("test_firstlast");

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
