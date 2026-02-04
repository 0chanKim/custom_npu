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

    // Dump hex files
    char fname[128];
    sprintf(fname, HEX_DIR "gemv_s%d_input.hex", seed);
    dump_to_hex_file(fname, input, input_dim, 8);
    sprintf(fname, HEX_DIR "gemv_s%d_weight.hex", seed);
    dump_to_hex_file(fname, weights, output_dim * input_dim, 8);
    sprintf(fname, HEX_DIR "gemv_s%d_output.hex", seed);
    dump_to_hex_file(fname, output_tiled, output_dim, 32);

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
    // GEMV Tests (various dimensions)
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
