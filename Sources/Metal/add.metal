#include <metal_stdlib>
using namespace metal;

kernel void
simpleAddition(
    device float *a [[ buffer(0) ]],
    device float *b [[ buffer(1) ]],
    device float *out [[ buffer(2) ]],
    uint position [[ thread_position_in_grid ]])
{
    out[position] = a[position] + b[position];
}
