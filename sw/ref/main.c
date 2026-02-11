//-----------------------------------------------------------------------------
// NPU Reference Test Program
// Description: Generates reference hex data for RTL verification
//              Seed-based random test generation for MAC / GEMV / GEMM
//              Usage: ./npu_ref [seed]  (default seed = 42)
//-----------------------------------------------------------------------------

#include "npu_ref.h"

#define HEX_DIR "hex_data/"

// Test result tracking
static int total_tests = 0;
static int passed_tests = 0;

#define TEST_ASSERT(cond, msg) do { \
    total_tests++; \
    if (cond) { passed_tests++; printf("  [PASS] %s\n", msg); } \
    else { printf("  [FAIL] %s\n", msg); } \
} while(0)

//=============================================================================
// MAC TEST HEX GENERATION (seed-based random)
//=============================================================================

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

void generate_mac_test_hex(int seed) {
    printf("\n");
    printf("=============================================================\n");
    printf("MAC Unit Test Hex Generation (seed=%d)\n", seed);
    printf("=============================================================\n");

    mac_op_count = 0;
    mac_acc = 0;

    srand(seed);

    // Generate multiple accumulation groups with random data
    int num_groups = 10 + (rand() % 11);  // 10~20 groups

    for (int g = 0; g < num_groups; g++) {
        int group_len = 4 + (rand() % 29);  // 4~32 ops per group

        for (int i = 0; i < group_len; i++) {
            int clear = (i == 0) ? 1 : 0;
            int8_t input  = (int8_t)((rand() % 256) - 128);
            int8_t weight = (int8_t)((rand() % 256) - 128);
            mac_add_op(clear, input, weight);
        }
    }

    printf("  Total MAC operations: %d\n", mac_op_count);

    // Dump hex files
    FILE *f_in  = fopen(HEX_DIR "mac_test_input.hex", "w");
    FILE *f_wt  = fopen(HEX_DIR "mac_test_weight.hex", "w");
    FILE *f_clr = fopen(HEX_DIR "mac_test_clear.hex", "w");
    FILE *f_exp = fopen(HEX_DIR "mac_test_expected.hex", "w");

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
// GEMV SUB-ARRAY TEST HEX GENERATION (fixed filenames for TB)
//=============================================================================

#define GEMV_SUBARRAY_NUM_TESTS 20

void generate_gemv_subarray_test_hex(int seed) {
    printf("\n");
    printf("=============================================================\n");
    printf("GEMV Sub-array Test Hex Generation (seed=%d)\n", seed);
    printf("=============================================================\n");

    int num_tests   = GEMV_SUBARRAY_NUM_TESTS;
    int input_size  = SUBARRAY_COLS;                    // 8
    int weight_size = SUBARRAY_ROWS * SUBARRAY_COLS;    // 256
    int output_size = SUBARRAY_ROWS;                    // 32

    int8_t*  all_input  = (int8_t*)calloc(num_tests * input_size, sizeof(int8_t));
    int8_t*  all_weight = (int8_t*)calloc(num_tests * weight_size, sizeof(int8_t));
    int32_t* all_output = (int32_t*)calloc(num_tests * output_size, sizeof(int32_t));

    srand(seed);

    for (int t = 0; t < num_tests; t++) {
        int8_t*  input  = &all_input[t * input_size];
        int8_t*  weight = &all_weight[t * weight_size];
        int32_t* output = &all_output[t * output_size];

        // Generate random input and weight
        for (int i = 0; i < input_size; i++)
            input[i] = (int8_t)((rand() % 256) - 128);
        for (int i = 0; i < weight_size; i++)
            weight[i] = (int8_t)((rand() % 256) - 128);

        // Compute expected output: output[r] = sum_c(weight[r*cols+c] * input[c])
        for (int r = 0; r < SUBARRAY_ROWS; r++) {
            int32_t sum = 0;
            for (int c = 0; c < SUBARRAY_COLS; c++) {
                sum += (int32_t)weight[r * SUBARRAY_COLS + c] * (int32_t)input[c];
            }
            output[r] = sum;
        }
    }

    printf("  Total test cases: %d\n", num_tests);

    // Dump hex files (fixed names, no seed in filename)
    dump_to_hex_file(HEX_DIR "gemv_test_input.hex",  all_input,  num_tests * input_size, 8);
    dump_to_hex_file(HEX_DIR "gemv_test_weight.hex", all_weight, num_tests * weight_size, 8);
    dump_to_hex_file(HEX_DIR "gemv_test_output.hex", all_output, num_tests * output_size, 32);

    free(all_input);
    free(all_weight);
    free(all_output);
}

//=============================================================================
// GEMV CTRL TEST HEX GENERATION (for gemv_ctrl_tb)
//=============================================================================

#define CTRL_ROWS      16
#define CTRL_COLS      4
#define CTRL_NUM_TESTS 8
#define CTRL_MAX_K     32

void generate_gemv_ctrl_test_hex(int seed) {
    printf("\n");
    printf("=============================================================\n");
    printf("GEMV Ctrl Test Hex Generation (seed=%d)\n", seed);
    printf("=============================================================\n");
    printf("  ROWS=%d, COLS=%d, NUM_TESTS=%d, MAX_K=%d\n",
           CTRL_ROWS, CTRL_COLS, CTRL_NUM_TESTS, CTRL_MAX_K);

    int dim_k_values[CTRL_NUM_TESTS] = {4, 8, 12, 16, 20, 24, 28, 32};

    // Allocate arrays with MAX_K stride (zero-padded)
    int total_input  = CTRL_NUM_TESTS * CTRL_MAX_K;
    int total_weight = CTRL_NUM_TESTS * CTRL_ROWS * CTRL_MAX_K;
    int total_output = CTRL_NUM_TESTS * CTRL_ROWS;

    int8_t*  all_input  = (int8_t*)calloc(total_input, sizeof(int8_t));
    int8_t*  all_weight = (int8_t*)calloc(total_weight, sizeof(int8_t));
    int32_t* all_output = (int32_t*)calloc(total_output, sizeof(int32_t));

    srand(seed);

    for (int t = 0; t < CTRL_NUM_TESTS; t++) {
        int dim_k = dim_k_values[t];
        int base_input  = t * CTRL_MAX_K;
        int base_weight = t * CTRL_ROWS * CTRL_MAX_K;
        int base_output = t * CTRL_ROWS;

        // Generate random input (only dim_k entries, rest stays 0)
        for (int k = 0; k < dim_k; k++)
            all_input[base_input + k] = (int8_t)((rand() % 256) - 128);

        // Generate random weight (only dim_k columns per row, rest stays 0)
        for (int r = 0; r < CTRL_ROWS; r++)
            for (int k = 0; k < dim_k; k++)
                all_weight[base_weight + r * CTRL_MAX_K + k] =
                    (int8_t)((rand() % 256) - 128);

        // Compute expected output: tile-based accumulation (mimics RTL)
        int num_tiles = (dim_k + CTRL_COLS - 1) / CTRL_COLS;
        for (int r = 0; r < CTRL_ROWS; r++)
            all_output[base_output + r] = 0;

        for (int tile = 0; tile < num_tiles; tile++) {
            for (int r = 0; r < CTRL_ROWS; r++) {
                for (int c = 0; c < CTRL_COLS; c++) {
                    int k = tile * CTRL_COLS + c;
                    int8_t inp = all_input[base_input + k];
                    int8_t wgt = all_weight[base_weight + r * CTRL_MAX_K + k];
                    all_output[base_output + r] += (int32_t)inp * (int32_t)wgt;
                }
            }
        }

        printf("  Test %d: dim_k=%d, num_tiles=%d\n", t, dim_k, num_tiles);
    }

    // Dump hex files
    dump_to_hex_file(HEX_DIR "gemv_ctrl_test_input.hex",
                     all_input, total_input, 8);
    dump_to_hex_file(HEX_DIR "gemv_ctrl_test_weight.hex",
                     all_weight, total_weight, 8);
    dump_to_hex_file(HEX_DIR "gemv_ctrl_test_output.hex",
                     all_output, total_output, 32);

    // Dump dim_k values as 32-bit hex
    FILE *f_dimk = fopen(HEX_DIR "gemv_ctrl_test_dimk.hex", "w");
    if (!f_dimk) {
        printf("ERROR: Cannot open dimk hex file!\n");
    } else {
        for (int t = 0; t < CTRL_NUM_TESTS; t++)
            fprintf(f_dimk, "%08X\n", (uint32_t)dim_k_values[t]);
        fclose(f_dimk);
    }

    printf("  Generated: gemv_ctrl_test_input.hex  (%d entries, 8bit)\n", total_input);
    printf("  Generated: gemv_ctrl_test_weight.hex (%d entries, 8bit)\n", total_weight);
    printf("  Generated: gemv_ctrl_test_output.hex (%d entries, 32bit)\n", total_output);
    printf("  Generated: gemv_ctrl_test_dimk.hex   (%d entries, 32bit)\n", CTRL_NUM_TESTS);

    free(all_input);
    free(all_weight);
    free(all_output);
}

//=============================================================================
// GEMV TEST (seed-based random, with tiled vs direct verification)
//=============================================================================

void test_gemv(int seed, int input_dim, int output_dim) {
    printf("\n");
    printf("=============================================================\n");
    printf("GEMV Test (seed=%d, input=%d, output=%d)\n", seed, input_dim, output_dim);
    printf("=============================================================\n");

    // Random input and weights
    int8_t* input   = (int8_t*)calloc(input_dim, sizeof(int8_t));
    int8_t* weights = (int8_t*)calloc(output_dim * input_dim, sizeof(int8_t));
    int32_t* output_tiled  = (int32_t*)calloc(output_dim, sizeof(int32_t));
    int32_t* output_direct = (int32_t*)calloc(output_dim, sizeof(int32_t));

    generate_random_i8(input, input_dim, seed);
    generate_random_i8(weights, output_dim * input_dim, seed + 1000);

    // Tiled computation (matches NPU behavior)
    ref_gemv_tiled(input, weights, output_tiled, input_dim, output_dim);

    // Direct computation (golden reference)
    for (int o = 0; o < output_dim; o++) {
        output_direct[o] = 0;
        for (int i = 0; i < input_dim; i++) {
            output_direct[o] += (int32_t)weights[o * input_dim + i] * (int32_t)input[i];
        }
    }

    // Verify tiled vs direct
    int pass = 1;
    for (int o = 0; o < output_dim; o++) {
        if (output_tiled[o] != output_direct[o]) {
            printf("  Mismatch at [%d]: tiled=%d, direct=%d\n",
                   o, output_tiled[o], output_direct[o]);
            pass = 0;
        }
    }

    char msg[128];
    sprintf(msg, "GEMV tiled vs direct (seed=%d, %dx%d)", seed, output_dim, input_dim);
    TEST_ASSERT(pass, msg);

    // Output stats
    int32_t min_out = output_tiled[0], max_out = output_tiled[0];
    for (int o = 1; o < output_dim; o++) {
        if (output_tiled[o] < min_out) min_out = output_tiled[o];
        if (output_tiled[o] > max_out) max_out = output_tiled[o];
    }
    printf("  Output range: [%d, %d]\n", min_out, max_out);
    printf("  Tiles: %d x %d\n",
           (output_dim + SUBARRAY_ROWS - 1) / SUBARRAY_ROWS,
           (input_dim + SUBARRAY_COLS - 1) / SUBARRAY_COLS);

    // Note: hex files for TB are generated by generate_gemv_subarray_test_hex()
    // test_gemv() is for tiled vs direct verification only

    free(input);
    free(weights);
    free(output_tiled);
    free(output_direct);
}

//=============================================================================
// GEMM TEST (seed-based random, with tiled vs direct verification)
//=============================================================================

void test_gemm(int seed, int M, int K, int N) {
    printf("\n");
    printf("=============================================================\n");
    printf("GEMM Test (seed=%d, M=%d, K=%d, N=%d)\n", seed, M, K, N);
    printf("=============================================================\n");

    int8_t* A = (int8_t*)calloc(M * K, sizeof(int8_t));
    int8_t* B = (int8_t*)calloc(K * N, sizeof(int8_t));
    int32_t* C_tiled  = (int32_t*)calloc(M * N, sizeof(int32_t));
    int32_t* C_direct = (int32_t*)calloc(M * N, sizeof(int32_t));

    generate_random_i8(A, M * K, seed);
    generate_random_i8(B, K * N, seed + 2000);

    // Tiled computation (matches NPU behavior)
    ref_gemm_tiled(A, B, C_tiled, M, K, N);

    // Direct computation (golden reference)
    for (int m = 0; m < M; m++) {
        for (int n = 0; n < N; n++) {
            int32_t sum = 0;
            for (int k = 0; k < K; k++) {
                sum += (int32_t)A[m * K + k] * (int32_t)B[k * N + n];
            }
            C_direct[m * N + n] = sum;
        }
    }

    // Verify tiled vs direct
    int pass = 1;
    int mismatch_count = 0;
    for (int i = 0; i < M * N; i++) {
        if (C_tiled[i] != C_direct[i]) {
            if (mismatch_count < 5) {
                printf("  Mismatch at [%d][%d]: tiled=%d, direct=%d\n",
                       i / N, i % N, C_tiled[i], C_direct[i]);
            }
            mismatch_count++;
            pass = 0;
        }
    }
    if (mismatch_count > 5) {
        printf("  ... and %d more mismatches\n", mismatch_count - 5);
    }

    char msg[128];
    sprintf(msg, "GEMM tiled vs direct (seed=%d, %dx%dx%d)", seed, M, K, N);
    TEST_ASSERT(pass, msg);

    // Output stats
    int32_t min_out = C_tiled[0], max_out = C_tiled[0];
    for (int i = 1; i < M * N; i++) {
        if (C_tiled[i] < min_out) min_out = C_tiled[i];
        if (C_tiled[i] > max_out) max_out = C_tiled[i];
    }
    printf("  Output range: [%d, %d]\n", min_out, max_out);
    printf("  Tiles (M x K): %d x %d\n",
           (M + SUBARRAY_ROWS - 1) / SUBARRAY_ROWS,
           (K + SUBARRAY_COLS - 1) / SUBARRAY_COLS);

    // Dump hex files
    char fname[128];
    sprintf(fname, HEX_DIR "gemm_s%d_a.hex", seed);
    dump_to_hex_file(fname, A, M * K, 8);
    sprintf(fname, HEX_DIR "gemm_s%d_b.hex", seed);
    dump_to_hex_file(fname, B, K * N, 8);
    sprintf(fname, HEX_DIR "gemm_s%d_c.hex", seed);
    dump_to_hex_file(fname, C_tiled, M * N, 32);

    free(A);
    free(B);
    free(C_tiled);
    free(C_direct);
}

//=============================================================================
// MAIN
//=============================================================================

int main(int argc, char* argv[]) {
    int seed = 42;
    if (argc > 1) seed = atoi(argv[1]);

    printf("\n");
    printf("*************************************************************\n");
    printf("*     NPU Reference Model - Seed-based Test Generator       *\n");
    printf("*************************************************************\n");
    printf("\n");
    printf("  Seed: %d\n", seed);
    printf("  Sub-array: %d x %d\n", SUBARRAY_ROWS, SUBARRAY_COLS);
    printf("  Data types: INT8 input/weight, INT32 accumulator\n");

    //=========================================================================
    // MAC Unit Hex Generation
    //=========================================================================
    printf("\n\n>>> MAC UNIT HEX GENERATION <<<\n");
    generate_mac_test_hex(seed);

    //=========================================================================
    // GEMV Sub-array Hex Generation (for gemv_subarray_tb)
    //=========================================================================
    printf("\n\n>>> GEMV SUB-ARRAY HEX GENERATION <<<\n");
    generate_gemv_subarray_test_hex(seed);

    //=========================================================================
    // GEMV Ctrl Test Hex Generation (for gemv_ctrl_tb)
    //=========================================================================
    printf("\n\n>>> GEMV CTRL TEST HEX GENERATION <<<\n");
    generate_gemv_ctrl_test_hex(seed);

    //=========================================================================
    // GEMV Tests (various dimensions, tiled vs direct verification)
    //=========================================================================
    printf("\n\n>>> GEMV TESTS <<<\n");

    // Single sub-array size (32x8)
    test_gemv(seed,     SUBARRAY_COLS, SUBARRAY_ROWS);
    // Tiling in input dimension (32x32)
    test_gemv(seed + 1, 32, SUBARRAY_ROWS);
    // Tiling in both dimensions (64x128)
    test_gemv(seed + 2, 64, 128);

    //=========================================================================
    // GEMM Tests (various dimensions)
    //=========================================================================
    printf("\n\n>>> GEMM TESTS <<<\n");

    // Small (fits sub-array)
    test_gemm(seed,     SUBARRAY_ROWS, SUBARRAY_COLS, 16);
    // Medium (requires tiling)
    test_gemm(seed + 1, 64, 32, 64);
    // Large
    test_gemm(seed + 2, 128, 64, 128);

    //=========================================================================
    // Summary
    //=========================================================================
    printf("\n");
    printf("*************************************************************\n");
    printf("*                    TEST SUMMARY                           *\n");
    printf("*************************************************************\n");
    printf("\n");
    printf("  Seed:         %d\n", seed);
    printf("  Total tests:  %d\n", total_tests);
    printf("  Passed:       %d\n", passed_tests);
    printf("  Failed:       %d\n", total_tests - passed_tests);
    printf("\n");

    if (passed_tests == total_tests) {
        printf("  *** ALL TESTS PASSED ***\n");
    } else {
        printf("  *** SOME TESTS FAILED ***\n");
    }

    printf("\n");
    printf("Generated hex files in current directory.\n");
    printf("Re-run with different seed: ./npu_ref <seed>\n");
    printf("\n");

    return (passed_tests == total_tests) ? 0 : 1;
}
