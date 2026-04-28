#include <metal_stdlib>
using namespace metal;
kernel void z3_pad(device float *buf [[buffer(0)]], uint id [[thread_position_in_grid]]) { if (id < 1) buf[id] = buf[id] + 1.0f; }