# GaiaOS ATC UI (WASM)
FROM rust:1.82-bookworm as builder

WORKDIR /app

# Install WASM target and trunk
RUN rustup target add wasm32-unknown-unknown && \
    cargo install trunk

# Copy source code
COPY . .

# Build WASM for production
RUN trunk build --release

# Runtime stage - minimal Nginx container
FROM nginx:alpine

# Copy built artifacts
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy Nginx config
COPY services/gaiaos-atc-ui/nginx.conf /etc/nginx/conf.d/default.conf

# Expose port
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
