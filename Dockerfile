# Multi-stage build for smaller final image
FROM debian:stable as zig-builder

# Install dependencies
RUN apt-get update
RUN apt-get install -y \
    nodejs \
    curl \
    npm


# Install Zig
ARG ZIG_VERSION=0.14.0
RUN curl -L https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz -o zig.tar.xz && \
    tar -xf zig.tar.xz && \
    mv zig-linux-x86_64-${ZIG_VERSION} /usr/local/zig && \
    ln -s /usr/local/zig/zig /usr/local/bin/zig

# Set working directory
WORKDIR /app

# Copy source files
COPY . .

RUN npm install
RUN VITE_APP_URL='https://community-crossword.com' VITE_APP_S3='https://crossword.sfo3.digitaloceanspaces.com' VITE_WS_URL='wss://community-crossword.com' npm run build

# Build the application
RUN zig build --release=safe -Dtarget=x86_64-linux 

# Final stage - minimal runtime image
FROM debian:latest

RUN apt-get update
RUN apt-get install -y ca-certificates

# Copy the built binary
COPY --from=zig-builder /app/zig-out/bin/app /usr/local/bin
COPY --from=zig-builder /app/dist /app/dist
COPY --from=zig-builder /app/crossword.map /app/crossword.map

# Set working directory
WORKDIR /app

# Expose port (adjust based on your app)
ENV PORT=8080
EXPOSE ${PORT} 

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# Run the application
CMD ["/usr/local/bin/app"]
