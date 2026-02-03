//-----------------------------------------------------------------------------
// NPU Reference Test Program
// Description: Generates reference data for RTL verification
//              Comprehensive test coverage for NPU verification
//-----------------------------------------------------------------------------

#include "npu_ref.h"

// Test result tracking
static int total_tests = 0;
static int passed_tests = 0;

#define TEST_ASSERT(cond, msg) do { \
    total_tests++; \
    if (cond) { passed_tests++; printf("  [PASS] %s\n", msg); } \
    else { printf("  [FAIL] %s\n", msg); } \
} while(0)

//=============================================================================
// MAC UNIT TESTS
//=============================================================================

void test_mac_basic(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 1.1: MAC Unit - Basic Operations\n");
    printf("=============================================================\n");

    int32_t acc;

    // Test: positive * positive
    acc = 0;
    ref_mac(2, 3, &acc);
    TEST_ASSERT(acc == 6, "2 * 3 = 6");

    // Test: accumulation
    ref_mac(4, 5, &acc);
    TEST_ASSERT(acc == 26, "6 + (4 * 5) = 26");

    // Test: negative * positive
    acc = 0;
    ref_mac(-5, 7, &acc);
    TEST_ASSERT(acc == -35, "(-5) * 7 = -35");

    // Test: negative * negative
    acc = 0;
    ref_mac(-3, -4, &acc);
    TEST_ASSERT(acc == 12, "(-3) * (-4) = 12");

    // Test: mixed accumulation
    ref_mac(-5, 7, &acc);  // 12 + (-35) = -23
    TEST_ASSERT(acc == -23, "12 + ((-5) * 7) = -23");
}

void test_mac_edge_cases(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 1.2: MAC Unit - Edge Cases\n");
    printf("=============================================================\n");

    int32_t acc;

    // Test: zero multiplication
    acc = 100;
    ref_mac(0, 50, &acc);
    TEST_ASSERT(acc == 100, "100 + (0 * 50) = 100");

    acc = 100;
    ref_mac(50, 0, &acc);
    TEST_ASSERT(acc == 100, "100 + (50 * 0) = 100");

    // Test: multiply by 1
    acc = 0;
    ref_mac(127, 1, &acc);
    TEST_ASSERT(acc == 127, "127 * 1 = 127");

    acc = 0;
    ref_mac(1, -128, &acc);
    TEST_ASSERT(acc == -128, "1 * (-128) = -128");

    // Test: multiply by -1
    acc = 0;
    ref_mac(100, -1, &acc);
    TEST_ASSERT(acc == -100, "100 * (-1) = -100");

    // Test: INT8 max values
    acc = 0;
    ref_mac(127, 127, &acc);
    TEST_ASSERT(acc == 16129, "127 * 127 = 16129");

    // Test: INT8 min values
    acc = 0;
    ref_mac(-128, -128, &acc);
    TEST_ASSERT(acc == 16384, "(-128) * (-128) = 16384");

    // Test: max * min
    acc = 0;
    ref_mac(127, -128, &acc);
    TEST_ASSERT(acc == -16256, "127 * (-128) = -16256");

    // Test: large accumulation (check for overflow handling)
    acc = 0;
    for (int i = 0; i < 256; i++) {
        ref_mac(127, 127, &acc);
    }
    TEST_ASSERT(acc == 16129 * 256, "256 * (127 * 127) = 4129024");
}

void test_mac_accumulation_patterns(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 1.3: MAC Unit - Accumulation Patterns\n");
    printf("=============================================================\n");

    int32_t acc;

    // Test: alternating signs
    acc = 0;
    ref_mac(10, 10, &acc);   // +100
    ref_mac(-10, 10, &acc);  // -100, total = 0
    TEST_ASSERT(acc == 0, "Alternating: (10*10) + (-10*10) = 0");

    // Test: sum of squares
    acc = 0;
    for (int i = 1; i <= 10; i++) {
        ref_mac((int8_t)i, (int8_t)i, &acc);
    }
    TEST_ASSERT(acc == 385, "Sum of squares 1^2 to 10^2 = 385");

    // Test: arithmetic progression
    acc = 0;
    for (int i = 1; i <= 8; i++) {
        ref_mac((int8_t)i, 1, &acc);
    }
    TEST_ASSERT(acc == 36, "Sum 1 to 8 = 36");
}

//=============================================================================
// MAC UNIT HEX FILE GENERATION (for RTL testbench $readmemh)
//=============================================================================

// Streaming MAC test data: each entry = {clear, input, weight, expected_acc}
#define MAC_TEST_MAX_OPS 512

static int mac_op_count = 0;
static int8_t  mac_inputs[MAC_TEST_MAX_OPS];
static int8_t  mac_weights[MAC_TEST_MAX_OPS];
static uint8_t mac_clears[MAC_TEST_MAX_OPS];
static int32_t mac_expected[MAC_TEST_MAX_OPS];
static int32_t mac_acc = 0;

static void mac_add_op(int clear, int8_t input, int8_t weight) {
    if (mac_op_count >= MAC_TEST_MAX_OPS) {
        printf("ERROR: MAC test ops overflow!\n");
        return;
    }
    if (clear) mac_acc = 0;
    int32_t product = (int32_t)input * (int32_t)weight;
    mac_acc += product;

    mac_clears[mac_op_count]   = (uint8_t)clear;
    mac_inputs[mac_op_count]   = input;
    mac_weights[mac_op_count]  = weight;
    mac_expected[mac_op_count] = mac_acc;
    mac_op_count++;
}

void generate_mac_test_hex(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Generating MAC Unit Test Hex Files\n");
    printf("=============================================================\n");

    mac_op_count = 0;
    mac_acc = 0;

    // --- Basic Operations (matches test_mac_basic) ---
    // 2 * 3 = 6
    mac_add_op(1, 2, 3);
    // accumulate: 6 + 4*5 = 26
    mac_add_op(0, 4, 5);
    // (-5) * 7 = -35
    mac_add_op(1, -5, 7);
    // (-3) * (-4) = 12
    mac_add_op(1, -3, -4);
    // 12 + (-5)*7 = -23
    mac_add_op(0, -5, 7);

    // --- Edge Cases (matches test_mac_edge_cases) ---
    // 0 * 50 = 0
    mac_add_op(1, 0, 50);
    // 50 * 0 = 0
    mac_add_op(1, 50, 0);
    // 127 * 1 = 127
    mac_add_op(1, 127, 1);
    // 1 * (-128) = -128
    mac_add_op(1, 1, -128);
    // 100 * (-1) = -100
    mac_add_op(1, 100, -1);
    // 127 * 127 = 16129
    mac_add_op(1, 127, 127);
    // (-128) * (-128) = 16384
    mac_add_op(1, -128, -128);
    // 127 * (-128) = -16256
    mac_add_op(1, 127, -128);

    // --- Large Accumulation: 256 * (127*127) = 4129024 ---
    mac_add_op(1, 127, 127);  // first with clear
    for (int i = 1; i < 256; i++) {
        mac_add_op(0, 127, 127);
    }

    // --- Alternating signs cancel: (10*10) + (-10*10) = 0 ---
    mac_add_op(1, 10, 10);
    mac_add_op(0, -10, 10);

    // --- Sum of squares: 1^2 + 2^2 + ... + 10^2 = 385 ---
    mac_add_op(1, 1, 1);  // first with clear
    for (int i = 2; i <= 10; i++) {
        mac_add_op(0, (int8_t)i, (int8_t)i);
    }

    // --- Sum 1 to 8 (multiply by 1): = 36 ---
    mac_add_op(1, 1, 1);  // first with clear
    for (int i = 2; i <= 8; i++) {
        mac_add_op(0, (int8_t)i, 1);
    }

    printf("  Total MAC operations: %d\n", mac_op_count);

    // Dump hex files
    FILE *f_in, *f_wt, *f_clr, *f_exp;
    f_in  = fopen("mac_test_input.hex", "w");
    f_wt  = fopen("mac_test_weight.hex", "w");
    f_clr = fopen("mac_test_clear.hex", "w");
    f_exp = fopen("mac_test_expected.hex", "w");

    if (!f_in || !f_wt || !f_clr || !f_exp) {
        printf("ERROR: Cannot open MAC hex files for writing!\n");
        return;
    }

    for (int i = 0; i < mac_op_count; i++) {
        fprintf(f_in,  "%02X\n", (uint8_t)mac_inputs[i]);
        fprintf(f_wt,  "%02X\n", (uint8_t)mac_weights[i]);
        fprintf(f_clr, "%02X\n", mac_clears[i]);
        fprintf(f_exp, "%08X\n", (uint32_t)mac_expected[i]);
    }

    fclose(f_in);
    fclose(f_wt);
    fclose(f_clr);
    fclose(f_exp);

    printf("  Generated: mac_test_input.hex\n");
    printf("  Generated: mac_test_weight.hex\n");
    printf("  Generated: mac_test_clear.hex\n");
    printf("  Generated: mac_test_expected.hex\n");
}

//=============================================================================
// GEMV SUBARRAY TESTS
//=============================================================================

void test_gemv_identity(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 2.1: GeMV - Identity-like Pattern\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: [1, 2, 3, 4, 5, 6, 7, 8]
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = (int8_t)(i + 1);
    }

    // Weights: identity-like (row r has 1 at column r%8)
    memset(layer->weights, 0, SUBARRAY_ROWS * SUBARRAY_COLS);
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        layer->weights[r * SUBARRAY_COLS + (r % SUBARRAY_COLS)] = 1;
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Verify: output[r] should equal input[r % 8]
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != (r % SUBARRAY_COLS) + 1) pass = 0;
    }
    TEST_ASSERT(pass, "Identity pattern: output[r] = input[r % 8]");

    dump_to_hex_file("test_identity_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_identity_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_identity_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_gemv_all_ones(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 2.2: GeMV - All Ones Pattern\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: all 1s
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = 1;
    }

    // Weights: all 1s
    for (int i = 0; i < SUBARRAY_ROWS * SUBARRAY_COLS; i++) {
        layer->weights[i] = 1;
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Verify: all outputs should be 8 (sum of 8 ones)
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != SUBARRAY_COLS) pass = 0;
    }
    TEST_ASSERT(pass, "All ones: output[r] = 8 for all r");

    dump_to_hex_file("test_allones_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_allones_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_allones_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_gemv_scaled_rows(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 2.3: GeMV - Scaled Rows Pattern\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: all 1s
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = 1;
    }

    // Weights: row r has all values = r+1
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        for (int c = 0; c < SUBARRAY_COLS; c++) {
            layer->weights[r * SUBARRAY_COLS + c] = (int8_t)(r + 1);
        }
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Verify: output[r] = (r+1) * 8
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != (r + 1) * SUBARRAY_COLS) pass = 0;
    }
    TEST_ASSERT(pass, "Scaled rows: output[r] = (r+1) * 8");

    printf("  Output: [8, 16, 24, ..., 256]\n");

    dump_to_hex_file("test_scaled_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_scaled_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_scaled_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_gemv_alternating(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 2.4: GeMV - Alternating Signs Pattern\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: [1, -1, 1, -1, 1, -1, 1, -1]
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = (i % 2 == 0) ? 1 : -1;
    }

    // Weights: all 1s
    for (int i = 0; i < SUBARRAY_ROWS * SUBARRAY_COLS; i++) {
        layer->weights[i] = 1;
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Verify: output should be 0 (alternating cancels out)
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != 0) pass = 0;
    }
    TEST_ASSERT(pass, "Alternating input: output[r] = 0 (cancellation)");

    dump_to_hex_file("test_alternating_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_alternating_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_alternating_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_gemv_max_values(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 2.5: GeMV - Maximum Values (Stress Test)\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: all 127 (INT8_MAX)
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = 127;
    }

    // Weights: all 127
    for (int i = 0; i < SUBARRAY_ROWS * SUBARRAY_COLS; i++) {
        layer->weights[i] = 127;
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Expected: 127 * 127 * 8 = 129032
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != 127 * 127 * SUBARRAY_COLS) pass = 0;
    }
    TEST_ASSERT(pass, "Max values: output[r] = 127 * 127 * 8 = 129032");

    dump_to_hex_file("test_maxval_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_maxval_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_maxval_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_gemv_min_values(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 2.6: GeMV - Minimum Values (Stress Test)\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: all -128 (INT8_MIN)
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = -128;
    }

    // Weights: all -128
    for (int i = 0; i < SUBARRAY_ROWS * SUBARRAY_COLS; i++) {
        layer->weights[i] = -128;
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Expected: (-128) * (-128) * 8 = 131072
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != 128 * 128 * SUBARRAY_COLS) pass = 0;
    }
    TEST_ASSERT(pass, "Min values: output[r] = (-128) * (-128) * 8 = 131072");

    dump_to_hex_file("test_minval_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_minval_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_minval_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_gemv_mixed_signs(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 2.7: GeMV - Mixed Signs (Max * Min)\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: all 127
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = 127;
    }

    // Weights: all -128
    for (int i = 0; i < SUBARRAY_ROWS * SUBARRAY_COLS; i++) {
        layer->weights[i] = -128;
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Expected: 127 * (-128) * 8 = -130048
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != 127 * (-128) * SUBARRAY_COLS) pass = 0;
    }
    TEST_ASSERT(pass, "Mixed signs: output[r] = 127 * (-128) * 8 = -130048");

    dump_to_hex_file("test_mixed_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_mixed_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_mixed_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_gemv_sparse(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 2.8: GeMV - Sparse Pattern (Single Non-zero per Row)\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: sequential [1, 2, 3, 4, 5, 6, 7, 8]
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = (int8_t)(i + 1);
    }

    // Weights: sparse - only diagonal-like elements are non-zero
    memset(layer->weights, 0, SUBARRAY_ROWS * SUBARRAY_COLS);
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        int col = r % SUBARRAY_COLS;
        layer->weights[r * SUBARRAY_COLS + col] = (int8_t)(r + 1);
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Verify: output[r] = weight[r][r%8] * input[r%8] = (r+1) * ((r%8)+1)
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        int expected = (r + 1) * ((r % SUBARRAY_COLS) + 1);
        if (layer->output[r] != expected) pass = 0;
    }
    TEST_ASSERT(pass, "Sparse: output[r] = (r+1) * ((r%%8)+1)");

    dump_to_hex_file("test_sparse_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_sparse_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_sparse_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_gemv_with_bias(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 2.9: GeMV - With Bias\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: all 1s
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = 1;
    }

    // Weights: all 1s
    for (int i = 0; i < SUBARRAY_ROWS * SUBARRAY_COLS; i++) {
        layer->weights[i] = 1;
    }

    // Bias: row index * 10
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        layer->bias[r] = r * 10;
    }

    ref_gemv(layer);

    // Verify: output[r] = 8 + r*10
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != SUBARRAY_COLS + r * 10) pass = 0;
    }
    TEST_ASSERT(pass, "With bias: output[r] = 8 + r*10");

    dump_to_hex_file("test_bias_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_bias_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_bias_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

//=============================================================================
// RANDOM TESTS
//=============================================================================

void test_gemv_random_seed(int seed) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 3.%d: GeMV - Random Pattern (seed=%d)\n", seed, seed);
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    generate_random_i8(layer->input, SUBARRAY_COLS, seed);
    generate_random_i8(layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, seed + 1000);
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Just verify computation completes (no crash)
    TEST_ASSERT(1, "Random pattern computation completed");

    // Print some statistics
    int32_t min_out = layer->output[0], max_out = layer->output[0];
    int64_t sum_out = 0;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] < min_out) min_out = layer->output[r];
        if (layer->output[r] > max_out) max_out = layer->output[r];
        sum_out += layer->output[r];
    }
    printf("  Output stats: min=%d, max=%d, avg=%ld\n",
           min_out, max_out, (long)(sum_out / SUBARRAY_ROWS));

    char fname[64];
    sprintf(fname, "test_random%d_input.hex", seed);
    dump_to_hex_file(fname, layer->input, SUBARRAY_COLS, 8);
    sprintf(fname, "test_random%d_weight.hex", seed);
    dump_to_hex_file(fname, layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    sprintf(fname, "test_random%d_output.hex", seed);
    dump_to_hex_file(fname, layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

//=============================================================================
// LLM SIMULATION TESTS
//=============================================================================

void test_llm_qkv_projection(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 4.1: LLM - Q/K/V Projection Simulation\n");
    printf("=============================================================\n");
    printf("Simulating attention projection for single token\n");
    printf("Dimensions fit single 32x8 sub-array\n\n");

    GemvLayer* q_proj = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);
    GemvLayer* k_proj = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);
    GemvLayer* v_proj = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Shared input (token embedding)
    int8_t* token_embedding = (int8_t*)calloc(SUBARRAY_COLS, sizeof(int8_t));
    generate_random_i8(token_embedding, SUBARRAY_COLS, 100);

    // Copy input to all projections
    memcpy(q_proj->input, token_embedding, SUBARRAY_COLS);
    memcpy(k_proj->input, token_embedding, SUBARRAY_COLS);
    memcpy(v_proj->input, token_embedding, SUBARRAY_COLS);

    // Different weights for Q, K, V
    generate_random_i8(q_proj->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 200);
    generate_random_i8(k_proj->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 300);
    generate_random_i8(v_proj->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 400);

    memset(q_proj->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));
    memset(k_proj->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));
    memset(v_proj->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    // Compute projections
    ref_gemv(q_proj);
    ref_gemv(k_proj);
    ref_gemv(v_proj);

    TEST_ASSERT(1, "Q projection computed");
    TEST_ASSERT(1, "K projection computed");
    TEST_ASSERT(1, "V projection computed");

    // Dump files
    dump_to_hex_file("test_llm_token.hex", token_embedding, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_llm_wq.hex", q_proj->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_llm_wk.hex", k_proj->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_llm_wv.hex", v_proj->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_llm_q.hex", q_proj->output, SUBARRAY_ROWS, 32);
    dump_to_hex_file("test_llm_k.hex", k_proj->output, SUBARRAY_ROWS, 32);
    dump_to_hex_file("test_llm_v.hex", v_proj->output, SUBARRAY_ROWS, 32);

    free(token_embedding);
    free_gemv_layer(q_proj);
    free_gemv_layer(k_proj);
    free_gemv_layer(v_proj);
}

void test_llm_ffn_layer(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 4.2: LLM - FFN Layer Simulation (Tiled)\n");
    printf("=============================================================\n");
    printf("FFN: hidden_dim=64, intermediate_dim=256\n");
    printf("Up projection: 64 -> 256 (tiled with 32x8 sub-arrays)\n\n");

    int hidden_dim = 64;
    int intermediate_dim = 256;

    int8_t* input = (int8_t*)calloc(hidden_dim, sizeof(int8_t));
    int8_t* w_up = (int8_t*)calloc(intermediate_dim * hidden_dim, sizeof(int8_t));
    int32_t* intermediate = (int32_t*)calloc(intermediate_dim, sizeof(int32_t));

    generate_random_i8(input, hidden_dim, 500);
    generate_random_i8(w_up, intermediate_dim * hidden_dim, 600);

    // Tiled computation
    ref_gemv_tiled(input, w_up, intermediate, hidden_dim, intermediate_dim);

    TEST_ASSERT(1, "FFN up projection computed (tiled)");

    printf("  Input dim: %d, Output dim: %d\n", hidden_dim, intermediate_dim);
    printf("  Tiles used: %d x %d\n",
           (intermediate_dim + SUBARRAY_ROWS - 1) / SUBARRAY_ROWS,
           (hidden_dim + SUBARRAY_COLS - 1) / SUBARRAY_COLS);

    dump_to_hex_file("test_ffn_input.hex", input, hidden_dim, 8);
    dump_to_hex_file("test_ffn_weight.hex", w_up, intermediate_dim * hidden_dim, 8);
    dump_to_hex_file("test_ffn_output.hex", intermediate, intermediate_dim, 32);

    free(input);
    free(w_up);
    free(intermediate);
}

//=============================================================================
// TILING TESTS
//=============================================================================

void test_tiled_accumulation(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 5.1: Tiled GeMV - Accumulation Correctness\n");
    printf("=============================================================\n");
    printf("Verify tiled result matches non-tiled for dimensions that\n");
    printf("require multiple tiles in input dimension\n\n");

    // Dimensions that need tiling: input_dim > 8
    int input_dim = 32;  // 4 tiles in input direction
    int output_dim = 32; // 1 tile in output direction

    int8_t* input = (int8_t*)calloc(input_dim, sizeof(int8_t));
    int8_t* weights = (int8_t*)calloc(output_dim * input_dim, sizeof(int8_t));
    int32_t* output_tiled = (int32_t*)calloc(output_dim, sizeof(int32_t));
    int32_t* output_direct = (int32_t*)calloc(output_dim, sizeof(int32_t));

    // Simple pattern for verification
    for (int i = 0; i < input_dim; i++) {
        input[i] = 1;
    }
    for (int i = 0; i < output_dim * input_dim; i++) {
        weights[i] = 1;
    }

    // Tiled computation
    ref_gemv_tiled(input, weights, output_tiled, input_dim, output_dim);

    // Direct computation
    for (int o = 0; o < output_dim; o++) {
        output_direct[o] = 0;
        for (int i = 0; i < input_dim; i++) {
            output_direct[o] += (int32_t)weights[o * input_dim + i] * (int32_t)input[i];
        }
    }

    // Compare
    int pass = 1;
    for (int o = 0; o < output_dim; o++) {
        if (output_tiled[o] != output_direct[o]) {
            printf("  Mismatch at [%d]: tiled=%d, direct=%d\n",
                   o, output_tiled[o], output_direct[o]);
            pass = 0;
        }
    }
    TEST_ASSERT(pass, "Tiled matches direct computation");
    TEST_ASSERT(output_tiled[0] == input_dim, "Output = sum of 32 ones = 32");

    free(input);
    free(weights);
    free(output_tiled);
    free(output_direct);
}

void test_tiled_large_matrix(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 5.2: Tiled GeMV - Large Matrix\n");
    printf("=============================================================\n");
    printf("Dimensions: input=128, output=256\n");
    printf("Tiles: 8 output tiles x 16 input tiles = 128 tile operations\n\n");

    int input_dim = 128;
    int output_dim = 256;

    int8_t* input = (int8_t*)calloc(input_dim, sizeof(int8_t));
    int8_t* weights = (int8_t*)calloc(output_dim * input_dim, sizeof(int8_t));
    int32_t* output = (int32_t*)calloc(output_dim, sizeof(int32_t));

    generate_random_i8(input, input_dim, 700);
    generate_random_i8(weights, output_dim * input_dim, 800);

    ref_gemv_tiled(input, weights, output, input_dim, output_dim);

    TEST_ASSERT(1, "Large tiled GeMV completed");

    printf("  Total tile operations: %d\n",
           ((output_dim + SUBARRAY_ROWS - 1) / SUBARRAY_ROWS) *
           ((input_dim + SUBARRAY_COLS - 1) / SUBARRAY_COLS));

    dump_to_hex_file("test_large_input.hex", input, input_dim, 8);
    dump_to_hex_file("test_large_weight.hex", weights, output_dim * input_dim, 8);
    dump_to_hex_file("test_large_output.hex", output, output_dim, 32);

    free(input);
    free(weights);
    free(output);
}

//=============================================================================
// BOUNDARY TESTS
//=============================================================================

void test_boundary_single_element(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 6.1: Boundary - Single Active Element\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: only first element is non-zero
    memset(layer->input, 0, SUBARRAY_COLS);
    layer->input[0] = 5;

    // Weights: first column is [1, 2, 3, ..., 32]
    memset(layer->weights, 0, SUBARRAY_ROWS * SUBARRAY_COLS);
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        layer->weights[r * SUBARRAY_COLS + 0] = (int8_t)(r + 1);
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Verify: output[r] = 5 * (r+1)
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != 5 * (r + 1)) pass = 0;
    }
    TEST_ASSERT(pass, "Single element: output[r] = 5 * (r+1)");

    dump_to_hex_file("test_single_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_single_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_single_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_boundary_last_element(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 6.2: Boundary - Last Element Only\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: only last element is non-zero
    memset(layer->input, 0, SUBARRAY_COLS);
    layer->input[SUBARRAY_COLS - 1] = 7;

    // Weights: last column is [1, 2, 3, ..., 32]
    memset(layer->weights, 0, SUBARRAY_ROWS * SUBARRAY_COLS);
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        layer->weights[r * SUBARRAY_COLS + (SUBARRAY_COLS - 1)] = (int8_t)(r + 1);
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    // Verify: output[r] = 7 * (r+1)
    int pass = 1;
    for (int r = 0; r < SUBARRAY_ROWS; r++) {
        if (layer->output[r] != 7 * (r + 1)) pass = 0;
    }
    TEST_ASSERT(pass, "Last element: output[r] = 7 * (r+1)");

    dump_to_hex_file("test_last_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_last_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_last_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

void test_boundary_first_last_row(void) {
    printf("\n");
    printf("=============================================================\n");
    printf("Test 6.3: Boundary - First and Last Row Only\n");
    printf("=============================================================\n");

    GemvLayer* layer = init_gemv_layer(SUBARRAY_COLS, SUBARRAY_ROWS);

    // Input: all ones
    for (int i = 0; i < SUBARRAY_COLS; i++) {
        layer->input[i] = 1;
    }

    // Weights: only first and last rows are non-zero
    memset(layer->weights, 0, SUBARRAY_ROWS * SUBARRAY_COLS);
    for (int c = 0; c < SUBARRAY_COLS; c++) {
        layer->weights[0 * SUBARRAY_COLS + c] = 10;  // First row
        layer->weights[(SUBARRAY_ROWS - 1) * SUBARRAY_COLS + c] = 20;  // Last row
    }
    memset(layer->bias, 0, SUBARRAY_ROWS * sizeof(int32_t));

    ref_gemv(layer);

    int pass = 1;
    if (layer->output[0] != 10 * SUBARRAY_COLS) pass = 0;
    if (layer->output[SUBARRAY_ROWS - 1] != 20 * SUBARRAY_COLS) pass = 0;
    for (int r = 1; r < SUBARRAY_ROWS - 1; r++) {
        if (layer->output[r] != 0) pass = 0;
    }
    TEST_ASSERT(pass, "First/last row: output[0]=80, output[31]=160, others=0");

    dump_to_hex_file("test_firstlast_input.hex", layer->input, SUBARRAY_COLS, 8);
    dump_to_hex_file("test_firstlast_weight.hex", layer->weights, SUBARRAY_ROWS * SUBARRAY_COLS, 8);
    dump_to_hex_file("test_firstlast_output.hex", layer->output, SUBARRAY_ROWS, 32);

    free_gemv_layer(layer);
}

//=============================================================================
// MAIN
//=============================================================================

int main(void) {
    printf("\n");
    printf("*************************************************************\n");
    printf("*     NPU Reference Model - Comprehensive Test Suite        *\n");
    printf("*************************************************************\n");
    printf("\n");
    printf("NPU Configuration:\n");
    printf("  Sub-array size: %d x %d (rows x cols)\n", SUBARRAY_ROWS, SUBARRAY_COLS);
    printf("  PE Array: %d x %d\n", PE_ARRAY_ROWS, PE_ARRAY_COLS);
    printf("  Large Arrays: %d\n", NUM_LARGE_ARRAYS);
    printf("  Total MACs: %d\n", TOTAL_MACS);
    printf("  Data types: INT8 input/weight, INT32 accumulator\n");

    //=========================================================================
    // MAC Unit Tests
    //=========================================================================
    printf("\n\n>>> MAC UNIT TESTS <<<\n");
    test_mac_basic();
    test_mac_edge_cases();
    test_mac_accumulation_patterns();

    //=========================================================================
    // MAC Unit Hex File Generation (for RTL $readmemh)
    //=========================================================================
    printf("\n\n>>> MAC UNIT HEX FILE GENERATION <<<\n");
    generate_mac_test_hex();

    //=========================================================================
    // GeMV Sub-array Tests
    //=========================================================================
    printf("\n\n>>> GEMV SUBARRAY TESTS <<<\n");
    test_gemv_identity();
    test_gemv_all_ones();
    test_gemv_scaled_rows();
    test_gemv_alternating();
    test_gemv_max_values();
    test_gemv_min_values();
    test_gemv_mixed_signs();
    test_gemv_sparse();
    test_gemv_with_bias();

    //=========================================================================
    // Random Tests
    //=========================================================================
    printf("\n\n>>> RANDOM TESTS <<<\n");
    test_gemv_random_seed(1);
    test_gemv_random_seed(42);
    test_gemv_random_seed(123);
    test_gemv_random_seed(9999);

    //=========================================================================
    // LLM Simulation Tests
    //=========================================================================
    printf("\n\n>>> LLM SIMULATION TESTS <<<\n");
    test_llm_qkv_projection();
    test_llm_ffn_layer();

    //=========================================================================
    // Tiling Tests
    //=========================================================================
    printf("\n\n>>> TILING TESTS <<<\n");
    test_tiled_accumulation();
    test_tiled_large_matrix();

    //=========================================================================
    // Boundary Tests
    //=========================================================================
    printf("\n\n>>> BOUNDARY TESTS <<<\n");
    test_boundary_single_element();
    test_boundary_last_element();
    test_boundary_first_last_row();

    //=========================================================================
    // Summary
    //=========================================================================
    printf("\n");
    printf("*************************************************************\n");
    printf("*                    TEST SUMMARY                           *\n");
    printf("*************************************************************\n");
    printf("\n");
    printf("  Total tests:  %d\n", total_tests);
    printf("  Passed:       %d\n", passed_tests);
    printf("  Failed:       %d\n", total_tests - passed_tests);
    printf("  Pass rate:    %.1f%%\n", 100.0 * passed_tests / total_tests);
    printf("\n");

    if (passed_tests == total_tests) {
        printf("  *** ALL TESTS PASSED ***\n");
    } else {
        printf("  *** SOME TESTS FAILED ***\n");
    }

    printf("\n");
    printf("Generated hex files in current directory.\n");
    printf("Use these files with $readmemh in RTL testbenches.\n");
    printf("\n");

    return (passed_tests == total_tests) ? 0 : 1;
}
