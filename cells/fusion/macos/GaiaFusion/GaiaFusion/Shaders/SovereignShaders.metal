#include <metal_stdlib>
using namespace metal;

kernel void sovereign_noop(
  constant float* input [[buffer(0)]],
  device float* output [[buffer(1)]],
  uint id [[thread_position_in_grid]]
) {
  if (id < 1) {
    output[id] = input[id];
  }
}
