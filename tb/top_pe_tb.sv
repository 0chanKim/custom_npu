`timescale 1ns/1ps
//-----------------------------------------------------------------------------
// Testbench: top_pe_tb
// Description: top_pe integration verification
//              Tests: single tile, K-tiling accumulation
//              Uses C reference hex data for comparison
//-----------------------------------------------------------------------------

module top_pe_tb;

    //-------------------------------------------------------------------------
    // Parameters
    //-------------------------------------------------------------------------
    parameter int INPUT_WIDTH   = 8;
    parameter int WEIGHT_WIDTH  = 8;
    parameter int OUTPUT_WIDTH  = 32;
    parameter int SUBARRAY_ROWS = 32;
    parameter int SUBARRAY_COLS = 8;
    parameter int BUF_DEPTH     = 4;
    parameter int CLK_PERIOD    = 10;
    parameter int NUM_TESTS     = 20;

    parameter string DATA_PATH = "/home/yc/yc_npu/sw/ref/hex_data/";

    localparam int WEIGHT_BUF_WIDTH = SUBARRAY_ROWS * SUBARRAY_COLS * WEIGHT_WIDTH; // 2048
    localparam int INPUT_BUF_WIDTH  = SUBARRAY_COLS * INPUT_WIDTH;                   // 64
    localparam int OUTPUT_BUF_WIDTH = SUBARRAY_ROWS * OUTPUT_WIDTH;                  // 1024

    //-------------------------------------------------------------------------
    // DUT Signals
    //-------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    // Control
    logic start;
    logic clear_acc;
    logic busy;
    logic done;

    // Weight buffer write
    logic [$clog2(BUF_DEPTH)-1:0]    wbuf_wr_addr;
    logic [WEIGHT_BUF_WIDTH-1:0]     wbuf_wr_data;
    logic                             wbuf_wr_en;

    // Input buffer write
    logic [$clog2(BUF_DEPTH)-1:0]    ibuf_wr_addr;
    logic [INPUT_BUF_WIDTH-1:0]      ibuf_wr_data;
    logic                             ibuf_wr_en;

    // Output buffer read
    logic [$clog2(BUF_DEPTH)-1:0]    obuf_rd_addr;
    logic                             obuf_rd_en;
    logic [OUTPUT_BUF_WIDTH-1:0]     obuf_rd_data;

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
    // PE Utilization Measurement
    //-------------------------------------------------------------------------
    int  perf_total_cycles;      // Total cycles (load → done)
    int  perf_compute_cycles;    // Cycles where gemv_enable=1
    int  perf_load_cycles;       // Buffer write + BRAM read cycles
    int  perf_store_cycles;      // Output store cycles
    int  perf_wait_cycles;       // Pipeline wait cycles
    int  perf_tile_count;        // Number of tiles processed
    logic perf_measuring;        // Measurement active flag

    // Continuous gemv_enable cycle counter (runs in background)
    always_ff @(posedge clk) begin
        if (perf_measuring && dut.gemv_enable)
            perf_compute_cycles <= perf_compute_cycles + 1;
    end

    // Track FSM states for breakdown
    // S_IDLE=0, S_LOAD=1, S_LOAD_WAIT=2, S_COMPUTE=3, S_WAIT=4, S_STORE=5, S_DONE=6
    always_ff @(posedge clk) begin
        if (perf_measuring) begin
            perf_total_cycles <= perf_total_cycles + 1;
            case (dut.u_pe_ctrl.state)
                3'd1, 3'd2: perf_load_cycles   <= perf_load_cycles + 1;   // S_LOAD + S_LOAD_WAIT
                3'd4:       perf_wait_cycles   <= perf_wait_cycles + 1;   // S_WAIT
                3'd5:       perf_store_cycles  <= perf_store_cycles + 1;  // S_STORE
                default: ;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // DUT Instance
    //-------------------------------------------------------------------------
    top_pe #(
        .SUBARRAY_ROWS (SUBARRAY_ROWS),
        .SUBARRAY_COLS (SUBARRAY_COLS),
        .INPUT_WIDTH   (INPUT_WIDTH),
        .WEIGHT_WIDTH  (WEIGHT_WIDTH),
        .OUTPUT_WIDTH  (OUTPUT_WIDTH),
        .BUF_DEPTH     (BUF_DEPTH)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .clear_acc    (clear_acc),
        .busy         (busy),
        .done         (done),
        .wbuf_wr_addr (wbuf_wr_addr),
        .wbuf_wr_data (wbuf_wr_data),
        .wbuf_wr_en   (wbuf_wr_en),
        .ibuf_wr_addr (ibuf_wr_addr),
        .ibuf_wr_data (ibuf_wr_data),
        .ibuf_wr_en   (ibuf_wr_en),
        .obuf_rd_addr (obuf_rd_addr),
        .obuf_rd_en   (obuf_rd_en),
        .obuf_rd_data (obuf_rd_data)
    );

    //-------------------------------------------------------------------------
    // Clock Generation
    //-------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    //-------------------------------------------------------------------------
    // Tasks
    //-------------------------------------------------------------------------

    task automatic init_signals();
        rst_n       = 0;
        start       = 0;
        clear_acc   = 0;
        wbuf_wr_addr = '0;
        wbuf_wr_data = '0;
        wbuf_wr_en   = 0;
        ibuf_wr_addr = '0;
        ibuf_wr_data = '0;
        ibuf_wr_en   = 0;
        obuf_rd_addr = '0;
        obuf_rd_en   = 0;
        test_count   = 0;
        pass_count   = 0;
        fail_count   = 0;
        perf_total_cycles   = 0;
        perf_compute_cycles = 0;
        perf_load_cycles    = 0;
        perf_store_cycles   = 0;
        perf_wait_cycles    = 0;
        perf_tile_count     = 0;
        perf_measuring      = 0;
    endtask

    task automatic do_reset();
        @(posedge clk);
        rst_n <= 0;
        repeat(5) @(posedge clk);
        rst_n <= 1;
        repeat(2) @(posedge clk);
    endtask

    //-------------------------------------------------------------------------
    // PE Utilization Measurement Tasks
    //-------------------------------------------------------------------------

    // Reset and start measurement
    task automatic perf_start();
        @(posedge clk);
        perf_total_cycles   <= 0;
        perf_compute_cycles <= 0;
        perf_load_cycles    <= 0;
        perf_store_cycles   <= 0;
        perf_wait_cycles    <= 0;
        perf_tile_count     <= 0;
        @(posedge clk);
        perf_measuring      <= 1;
    endtask

    // Stop measurement
    task automatic perf_stop();
        @(posedge clk);
        perf_measuring <= 0;
        @(posedge clk);
    endtask

    // Increment tile count
    task automatic perf_tick_tile();
        perf_tile_count <= perf_tile_count + 1;
    endtask

    // Display utilization report
    task automatic perf_report(string label);
        real util_pct;
        int  overhead_cycles;

        overhead_cycles = perf_total_cycles - perf_compute_cycles;
        if (perf_total_cycles > 0)
            util_pct = real'(perf_compute_cycles) / real'(perf_total_cycles) * 100.0;
        else
            util_pct = 0.0;

        $display("");
        $display("-------------------------------------------------------------");
        $display("  PE Utilization Report: %s", label);
        $display("-------------------------------------------------------------");
        $display("  Tiles processed     : %0d", perf_tile_count);
        $display("  Total cycles        : %0d", perf_total_cycles);
        $display("  Compute cycles      : %0d  (gemv_enable=1)", perf_compute_cycles);
        $display("  Load cycles         : %0d  (LOAD_REQ + LOAD_DONE)", perf_load_cycles);
        $display("  Wait cycles         : %0d  (pipeline drain)", perf_wait_cycles);
        $display("  Store cycles        : %0d", perf_store_cycles);
        $display("  Overhead cycles     : %0d  (total - compute)", overhead_cycles);
        $display("  ---");
        $display("  PE Utilization      : %0.1f%%", util_pct);
        if (perf_tile_count > 0)
            $display("  Avg cycles/tile     : %0.1f", real'(perf_total_cycles) / real'(perf_tile_count));
        $display("-------------------------------------------------------------");
        $display("");
    endtask

    task automatic load_test_data();
        $display("  Loading: %sgemv_test_input.hex", DATA_PATH);
        $readmemh({DATA_PATH, "gemv_test_input.hex"},  ref_input);
        $display("  Loading: %sgemv_test_weight.hex", DATA_PATH);
        $readmemh({DATA_PATH, "gemv_test_weight.hex"}, ref_weight);
        $display("  Loading: %sgemv_test_output.hex", DATA_PATH);
        $readmemh({DATA_PATH, "gemv_test_output.hex"}, ref_output);
    endtask

    //-------------------------------------------------------------------------
    // Write weight matrix to weight buffer (pack into WEIGHT_BUF_WIDTH bits)
    //-------------------------------------------------------------------------
    task automatic write_weight_buffer(int test_idx);
        int weight_base;
        weight_base = test_idx * SUBARRAY_ROWS * SUBARRAY_COLS;

        @(posedge clk);
        wbuf_wr_addr <= '0;
        wbuf_wr_en   <= 1;

        // Pack weight matrix: weight[row][col] → flat bit vector
        for (int r = 0; r < SUBARRAY_ROWS; r++) begin
            for (int c = 0; c < SUBARRAY_COLS; c++) begin
                wbuf_wr_data[(r*SUBARRAY_COLS + c)*WEIGHT_WIDTH +: WEIGHT_WIDTH]
                    <= ref_weight[weight_base + r*SUBARRAY_COLS + c];
            end
        end

        @(posedge clk);
        wbuf_wr_en <= 0;
    endtask

    //-------------------------------------------------------------------------
    // Write input vector to input buffer (pack into INPUT_BUF_WIDTH bits)
    //-------------------------------------------------------------------------
    task automatic write_input_buffer(int test_idx);
        int input_base;
        input_base = test_idx * SUBARRAY_COLS;

        @(posedge clk);
        ibuf_wr_addr <= '0;
        ibuf_wr_en   <= 1;

        for (int c = 0; c < SUBARRAY_COLS; c++) begin
            ibuf_wr_data[c*INPUT_WIDTH +: INPUT_WIDTH]
                <= ref_input[input_base + c];
        end

        @(posedge clk);
        ibuf_wr_en <= 0;
    endtask

    //-------------------------------------------------------------------------
    // Start computation and wait for done
    //-------------------------------------------------------------------------
    task automatic run_tile(logic do_clear);
        @(posedge clk);
        start     <= 1;
        clear_acc <= do_clear;
        @(posedge clk);
        start     <= 0;
        clear_acc <= 0;

        // Wait for done
        wait(done);
        @(posedge clk);
    endtask

    //-------------------------------------------------------------------------
    // Read output buffer and compare with reference
    //-------------------------------------------------------------------------
    task automatic check_output(int test_idx);
        int output_base;
        int mismatch_found;
        logic [OUTPUT_WIDTH-1:0] rtl_val;
        logic [OUTPUT_WIDTH-1:0] ref_val;

        output_base    = test_idx * SUBARRAY_ROWS;
        mismatch_found = 0;
        test_count++;

        // Read output buffer (HIGH_PERFORMANCE: 2-cycle latency)
        @(posedge clk);
        obuf_rd_addr <= '0;
        obuf_rd_en   <= 1;
        @(posedge clk);  // Cycle 1: ram_data <= BRAM[addr]
        @(posedge clk);  // Cycle 2: doutb_reg <= ram_data
        @(posedge clk);  // Cycle 3: doutb valid
        obuf_rd_en <= 0;

        // Compare each output element
        for (int r = 0; r < SUBARRAY_ROWS; r++) begin
            rtl_val = obuf_rd_data[r*OUTPUT_WIDTH +: OUTPUT_WIDTH];
            ref_val = ref_output[output_base + r];

            if ($signed(rtl_val) !== $signed(ref_val)) begin
                if (!mismatch_found) begin
                    fail_count++;
                    mismatch_found = 1;
                    $display("===========================================================");
                    $display("[FAIL] Test #%0d", test_idx);
                    $display("===========================================================");
                end
                $display("  [%2d] RTL=%0d (0x%08X), REF=%0d (0x%08X)",
                         r, $signed(rtl_val), rtl_val,
                         $signed(ref_val), ref_val);
            end
        end

        if (!mismatch_found) begin
            pass_count++;
            $display("[PASS] Test #%0d", test_idx);
        end else begin
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
        $display("      top_pe Integration Testbench");
        $display("=============================================================");
        $display("  SUBARRAY_ROWS: %0d", SUBARRAY_ROWS);
        $display("  SUBARRAY_COLS: %0d", SUBARRAY_COLS);
        $display("  BUF_DEPTH:     %0d", BUF_DEPTH);
        $display("  WEIGHT_BUF_WIDTH: %0d bits", WEIGHT_BUF_WIDTH);
        $display("  INPUT_BUF_WIDTH:  %0d bits", INPUT_BUF_WIDTH);
        $display("  OUTPUT_BUF_WIDTH: %0d bits", OUTPUT_BUF_WIDTH);
        $display("  NUM_TESTS:     %0d", NUM_TESTS);
        $display("=============================================================");
        $display("");

        // Initialize
        init_signals();

        // Load reference data
        $display("--- Loading C Reference Data ---");
        load_test_data();
        $display("");

        // Reset
        do_reset();

        //=====================================================================
        // Test 1: Single tile operations (clear_acc=1 for each)
        //=====================================================================
        $display("=== Test Group 1: Single Tile Operations ===");

        perf_start();
        for (int i = 0; i < NUM_TESTS; i++) begin
            write_weight_buffer(i);
            write_input_buffer(i);
            run_tile(1'b1);  // clear_acc=1 for fresh computation
            perf_tick_tile();
            check_output(i);
        end
        perf_stop();
        perf_report("Single Tile Operations (with buffer load + output read)");

        $display("");

        //=====================================================================
        // Test 2: K-tiling simulation (2 consecutive tiles with accumulation)
        //   Tile 0: clear_acc=1, compute test[0]
        //   Tile 1: clear_acc=0, compute test[1] → result = test[0] + test[1]
        //=====================================================================
        $display("=== Test Group 2: K-Tiling Accumulation (2 tiles) ===");

        perf_start();

        // Load and compute first tile (clear accumulator)
        write_weight_buffer(0);
        write_input_buffer(0);
        run_tile(1'b1);  // clear_acc=1
        perf_tick_tile();
        $display("  K-tile 0: computed (clear_acc=1)");

        // Load and compute second tile (accumulate)
        write_weight_buffer(1);
        write_input_buffer(1);
        run_tile(1'b0);  // clear_acc=0 → accumulate
        perf_tick_tile();
        $display("  K-tile 1: computed (clear_acc=0, accumulating)");

        perf_stop();
        perf_report("K-Tiling Accumulation (2 tiles)");

        // Read output and manually verify accumulation
        begin
            logic [OUTPUT_WIDTH-1:0] rtl_val;
            logic signed [OUTPUT_WIDTH-1:0] expected_sum;
            int k_mismatch;

            test_count++;
            k_mismatch = 0;

            // Read output buffer (HIGH_PERFORMANCE: 2-cycle latency)
            @(posedge clk);
            obuf_rd_addr <= '0;
            obuf_rd_en   <= 1;
            @(posedge clk);  // Cycle 1: ram_data <= BRAM[addr]
            @(posedge clk);  // Cycle 2: doutb_reg <= ram_data
            @(posedge clk);  // Cycle 3: doutb valid
            obuf_rd_en <= 0;

            for (int r = 0; r < SUBARRAY_ROWS; r++) begin
                rtl_val = obuf_rd_data[r*OUTPUT_WIDTH +: OUTPUT_WIDTH];
                expected_sum = $signed(ref_output[0*SUBARRAY_ROWS + r])
                             + $signed(ref_output[1*SUBARRAY_ROWS + r]);

                if ($signed(rtl_val) !== expected_sum) begin
                    if (!k_mismatch) begin
                        fail_count++;
                        k_mismatch = 1;
                        $display("[FAIL] K-tiling accumulation test");
                    end
                    $display("  [%2d] RTL=%0d, Expected(t0+t1)=%0d",
                             r, $signed(rtl_val), expected_sum);
                end
            end

            if (!k_mismatch) begin
                pass_count++;
                $display("[PASS] K-tiling accumulation test (2 tiles)");
            end else begin
                $display("!!! K-TILING TEST FAILED !!!");
                $finish;
            end
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
        #(CLK_PERIOD * 500000);
        $display("");
        $display("!!! SIMULATION TIMEOUT !!!");
        $display("");
        $finish;
    end

    //-------------------------------------------------------------------------
    // Waveform Dump
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("top_pe_tb.vcd");
        $dumpvars(0, top_pe_tb);
    end

endmodule
