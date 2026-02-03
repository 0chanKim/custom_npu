# NPU Architecture Specification

## 1. 개요
범용 Neural Processing Unit (NPU) 아키텍처 스펙 문서

## 2. 설계 목표
- 효율적인 CNN/DNN 추론 가속
- 유연한 데이터 타입 지원
- 확장 가능한 PE Array 구조

## 3. 주요 스펙 (TBD)

### 3.1 데이터 타입
| 타입 | 지원 여부 | 비고 |
|------|----------|------|
| INT8 | TBD | 추론 최적화 |
| FP16 | TBD | 정밀도/성능 균형 |
| BF16 | TBD | 학습 호환 |
| FP32 | TBD | 고정밀도 |

### 3.2 PE Array
- 크기: TBD (예: 8x8, 16x16)
- 구조: Systolic Array / Spatial Array

### 3.3 메모리
- On-chip SRAM: TBD KB
- Weight Buffer: TBD KB
- Activation Buffer: TBD KB

### 3.4 지원 연산
- [ ] Matrix Multiplication
- [ ] Convolution (1x1, 3x3, etc.)
- [ ] Pooling (Max, Average)
- [ ] Activation (ReLU, Sigmoid, Tanh)
- [ ] Batch Normalization
- [ ] Element-wise Operations

### 3.5 인터페이스
- 버스: TBD (AXI4 / AXI-Stream)
- 클럭: TBD MHz
- 타겟: TBD (FPGA / ASIC)

## 4. 블록 다이어그램

```
+----------------------------------------------------------+
|                        NPU Top                            |
|  +------------+  +-------------+  +-------------------+  |
|  |  Control   |  |   Memory    |  |    Compute Core   |  |
|  |   Unit     |  |  Subsystem  |  |                   |  |
|  |            |  |             |  |  +-----------+    |  |
|  | - Decoder  |  | - Weight    |  |  | PE Array  |    |  |
|  | - FSM      |  |   Buffer    |  |  | (NxN)     |    |  |
|  | - Scheduler|  | - Act Buffer|  |  +-----------+    |  |
|  +------------+  +-------------+  |  +-----------+    |  |
|                                   |  | Activation|    |  |
|                                   |  +-----------+    |  |
|                                   +-------------------+  |
+----------------------------------------------------------+
```

## 5. 버전 히스토리
| 버전 | 날짜 | 변경 내용 |
|------|------|----------|
| 0.1  | TBD  | 초기 스펙 작성 |
