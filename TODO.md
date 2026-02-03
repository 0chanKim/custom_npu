# NPU Project TODO List

## Phase 1: 설계 및 스펙 정의
- [x] NPU 아키텍처 스펙 정의 (PLAN.md)
- [ ] 상세 아키텍처 문서 작성 (docs/ARCHITECTURE.md)

## Phase 2: 핵심 연산 유닛 구현
- [x] MAC (Multiply-Accumulate) 유닛 설계 (`mac_unit.sv`)
- [x] GeMV Sub-array 구현 (`gemv_subarray.sv`)
- [x] PE Unit 설계 (`pe_unit.sv`)
- [x] Large PE Array 구현 (`large_pe_array.sv`)
- [x] PE Array Cluster 구현 (`pe_array_cluster.sv`)

## Phase 3: 메모리 서브시스템
- [ ] Weight Buffer 설계
- [ ] Input/Output Buffer 설계
- [ ] 메모리 컨트롤러 구현

## Phase 4: 제어 유닛 (방식 A: HW 자체 tiling)
- [ ] Compute Controller FSM 설계 (`compute_ctrl.sv`)
  - AXI-Lite에서 M, K, N dimension 수신
  - `num_k_tiles = ceil(K / SUBARRAY_COLS)` 내부 계산
  - clear_acc (첫 K tile), enable (매 tile), output store 자동 제어
  - FSM: IDLE → LOAD_WEIGHT → LOAD_INPUT → COMPUTE → STORE → DONE
- [ ] AXI-Lite 레지스터 확장 (DIM_M/K/N, ADDR_INPUT/WEIGHT/OUTPUT 추가)
- [ ] Controller FSM 테스트벤치 (`compute_ctrl_tb.sv`)

## Phase 5: 시스템 통합
- [x] Top 모듈 기본 구현 (`npu_top.sv`)
- [x] AXI-Lite 인터페이스 기본 구현 (`axi_lite_slave.sv`)
- [ ] npu_top에 compute_ctrl 연결, dimension 경로 추가
- [ ] 시스템 레벨 테스트벤치 (`npu_top_tb.sv`)

## Phase 6: 검증
- [x] C reference model 구현 (`sw/ref/npu_ref.c`)
- [x] C reference hex 파일 생성 (MAC + GeMV 테스트 데이터)
- [x] MAC 단위 테스트벤치 ($readmemh, C ref 비교, non-blocking)
- [x] GeMV Sub-array 테스트벤치 ($readmemh, C ref 비교, non-blocking)
- [ ] Controller FSM 검증 (다양한 dimension으로 tiling 정확성 확인)
- [ ] End-to-end 검증 (AXI-Lite로 dimension 설정 → 연산 → 결과 비교)

## Phase 7: 최적화 및 완료
- [ ] 타이밍 최적화
- [ ] 면적 최적화
- [ ] 문서 정리

---
## 진행 상황
| Phase | 상태 | 비고 |
|-------|------|------|
| Phase 1 | 완료 | 아키텍처 스펙 정의 완료 |
| Phase 2 | 완료 | MAC → GeMV → PE → Array → Cluster 전체 구현 |
| Phase 3 | 대기 | 메모리 서브시스템 미착수 |
| Phase 4 | **다음** | Controller FSM 설계 필요 (방식 A: HW 자체 tiling) |
| Phase 5 | 부분완료 | top/axi 기본 구현, controller 연결 필요 |
| Phase 6 | 부분완료 | MAC/GeMV TB 완료, controller/system TB 필요 |
| Phase 7 | 대기 | - |
