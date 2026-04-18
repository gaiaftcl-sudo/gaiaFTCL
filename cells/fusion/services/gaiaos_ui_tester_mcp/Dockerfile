# GaiaOS UI Tester MCP Server
# Multi-arch: linux/amd64, linux/arm64

FROM rust:bookworm AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install nightly (needed for edition2024)
RUN rustup toolchain install nightly && rustup default nightly

# Copy source
COPY . .

# Build release binary
RUN cargo build --release

# Runtime stage
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/target/release/gaiaos_ui_tester_mcp /app/gaiaos_ui_tester_mcp

# Copy evidence files (canonicals, environments, agents)
COPY evidence /app/evidence

# Create remaining evidence directories
RUN mkdir -p /app/evidence/{ui_expected,ui_contract,agent_census,domain_tubes,closure_game,echo,mcp_calls}

ENV RUST_LOG=info
ENV MCP_PORT=8900

EXPOSE 8900

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8900/health || exit 1

CMD ["/app/gaiaos_ui_tester_mcp"]
