# NPU PE Array 구현 계획

## 1. 아키텍처 개요

```
+------------------------------------------------------------------+
|                          NPU Top                                  |
|  +------------------+     +-----------------------------------+   |
|  |   AXI-Lite       |     |        PE Array Cluster           |   |
|  |   Interface      |---->|  +-------+  +-------+             |   |
|  | - Enable regs    |     |  | Large |  | Large |             |   |
|  | - Config regs    |     |  | PE    |  | PE    |             |   |
|  | - Status regs    |     |  | Array |  | Array |             |   |
|  +------------------+     |  |  [0]  |  |  [1]  |             |   |
|                           |  +-------+  +-------+             |   |
|                           |  +-------+  +-------+             |   |
|                           |  | Large |  | Large |             |   |
|                           |  | PE    |  | PE    |             |   |
|                           |  | Array |  | Array |             |   |
|                           |  |  [2]  |  |  [3]  |             |   |
|                           |  +-------+  +-------+             |   |
|                           +-----------------------------------+   |
+------------------------------------------------------------------+
```

## 2. 계층 구조

```
npu_top
├── axi_lite_slave          # AXI-Lite 인터페이스 (제어/상태/차원 레지스터)
├── compute_ctrl            # Controller FSM (tiling/accumulation 자동 제어)
│   └── dimension에 따라 clear_acc, enable 횟수 자동 계산
├── pe_array_cluster        # 4개 Large PE Array 관리
│   ├── large_pe_array[0]   # 2x2 PE Array
│   │   ├── pe_unit[0][0]   # 32x8 Sub-array 포함
│   │   ├── pe_unit[0][1]
│   │   ├── pe_unit[1][0]
│   │   └── pe_unit[1][1]
│   ├── large_pe_array[1]
│   ├── large_pe_array[2]
│   └── large_pe_array[3]
└── (향후) memory_subsystem  # 버퍼 관리
```

## 3. 모듈 상세 설계

### 3.1 PE Unit (pe_unit.sv)
- **내부 구조**: 32x8 = 256개 MAC 유닛
- **연산**: GeMV (행렬-벡터 곱셈) - 32x8 행렬 × 8 벡터 → 32 벡터
- **파라미터**:
  - `INPUT_WIDTH` (default: 8)
  - `WEIGHT_WIDTH` (default: 8)
  - `OUTPUT_WIDTH` (default: 32, 누적용)
  - `SUBARRAY_ROWS` (default: 32)
  - `SUBARRAY_COLS` (default: 8)
- **인터페이스**:
  - `enable` - Sub-array 활성화
  - `input_vector[SUBARRAY_COLS-1:0][INPUT_WIDTH-1:0]` - 입력 벡터 (8개)
  - `weight_matrix[SUBARRAY_ROWS-1:0][SUBARRAY_COLS-1:0][WEIGHT_WIDTH-1:0]` - Weight (32x8)
  - `output_vector[SUBARRAY_ROWS-1:0][OUTPUT_WIDTH-1:0]` - 출력 벡터 (32개)

### 3.2 Large PE Array (large_pe_array.sv)
- **구조**: 2x2 = 4개 PE Unit
- **파라미터**:
  - `PE_ARRAY_ROWS` (default: 2)
  - `PE_ARRAY_COLS` (default: 2)
- **인터페이스**:
  - `array_enable` - 전체 Array 활성화
  - `pe_enable[PE_ARRAY_ROWS-1:0][PE_ARRAY_COLS-1:0]` - 개별 PE 활성화
  - 데이터 입출력 포트

### 3.3 PE Array Cluster (pe_array_cluster.sv)
- **구조**: 4개 Large PE Array
- **파라미터**:
  - `NUM_LARGE_ARRAYS` (default: 4)
- **인터페이스**:
  - `cluster_enable` - 전체 클러스터 활성화
  - `large_array_enable[NUM_LARGE_ARRAYS-1:0]` - 개별 Large Array 활성화

### 3.4 Compute Controller FSM (compute_ctrl.sv)
- **역할**: AXI-Lite로 받은 dimension 정보를 기반으로 tiling/accumulation을 자동 제어
- **설계 방식 A**: SW는 dimension + 주소만 설정, HW가 내부적으로 tiling loop 수행
- **내부 동작**:
  ```
  num_k_tiles = (K + SUBARRAY_COLS - 1) / SUBARRAY_COLS
  num_m_tiles = (M + SUBARRAY_ROWS - 1) / SUBARRAY_ROWS

  for m_tile in num_m_tiles:
    for n in N:
      for k_tile in num_k_tiles:
        DMA로 weight/input 로드
        if (k_tile == 0) clear_acc
        enable 1 cycle
      output store
  done ← 1
  ```
- **FSM States**: IDLE → LOAD_WEIGHT → LOAD_INPUT → COMPUTE → STORE → (loop or DONE)
- **인터페이스**:
  - `start` - 연산 시작 (AXI-Lite CTRL에서)
  - `dim_m`, `dim_k`, `dim_n` - 행렬 차원
  - `base_addr_input`, `base_addr_weight`, `base_addr_output` - 메모리 주소
  - `done`, `busy` - 상태 출력
  - PE array 제어 신호 (clear_acc, enable, data/weight 경로)

### 3.5 AXI-Lite Slave (axi_lite_slave.sv)
- **레지스터 맵**:
  | Offset | Name | Description |
  |--------|------|-------------|
  | 0x00 | CTRL | 전역 제어 (start, reset) |
  | 0x04 | STATUS | 상태 (busy, done, error) |
  | 0x08 | CLUSTER_EN | Large PE Array enable [3:0] |
  | 0x0C | PE_EN_0 | Array[0]의 PE enable [3:0] |
  | 0x10 | PE_EN_1 | Array[1]의 PE enable [3:0] |
  | 0x14 | PE_EN_2 | Array[2]의 PE enable [3:0] |
  | 0x18 | PE_EN_3 | Array[3]의 PE enable [3:0] |
  | 0x1C | CONFIG | 설정 (data type 등) |
  | 0x20 | DIM_M | M dimension (output rows) |
  | 0x24 | DIM_K | K dimension (shared/accumulate) |
  | 0x28 | DIM_N | N dimension (output cols) |
  | 0x2C | ADDR_INPUT | Input data base address |
  | 0x30 | ADDR_WEIGHT | Weight data base address |
  | 0x34 | ADDR_OUTPUT | Output data base address |

## 4. 구현 순서

### Phase 1: 기본 연산 유닛
1. [x] `mac_unit.sv` - 단일 MAC 유닛 (INT8 × INT8 → INT32)
2. [x] `mac_unit_tb.sv` - MAC 유닛 테스트벤치 ($readmemh, C reference 비교, non-blocking)

### Phase 2: Sub-array (GeMV)
3. [x] `gemv_subarray.sv` - 32x8 GeMV Sub-array
4. [x] `gemv_subarray_tb.sv` - Sub-array 테스트벤치 ($readmemh, C reference 비교, non-blocking)

### Phase 3: PE Unit
5. [x] `pe_unit.sv` - PE Unit (Sub-array wrapper + control)
6. [ ] `pe_unit_tb.sv` - PE Unit 테스트벤치

### Phase 4: Large PE Array
7. [x] `large_pe_array.sv` - 2x2 PE Array
8. [ ] `large_pe_array_tb.sv` - Large PE Array 테스트벤치

### Phase 5: PE Array Cluster
9. [x] `pe_array_cluster.sv` - 4개 Large Array 묶음
10. [ ] `pe_array_cluster_tb.sv` - Cluster 테스트벤치

### Phase 6: Controller FSM
11. [ ] `compute_ctrl.sv` - Compute Controller FSM (tiling/accumulation 자동 제어)
    - AXI-Lite에서 M, K, N dimension 수신
    - num_k_tiles = ceil(K / SUBARRAY_COLS)로 accumulate 횟수 자동 계산
    - clear_acc / enable / 데이터 경로 제어
12. [ ] `compute_ctrl_tb.sv` - Controller FSM 테스트벤치

### Phase 7: AXI Interface
13. [x] `axi_lite_slave.sv` - AXI-Lite 슬레이브 (기본 구현 완료)
14. [ ] `axi_lite_slave.sv` - dimension 레지스터 추가 (DIM_M/K/N, ADDR_INPUT/WEIGHT/OUTPUT)
15. [ ] `axi_lite_slave_tb.sv` - AXI-Lite 테스트벤치

### Phase 8: Top Integration
16. [x] `npu_top.sv` - 최상위 모듈 (기본 구현 완료)
17. [ ] `npu_top.sv` - compute_ctrl 연결, dimension 경로 추가
18. [ ] `npu_top_tb.sv` - 시스템 레벨 테스트벤치

## 5. 파라미터 정의 (npu_pkg.sv)

```systemverilog
package npu_pkg;
    // Data width parameters
    parameter int INPUT_WIDTH  = 8;
    parameter int WEIGHT_WIDTH = 8;
    parameter int OUTPUT_WIDTH = 32;  // For accumulation

    // Array size parameters
    parameter int SUBARRAY_ROWS     = 32;  // 32x8 sub-array
    parameter int SUBARRAY_COLS     = 8;
    parameter int PE_ARRAY_ROWS     = 2;   // 2x2 PE array
    parameter int PE_ARRAY_COLS     = 2;
    parameter int NUM_LARGE_ARRAYS  = 4;   // 4 large arrays

    // Derived parameters
    parameter int TOTAL_PE_UNITS = PE_ARRAY_ROWS * PE_ARRAY_COLS * NUM_LARGE_ARRAYS;
    parameter int MACS_PER_PE    = SUBARRAY_ROWS * SUBARRAY_COLS;  // 256
    parameter int TOTAL_MACS     = TOTAL_PE_UNITS * MACS_PER_PE;   // 4096
endpackage
```

## 6. 파일 구조

```
rtl/
├── pkg/
│   └── npu_pkg.sv              # 공통 파라미터/타입 정의
├── compute/
│   ├── mac_unit.sv             # MAC 유닛                    [구현완료]
│   ├── gemv_subarray.sv        # 32x8 GeMV Sub-array         [구현완료]
│   ├── pe_unit.sv              # PE Unit                      [구현완료]
│   ├── large_pe_array.sv       # 2x2 PE Array                 [구현완료]
│   └── pe_array_cluster.sv     # 4개 Large Array 클러스터     [구현완료]
├── core/
│   └── compute_ctrl.sv         # Controller FSM               [TODO]
├── interface/
│   └── axi_lite_slave.sv       # AXI-Lite 인터페이스          [dimension 레지스터 추가 필요]
└── top/
    └── npu_top.sv              # 최상위 모듈                  [controller 연결 필요]

sw/ref/
├── npu_ref.h                   # C reference 헤더
├── npu_ref.c                   # C reference 구현 (MAC, GeMV, GeMM)
├── main.c                      # 테스트 + hex 파일 생성
├── mac_test_*.hex              # MAC 테스트 데이터 (input/weight/clear/expected)
└── test_*_*.hex                # GeMV 테스트 데이터 (input/weight/output)

tb/
├── mac_unit_tb.sv              # $readmemh + C ref 비교       [구현완료]
├── gemv_subarray_tb.sv         # $readmemh + C ref 비교       [구현완료]
├── compute_ctrl_tb.sv          # Controller FSM 테스트         [TODO]
├── axi_lite_slave_tb.sv        #                               [TODO]
└── npu_top_tb.sv               #                               [TODO]
```

## 7. 검증 전략

1. **C Reference Model** (`sw/ref/`): C로 golden model 구현 → hex 파일 생성
2. **$readmemh 기반 비교**: TB에서 hex 파일 로드 → DUT 출력과 C reference 출력 비교
3. **Non-blocking stimuli**: TB task에서 DUT 신호 구동 시 `<=` 사용 (init 제외)
4. **단위 테스트**: mac_unit → gemv_subarray → pe_unit → ... 단계별 검증
5. **Random Test**: C reference에서 다양한 seed로 랜덤 테스트 데이터 생성
6. **Integration Test**: controller + PE array 연동, AXI-Lite 경유 dimension 설정 → end-to-end 검증

## 8. 예상 리소스 (참고)

- **총 MAC 유닛**: 4 × 4 × 256 = 4,096개
- **INT8 기준 처리량**: 4,096 ops/cycle (peak)
