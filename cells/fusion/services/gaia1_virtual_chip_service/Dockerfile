# GAIA-1 Virtual Chip Service Dockerfile
# Builds the vChip HTTP+NATS service

FROM rustlang/rust:nightly-slim AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    cmake \
    && rm -rf /var/lib/apt/lists/*

# Copy workspace Cargo files
COPY Cargo.toml Cargo.lock ./

# Copy ALL crates directory (contains all internal dependencies)
COPY crates ./crates

# Copy the service
COPY services/gaia1_virtual_chip_service ./services/gaia1_virtual_chip_service

# Create stub workspace members to satisfy Cargo
# These are referenced in Cargo.toml but not needed for vchip build
RUN mkdir -p uum8d_core/src && \
    echo "pub fn stub() {}" > uum8d_core/src/lib.rs && \
    echo '[package]\nname = "uum8d_core"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > uum8d_core/Cargo.toml

RUN mkdir -p uum8d_world_bridge/src && \
    echo "pub fn stub() {}" > uum8d_world_bridge/src/lib.rs && \
    echo '[package]\nname = "uum8d_world_bridge"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > uum8d_world_bridge/Cargo.toml

RUN mkdir -p fot_akg_client/src && \
    echo "pub fn stub() {}" > fot_akg_client/src/lib.rs && \
    echo '[package]\nname = "fot_akg_client"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > fot_akg_client/Cargo.toml

RUN mkdir -p quantum_substrate/src && \
    echo "pub fn stub() {}" > quantum_substrate/src/lib.rs && \
    echo '[package]\nname = "quantum_substrate"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > quantum_substrate/Cargo.toml

RUN mkdir -p gasm_runtime/src && \
    echo "pub fn stub() {}" > gasm_runtime/src/lib.rs && \
    echo '[package]\nname = "gasm_runtime"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > gasm_runtime/Cargo.toml

RUN mkdir -p franklin_validator/src && \
    echo "pub fn stub() {}" > franklin_validator/src/lib.rs && \
    echo '[package]\nname = "franklin_validator"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > franklin_validator/Cargo.toml

RUN mkdir -p quantum_facade/src && \
    echo "pub fn stub() {}" > quantum_facade/src/lib.rs && \
    echo '[package]\nname = "quantum_facade"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > quantum_facade/Cargo.toml

RUN mkdir -p fara_encoder/src && \
    echo "pub fn stub() {}" > fara_encoder/src/lib.rs && \
    echo '[package]\nname = "fara_encoder"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > fara_encoder/Cargo.toml

RUN mkdir -p benstack/uum8d/src && \
    echo "pub fn stub() {}" > benstack/uum8d/src/lib.rs && \
    echo '[package]\nname = "uum8d"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > benstack/uum8d/Cargo.toml

RUN mkdir -p exam-recorder/src && \
    echo "pub fn stub() {}" > exam-recorder/src/lib.rs && \
    echo '[package]\nname = "exam-recorder"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > exam-recorder/Cargo.toml

RUN mkdir -p evidence-pack/src && \
    echo "pub fn stub() {}" > evidence-pack/src/lib.rs && \
    echo '[package]\nname = "evidence-pack"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > evidence-pack/Cargo.toml

RUN mkdir -p mac-cell/consciousness_rust/src && \
    echo "pub fn stub() {}" > mac-cell/consciousness_rust/src/lib.rs && \
    echo '[package]\nname = "consciousness_rust"\nversion = "0.1.0"\nedition = "2021"\n[lib]\npath = "src/lib.rs"' > mac-cell/consciousness_rust/Cargo.toml

# Create stub services
RUN for svc in gaiaos_ui gaiaos_validation gaiaos_core_agent franklin_guardian inference_encoder teacher_harvest gaialm_trainer gaia_orchestrator uum-8d-core uum-node-agent gaiaos_comm_router gaiaos_comm_agent sensor_sim actuator_sim world_engine gaiaos_24h_cycle uum8d_brain status_reporter gaiaos_mcp_server gaiaos_llm_router spatial_gateway akg_gnn; do \
    mkdir -p "services/${svc}/src" && \
    echo "pub fn stub() {}" > "services/${svc}/src/lib.rs" && \
    echo "[package]\nname = \"${svc}\"\nversion = \"0.1.0\"\nedition = \"2021\"\n[lib]\npath = \"src/lib.rs\"" > "services/${svc}/Cargo.toml"; \
    done

# Now copy the actual vchip service (overwriting stub)
COPY services/gaia1_virtual_chip_service ./services/gaia1_virtual_chip_service

# Build
RUN cargo build --release -p gaia1_virtual_chip_service

# Runtime stage
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/gaiaos

# Copy the binary
COPY --from=builder /build/target/release/gaia1-vchip-service /opt/gaiaos/bin/

ENV RUST_LOG=info
ENV VCHIP_PORT=8001
ENV CELL_ID=cell-01

EXPOSE 8001

HEALTHCHECK --interval=10s --timeout=5s --retries=3 \
    CMD curl -sf http://localhost:8001/health || exit 1

CMD ["/opt/gaiaos/bin/gaia1-vchip-service"]
