# NPU Detailed Architecture

## 1. 시스템 개요

### 1.1 최상위 구조
```
                    +------------------+
                    |   External Host  |
                    +--------+---------+
                             |
                    +--------v---------+
                    |   AXI Interface  |
                    +--------+---------+
                             |
        +--------------------+--------------------+
        |                    |                    |
+-------v-------+   +--------v--------+   +-------v-------+
| Control Unit  |   | Memory Subsys   |   | Compute Core  |
+---------------+   +-----------------+   +---------------+
```

## 2. Compute Core

### 2.1 PE (Processing Element) 구조
```
+------------------------------------------+
|                   PE                      |
|  +--------+    +--------+    +--------+  |
|  | Weight |    |  MAC   |    | Output |  |
|  |  Reg   |--->| Unit   |--->|  Reg   |  |
|  +--------+    +---^----+    +--------+  |
|                    |                      |
|               +----+----+                 |
|               | Input   |                 |
|               | (from above/left)         |
+------------------------------------------+
```

### 2.2 PE Array (Systolic Array)
```
     Input Data Flow -->
    +----+----+----+----+
    | PE | PE | PE | PE |  |
    +----+----+----+----+  |
    | PE | PE | PE | PE |  | Weight
    +----+----+----+----+  | Data
    | PE | PE | PE | PE |  | Flow
    +----+----+----+----+  |
    | PE | PE | PE | PE |  v
    +----+----+----+----+
         Output Data
```

### 2.3 Activation Unit
- 지원 함수: ReLU, Leaky ReLU, Sigmoid, Tanh
- 구현 방식: LUT 또는 근사 연산

## 3. Memory Subsystem

### 3.1 버퍼 구조
```
+--------------------------------------------------+
|              Memory Subsystem                     |
|  +-------------+  +-------------+  +-----------+ |
|  |   Weight    |  |   Input     |  |  Output   | |
|  |   Buffer    |  |   Buffer    |  |  Buffer   | |
|  | (Double-buf)|  | (Double-buf)|  |           | |
|  +-------------+  +-------------+  +-----------+ |
|         |               |               |        |
|  +------v---------------v---------------v------+ |
|  |              Memory Controller              | |
|  +---------------------------------------------+ |
+--------------------------------------------------+
```

### 3.2 메모리 계층
1. **Register File**: PE 내부, 최소 지연
2. **On-chip Buffer**: SRAM, 낮은 지연
3. **External Memory**: DDR, 높은 대역폭

## 4. Control Unit

### 4.1 주요 구성요소
- **Instruction Fetch**: 명령어 인출
- **Instruction Decode**: 명령어 해석
- **Execution Control**: 실행 제어 FSM
- **Scheduler**: 연산 스케줄링

### 4.2 FSM 상태
```
    +-------+
    | IDLE  |<-----------------+
    +---+---+                  |
        |                      |
        v                      |
    +---+---+                  |
    | FETCH |                  |
    +---+---+                  |
        |                      |
        v                      |
    +---+----+                 |
    | DECODE |                 |
    +---+----+                 |
        |                      |
        v                      |
    +---+----+                 |
    | EXECUTE|                 |
    +---+----+                 |
        |                      |
        v                      |
    +---+----+     +---------+ |
    | WRITE  |---->|  DONE   |-+
    +--------+     +---------+
```

## 5. 데이터 플로우

### 5.1 Convolution 연산 흐름
1. Weight 로드 → Weight Buffer
2. Input Feature Map 로드 → Input Buffer
3. PE Array에서 MAC 연산 수행
4. Activation 함수 적용
5. Output Feature Map 저장 → Output Buffer

### 5.2 Matrix Multiplication 흐름
1. Matrix A 로드 (행 단위)
2. Matrix B 로드 (열 단위)
3. Systolic Array에서 연산
4. 결과 누적 및 저장

## 6. 인터페이스

### 6.1 AXI4 Interface
- AXI4-Full: 메모리 매핑 레지스터 접근
- AXI4-Stream: 데이터 스트리밍

### 6.2 인터럽트
- 연산 완료 인터럽트
- 에러 인터럽트

## 7. RTL 모듈 계층

```
npu_top
├── npu_ctrl
│   ├── inst_fetch
│   ├── inst_decode
│   └── execution_fsm
├── memory_subsys
│   ├── weight_buffer
│   ├── input_buffer
│   ├── output_buffer
│   └── mem_controller
├── compute_core
│   ├── pe_array
│   │   └── pe (NxN instances)
│   ├── activation_unit
│   └── accumulator
└── axi_interface
    ├── axi_slave
    └── axi_master
```

## 8. 버전 히스토리
| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| 0.1  | TBD  | 초기 아키텍처 문서 |
