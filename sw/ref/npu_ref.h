//-----------------------------------------------------------------------------
// NPU Reference Model Header
// Description: C-level reference for NPU verification
//-----------------------------------------------------------------------------

#ifndef NPU_REF_H
#define NPU_REF_H

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

//-----------------------------------------------------------------------------
// NPU Configuration (matches RTL parameters)
//-----------------------------------------------------------------------------
#define INPUT_WIDTH      8
#define WEIGHT_WIDTH     8
#define OUTPUT_WIDTH     32

#define SUBARRAY_ROWS    32    // Output vector size
#define SUBARRAY_COLS    8     // Input vector size

#define PE_ARRAY_ROWS    2
#define PE_ARRAY_COLS    2
#define NUM_LARGE_ARRAYS 4

#define TOTAL_PE_UNITS   (PE_ARRAY_ROWS * PE_ARRAY_COLS * NUM_LARGE_ARRAYS)
#define MACS_PER_PE      (SUBARRAY_ROWS * SUBARRAY_COLS)
#define TOTAL_MACS       (TOTAL_PE_UNITS * MACS_PER_PE)

//-----------------------------------------------------------------------------
// LLM Configuration Examples
//-----------------------------------------------------------------------------
// LLaMA-7B dimensions
#define LLAMA_HIDDEN_DIM     4096
#define LLAMA_INTERMEDIATE   11008
#define LLAMA_NUM_HEADS      32
#define LLAMA_HEAD_DIM       128

// Smaller model for testing (fits single sub-array)
#define TEST_INPUT_DIM       SUBARRAY_COLS   // 8
#define TEST_OUTPUT_DIM      SUBARRAY_ROWS   // 32

//-----------------------------------------------------------------------------
// Data Structures
//-----------------------------------------------------------------------------
typedef struct {
    int input_dim;
    int output_dim;
    int8_t* weights;      // [output_dim][input_dim] in row-major
    int8_t* input;        // [input_dim]
    int32_t* output;      // [output_dim]
    int32_t* bias;        // [output_dim] (optional)
} GemvLayer;

typedef struct {
    int M;                // Output rows
    int K;                // Shared dimension
    int N;                // Output cols
    int8_t* A;            // [M][K] matrix
    int8_t* B;            // [K][N] matrix
    int32_t* C;           // [M][N] output
} GemmLayer;

//-----------------------------------------------------------------------------
// Function Prototypes
//-----------------------------------------------------------------------------

// Initialization
GemvLayer* init_gemv_layer(int input_dim, int output_dim);
void free_gemv_layer(GemvLayer* layer);

GemmLayer* init_gemm_layer(int M, int K, int N);
void free_gemm_layer(GemmLayer* layer);

// Core operations (matches NPU behavior)
void ref_mac(int8_t input, int8_t weight, int32_t* acc);
void ref_gemv(GemvLayer* layer);
void ref_gemm(GemmLayer* layer);

// Tiled operations (for large matrices)
void ref_gemv_tiled(int8_t* input, int8_t* weights, int32_t* output,
                    int input_dim, int output_dim);
void ref_gemm_tiled(int8_t* A, int8_t* B, int32_t* C,
                    int M, int K, int N);

// Utility functions
void print_vector_i8(const char* name, int8_t* vec, int len);
void print_vector_i32(const char* name, int32_t* vec, int len);
void print_matrix_i8(const char* name, int8_t* mat, int rows, int cols);
void print_matrix_i32(const char* name, int32_t* mat, int rows, int cols);

// Test data generation
void generate_random_i8(int8_t* data, int len, int seed);
void generate_sequential_i8(int8_t* data, int len, int8_t start);

// File I/O for RTL comparison
void dump_to_hex_file(const char* filename, void* data, int len, int width);
int load_from_hex_file(const char* filename, void* data, int len, int width);

#endif // NPU_REF_H
