`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Testbench: mac_unit_tb
// Description: MAC Unit verification with C reference comparison
//              Loads test data via $readmemh and compares results
//              For Vivado simulation
//-----------------------------------------------------------------------------

module mac_unit_tb;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter int INPUT_WIDTH  = 8;
    parameter int WEIGHT_WIDTH = 8;
    parameter int OUTPUT_WIDTH = 32;
    parameter int CLK_PERIOD   = 10;
    parameter int NUM_OPS      = 289;

    // Test data path (update this path for your environment)
    parameter string DATA_PATH = "/home/yc/idsl_npu/sw/ref/";

    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    logic                      clk;
    logic                      rst_n;
    logic                      enable;
    logic                      clear_acc;
    logic signed [INPUT_WIDTH-1:0]    data_in;
    logic signed [WEIGHT_WIDTH-1:0]   weight_in;
    logic signed [OUTPUT_WIDTH-1:0]   data_out;

    //-------------------------------------------------------------------------
    // Reference Data Memory
    //-------------------------------------------------------------------------
    logic [INPUT_WIDTH-1:0]  ref_input    [0:NUM_OPS-1];
    logic [WEIGHT_WIDTH-1:0] ref_weight   [0:NUM_OPS-1];
    logic [7:0]              ref_clear    [0:NUM_OPS-1];
    logic [OUTPUT_WIDTH-1:0] ref_expected [0:NUM_OPS-1];

    //-------------------------------------------------------------------------
    // Test Variables
    //-------------------------------------------------------------------------
    int test_count;
    int pass_count;
    int fail_count;

    //-------------------------------------------------------------------------
    // DUT Instance
    //-------------------------------------------------------------------------
    mac_unit #(
        .INPUT_WIDTH  (INPUT_WIDTH),
        .WEIGHT_WIDTH (WEIGHT_WIDTH),
        .OUTPUT_WIDTH (OUTPUT_WIDTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (enable),
        .clear_acc  (clear_acc),
        .data_in    (data_in),
        .weight_in  (weight_in),
        .data_out   (data_out)
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
        data_in   = 0;
        weight_in = 0;
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

    // Single MAC operation from reference data
    task automatic do_mac_op(int idx);
        @(posedge clk);
        // Apply clear if flagged
        if (ref_clear[idx]) begin
            clear_acc <= 1;
            enable    <= 0;
            data_in   <= 0;
            weight_in <= 0;
            @(posedge clk);
            clear_acc <= 0;
        end

        // Apply input/weight and enable
        data_in   <= $signed(ref_input[idx]);
        weight_in <= $signed(ref_weight[idx]);
        enable    <= 1;
        @(posedge clk);
        enable    <= 0;
        @(posedge clk);  // Wait for result to propagate
    endtask

    // Check result against reference
    task automatic check_result(int idx);
        test_count++;
        if (data_out === $signed(ref_expected[idx])) begin
            pass_count++;
        end else begin
            fail_count++;
            $display("===========================================================");
            $display("[FAIL] Operation #%0d", idx);
            $display("       Input:    %0d (0x%02X)", $signed(ref_input[idx]), ref_input[idx]);
            $display("       Weight:   %0d (0x%02X)", $signed(ref_weight[idx]), ref_weight[idx]);
            $display("       Clear:    %0d", ref_clear[idx]);
            $display("       Output:   %0d (0x%08X)", data_out, data_out);
            $display("       Expected: %0d (0x%08X)",
                     $signed(ref_expected[idx]), ref_expected[idx]);
            $display("===========================================================");
            $display("");
            $display("!!! SIMULATION STOPPED DUE TO MISMATCH !!!");
            $display("");
            $finish;
        end
    endtask

    //-------------------------------------------------------------------------
    // Load Reference Data
    //-------------------------------------------------------------------------
    task automatic load_test_data();
        $display("  Loading: %smac_test_input.hex", DATA_PATH);
        $readmemh({DATA_PATH, "mac_test_input.hex"},    ref_input);

        $display("  Loading: %smac_test_weight.hex", DATA_PATH);
        $readmemh({DATA_PATH, "mac_test_weight.hex"},   ref_weight);

        $display("  Loading: %smac_test_clear.hex", DATA_PATH);
        $readmemh({DATA_PATH, "mac_test_clear.hex"},    ref_clear);

        $display("  Loading: %smac_test_expected.hex", DATA_PATH);
        $readmemh({DATA_PATH, "mac_test_expected.hex"}, ref_expected);
    endtask

    //-------------------------------------------------------------------------
    // Main Test Sequence
    //-------------------------------------------------------------------------
    initial begin
        $display("");
        $display("=============================================================");
        $display("        MAC Unit Testbench - Vivado Simulation");
        $display("=============================================================");
        $display("  INPUT_WIDTH:  %0d", INPUT_WIDTH);
        $display("  WEIGHT_WIDTH: %0d", WEIGHT_WIDTH);
        $display("  OUTPUT_WIDTH: %0d", OUTPUT_WIDTH);
        $display("  NUM_OPS:      %0d", NUM_OPS);
        $display("  DATA_PATH:    %s", DATA_PATH);
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
        // Run all MAC operations from reference data
        //=====================================================================
        $display("--- Running %0d MAC Operations ---", NUM_OPS);

        for (int i = 0; i < NUM_OPS; i++) begin
            do_mac_op(i);
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
        $dumpfile("mac_unit_tb.vcd");
        $dumpvars(0, mac_unit_tb);
    end

endmodule
