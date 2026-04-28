// ─────────────────────────────────────────────────────────────────────────────
// pass3_pbd_cloth.metal
//
// Z3 pass 3 — XPBD (eXtended Position-Based Dynamics) cloth simulation for
// the Continental frock coat + lace cravat. Compute pass; runs N substeps
// per frame against the constraint set produced from the rest pose.
//
// Pipeline:
//   1. predict — particle.position += particle.velocity * dt
//   2. solve_constraints — XPBD distance constraints (gauss–seidel)
//   3. project_collisions — capsule colliders for arms / torso
//   4. integrate — recompute velocities, write back positions
// ─────────────────────────────────────────────────────────────────────────────

#include "Common.metal"
using namespace metal;

struct ClothFrame {
    float dt;
    uint  particle_count;
    uint  constraint_count;
    uint  substeps;
    float gravity_y_mps2;       // -9.81 baseline
    float damping;              // 0.99 nominal
    float wind_x;
    float wind_z;
};

kernel void pass3_pbd_predict(
    device ClothParticle* particles [[buffer(0)]],
    constant ClothFrame& frame [[buffer(1)]],
    uint pid [[thread_position_in_grid]]
) {
    if (pid >= frame.particle_count) return;
    ClothParticle p = particles[pid];
    if (p.inv_mass <= 0.0f) return;   // pinned (collar / cuff)
    float3 acc = float3(frame.wind_x, frame.gravity_y_mps2, frame.wind_z);
    p.velocity += acc * frame.dt;
    p.velocity *= frame.damping;
    p.position += p.velocity * frame.dt;
    particles[pid] = p;
}

kernel void pass3_pbd_solve_constraints(
    device ClothParticle* particles [[buffer(0)]],
    constant ClothConstraint* constraints [[buffer(1)]],
    constant ClothFrame& frame [[buffer(2)]],
    device atomic_uint* lambdas [[buffer(3)]],   // XPBD multipliers (atomic for parallel solve)
    uint cid [[thread_position_in_grid]]
) {
    if (cid >= frame.constraint_count) return;
    ClothConstraint c = constraints[cid];
    ClothParticle pa = particles[c.a];
    ClothParticle pb = particles[c.b];
    float3 d = pb.position - pa.position;
    float dist = length(d);
    if (dist < 1e-6f) return;
    float3 dir = d / dist;
    float w_sum = pa.inv_mass + pb.inv_mass;
    if (w_sum <= 0.0f) return;
    float alpha = c.compliance / (frame.dt * frame.dt);
    float lambda_delta = -(dist - c.rest_length_m) / (w_sum + alpha);
    float3 corr = lambda_delta * dir;
    if (pa.inv_mass > 0.0f) particles[c.a].position = pa.position - corr * pa.inv_mass;
    if (pb.inv_mass > 0.0f) particles[c.b].position = pb.position + corr * pb.inv_mass;
}

kernel void pass3_pbd_integrate(
    device ClothParticle* particles [[buffer(0)]],
    device const ClothParticle* prev [[buffer(1)]],
    constant ClothFrame& frame [[buffer(2)]],
    uint pid [[thread_position_in_grid]]
) {
    if (pid >= frame.particle_count) return;
    ClothParticle p = particles[pid];
    if (p.inv_mass <= 0.0f) return;
    p.velocity = (p.position - prev[pid].position) / frame.dt;
    particles[pid] = p;
}
