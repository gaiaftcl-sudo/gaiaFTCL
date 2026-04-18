# GaiaOS LLM Router
# Unified OS-level LLM facade for all GaiaOS profiles
# Port: 8790

FROM rust:1.83-slim AS builder

WORKDIR /build

RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy workspace Cargo files
COPY Cargo.toml Cargo.lock ./

# Copy ALL crates
COPY crates ./crates

# Copy the service
COPY services/gaiaos_llm_router ./services/gaiaos_llm_router

# Create stub workspace members
RUN mkdir -p uum8d_core/src && \
    echo "pub fn stub() {}" > uum8d_core/src/lib.rs && \
    printf '[package]\nname = "uum8d_core"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > uum8d_core/Cargo.toml

RUN mkdir -p uum8d_world_bridge/src && \
    echo "pub fn stub() {}" > uum8d_world_bridge/src/lib.rs && \
    printf '[package]\nname = "uum8d_world_bridge"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > uum8d_world_bridge/Cargo.toml

RUN mkdir -p fot_akg_client/src && \
    echo "pub fn stub() {}" > fot_akg_client/src/lib.rs && \
    printf '[package]\nname = "fot_akg_client"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > fot_akg_client/Cargo.toml

RUN mkdir -p quantum_substrate/src && \
    echo "pub fn stub() {}" > quantum_substrate/src/lib.rs && \
    printf '[package]\nname = "quantum_substrate"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > quantum_substrate/Cargo.toml

RUN mkdir -p gasm_runtime/src && \
    echo "pub fn stub() {}" > gasm_runtime/src/lib.rs && \
    printf '[package]\nname = "gasm_runtime"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > gasm_runtime/Cargo.toml

RUN mkdir -p franklin_validator/src && \
    echo "pub fn stub() {}" > franklin_validator/src/lib.rs && \
    printf '[package]\nname = "franklin_validator"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > franklin_validator/Cargo.toml

RUN mkdir -p quantum_facade/src && \
    echo "pub fn stub() {}" > quantum_facade/src/lib.rs && \
    printf '[package]\nname = "quantum_facade"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > quantum_facade/Cargo.toml

RUN mkdir -p fara_encoder/src && \
    echo "pub fn stub() {}" > fara_encoder/src/lib.rs && \
    printf '[package]\nname = "fara_encoder"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > fara_encoder/Cargo.toml

RUN mkdir -p benstack/uum8d/src && \
    echo "pub fn stub() {}" > benstack/uum8d/src/lib.rs && \
    printf '[package]\nname = "uum8d"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > benstack/uum8d/Cargo.toml

RUN mkdir -p exam-recorder/src && \
    echo "pub fn stub() {}" > exam-recorder/src/lib.rs && \
    printf '[package]\nname = "exam-recorder"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > exam-recorder/Cargo.toml

RUN mkdir -p evidence-pack/src && \
    echo "pub fn stub() {}" > evidence-pack/src/lib.rs && \
    printf '[package]\nname = "evidence-pack"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > evidence-pack/Cargo.toml

RUN mkdir -p mac-cell/consciousness_rust/src && \
    echo "pub fn stub() {}" > mac-cell/consciousness_rust/src/lib.rs && \
    printf '[package]\nname = "consciousness_rust"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > mac-cell/consciousness_rust/Cargo.toml

# Stub services
RUN for svc in gaiaos_ui gaiaos_validation gaiaos_core_agent franklin_guardian inference_encoder teacher_harvest gaialm_trainer gaia_orchestrator uum-8d-core uum-node-agent gaiaos_comm_router gaiaos_comm_agent sensor_sim actuator_sim world_engine gaiaos_24h_cycle uum8d_brain status_reporter gaiaos_mcp_server spatial_gateway gaia1_virtual_chip_service akg_gnn; do \
    mkdir -p "services/${svc}/src" && \
    echo "pub fn stub() {}" > "services/${svc}/src/lib.rs" && \
    printf "[package]\nname = \"${svc}\"\nversion = \"0.1.0\"\nedition = \"2021\"\n[lib]\npath = \"src/lib.rs\"" > "services/${svc}/Cargo.toml"; \
    done

# Overwrite with actual service
COPY services/gaiaos_llm_router ./services/gaiaos_llm_router

# Build
RUN cargo build --release -p gaiaos_llm_router

# Runtime
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/target/release/gaiaos-llm-router /app/

ENV RUST_LOG=info
ENV HOST=0.0.0.0
ENV PORT=8790
ENV OLLAMA_URL=http://ollama:11434

EXPOSE 8790

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8790/health || exit 1

CMD ["/app/gaiaos-llm-router"]

