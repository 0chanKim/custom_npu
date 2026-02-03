//-----------------------------------------------------------------------------
// NPU Reference Model Implementation
// Description: C-level reference for NPU verification
//-----------------------------------------------------------------------------

#include "npu_ref.h"

//-----------------------------------------------------------------------------
// Initialization Functions
//-----------------------------------------------------------------------------

GemvLayer* init_gemv_layer(int input_dim, int output_dim) {
    GemvLayer* layer = (GemvLayer*)malloc(sizeof(GemvLayer));

    layer->input_dim = input_dim;
    layer->output_dim = output_dim;

    layer->weights = (int8_t*)calloc(output_dim * input_dim, sizeof(int8_t));
    layer->input = (int8_t*)calloc(input_dim, sizeof(int8_t));
    layer->output = (int32_t*)calloc(output_dim, sizeof(int32_t));
    layer->bias = (int32_t*)calloc(output_dim, sizeof(int32_t));

    return layer;
}

void free_gemv_layer(GemvLayer* layer) {
    if (layer) {
        free(layer->weights);
        free(layer->input);
        free(layer->output);
        free(layer->bias);
        free(layer);
    }
}

GemmLayer* init_gemm_layer(int M, int K, int N) {
    GemmLayer* layer = (GemmLayer*)malloc(sizeof(GemmLayer));

    layer->M = M;
    layer->K = K;
    layer->N = N;

    layer->A = (int8_t*)calloc(M * K, sizeof(int8_t));
    layer->B = (int8_t*)calloc(K * N, sizeof(int8_t));
    layer->C = (int32_t*)calloc(M * N, sizeof(int32_t));

    return layer;
}

void free_gemm_layer(GemmLayer* layer) {
    if (layer) {
        free(layer->A);
        free(layer->B);
        free(layer->C);
        free(layer);
    }
}

//-----------------------------------------------------------------------------
// Core Operations (matches NPU RTL behavior)
//-----------------------------------------------------------------------------

// Single MAC operation - matches mac_unit.sv
void ref_mac(int8_t input, int8_t weight, int32_t* acc) {
    int32_t product = (int32_t)input * (int32_t)weight;
    *acc += product;
}

// GeMV operation - matches gemv_subarray.sv
// output[i] = sum_j(weights[i][j] * input[j])
void ref_gemv(GemvLayer* layer) {
    for (int o = 0; o < layer->output_dim; o++) {
        int32_t sum = 0;
        for (int i = 0; i < layer->input_dim; i++) {
            int idx = o * layer->input_dim + i;  // Row-major order
            int32_t product = (int32_t)layer->weights[idx] * (int32_t)layer->input[i];
            sum += product;
        }
        layer->output[o] = sum + layer->bias[o];
    }
}

// GeMM operation - C = A * B
// C[m][n] = sum_k(A[m][k] * B[k][n])
void ref_gemm(GemmLayer* layer) {
    for (int m = 0; m < layer->M; m++) {
        for (int n = 0; n < layer->N; n++) {
            int32_t sum = 0;
            for (int k = 0; k < layer->K; k++) {
                int idx_a = m * layer->K + k;
                int idx_b = k * layer->N + n;
                int32_t product = (int32_t)layer->A[idx_a] * (int32_t)layer->B[idx_b];
                sum += product;
            }
            layer->C[m * layer->N + n] = sum;
        }
    }
}

//-----------------------------------------------------------------------------
// Tiled Operations (for large matrices using NPU sub-arrays)
//-----------------------------------------------------------------------------

// Tiled GeMV: process large vectors using 32x8 sub-array tiles
void ref_gemv_tiled(int8_t* input, int8_t* weights, int32_t* output,
                    int input_dim, int output_dim) {

    int tile_rows = SUBARRAY_ROWS;  // 32
    int tile_cols = SUBARRAY_COLS;  // 8

    // Initialize output
    memset(output, 0, output_dim * sizeof(int32_t));

    // Tile over output dimension
    for (int o_tile = 0; o_tile < output_dim; o_tile += tile_rows) {
        int o_end = (o_tile + tile_rows < output_dim) ? o_tile + tile_rows : output_dim;

        // Tile over input dimension (accumulate partial sums)
        for (int i_tile = 0; i_tile < input_dim; i_tile += tile_cols) {
            int i_end = (i_tile + tile_cols < input_dim) ? i_tile + tile_cols : input_dim;

            // Process one tile
            for (int o = o_tile; o < o_end; o++) {
                for (int i = i_tile; i < i_end; i++) {
                    int idx = o * input_dim + i;
                    int32_t product = (int32_t)weights[idx] * (int32_t)input[i];
                    output[o] += product;
                }
            }
        }
    }
}

// Tiled GeMM: process large matrices using 32x8 sub-array tiles
void ref_gemm_tiled(int8_t* A, int8_t* B, int32_t* C,
                    int M, int K, int N) {

    int tile_m = SUBARRAY_ROWS;  // 32
    int tile_k = SUBARRAY_COLS;  // 8

    // Initialize output
    memset(C, 0, M * N * sizeof(int32_t));

    // Tile over M dimension
    for (int m_tile = 0; m_tile < M; m_tile += tile_m) {
        int m_end = (m_tile + tile_m < M) ? m_tile + tile_m : M;

        // Tile over K dimension (accumulate partial sums)
        for (int k_tile = 0; k_tile < K; k_tile += tile_k) {
            int k_end = (k_tile + tile_k < K) ? k_tile + tile_k : K;

            // Process all N columns for this M x K tile
            for (int n = 0; n < N; n++) {
                for (int m = m_tile; m < m_end; m++) {
                    for (int k = k_tile; k < k_end; k++) {
                        int idx_a = m * K + k;
                        int idx_b = k * N + n;
                        int32_t product = (int32_t)A[idx_a] * (int32_t)B[idx_b];
                        C[m * N + n] += product;
                    }
                }
            }
        }
    }
}

//-----------------------------------------------------------------------------
// Utility Functions
//-----------------------------------------------------------------------------

void print_vector_i8(const char* name, int8_t* vec, int len) {
    printf("%s[%d] = { ", name, len);
    for (int i = 0; i < len; i++) {
        printf("%4d", vec[i]);
        if (i < len - 1) printf(", ");
    }
    printf(" }\n");
}

void print_vector_i32(const char* name, int32_t* vec, int len) {
    printf("%s[%d] = { ", name, len);
    for (int i = 0; i < len; i++) {
        printf("%6d", vec[i]);
        if (i < len - 1) printf(", ");
    }
    printf(" }\n");
}

void print_matrix_i8(const char* name, int8_t* mat, int rows, int cols) {
    printf("%s[%d][%d] = {\n", name, rows, cols);
    for (int r = 0; r < rows; r++) {
        printf("  { ");
        for (int c = 0; c < cols; c++) {
            printf("%4d", mat[r * cols + c]);
            if (c < cols - 1) printf(", ");
        }
        printf(" }");
        if (r < rows - 1) printf(",");
        printf("\n");
    }
    printf("}\n");
}

void print_matrix_i32(const char* name, int32_t* mat, int rows, int cols) {
    printf("%s[%d][%d] = {\n", name, rows, cols);
    for (int r = 0; r < rows; r++) {
        printf("  { ");
        for (int c = 0; c < cols; c++) {
            printf("%8d", mat[r * cols + c]);
            if (c < cols - 1) printf(", ");
        }
        printf(" }");
        if (r < rows - 1) printf(",");
        printf("\n");
    }
    printf("}\n");
}

//-----------------------------------------------------------------------------
// Test Data Generation
//-----------------------------------------------------------------------------

void generate_random_i8(int8_t* data, int len, int seed) {
    srand(seed);
    for (int i = 0; i < len; i++) {
        data[i] = (int8_t)((rand() % 256) - 128);  // -128 to 127
    }
}

void generate_sequential_i8(int8_t* data, int len, int8_t start) {
    for (int i = 0; i < len; i++) {
        data[i] = start + i;
    }
}

//-----------------------------------------------------------------------------
// File I/O for RTL Comparison
//-----------------------------------------------------------------------------

void dump_to_hex_file(const char* filename, void* data, int len, int width) {
    FILE* fp = fopen(filename, "w");
    if (!fp) {
        printf("Error: Cannot open file %s\n", filename);
        return;
    }

    if (width == 8) {
        int8_t* d = (int8_t*)data;
        for (int i = 0; i < len; i++) {
            fprintf(fp, "%02X\n", (uint8_t)d[i]);
        }
    } else if (width == 32) {
        int32_t* d = (int32_t*)data;
        for (int i = 0; i < len; i++) {
            fprintf(fp, "%08X\n", (uint32_t)d[i]);
        }
    }

    fclose(fp);
    printf("Dumped %d elements to %s\n", len, filename);
}

int load_from_hex_file(const char* filename, void* data, int len, int width) {
    FILE* fp = fopen(filename, "r");
    if (!fp) {
        printf("Error: Cannot open file %s\n", filename);
        return -1;
    }

    int count = 0;
    if (width == 8) {
        int8_t* d = (int8_t*)data;
        unsigned int val;
        while (count < len && fscanf(fp, "%x", &val) == 1) {
            d[count++] = (int8_t)val;
        }
    } else if (width == 32) {
        int32_t* d = (int32_t*)data;
        unsigned int val;
        while (count < len && fscanf(fp, "%x", &val) == 1) {
            d[count++] = (int32_t)val;
        }
    }

    fclose(fp);
    return count;
}
