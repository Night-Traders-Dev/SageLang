# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=ubuntu:24.04

FROM ${BASE_IMAGE} AS build

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN apt-get update && apt-get install -y \
    ca-certificates \
    git \
    file \
    cmake \
    ninja-build \
    build-essential \
    pkg-config \
    libcurl4-openssl-dev \
    libssl-dev \
    bash \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . /src

RUN chmod +x /src/build.sh && \
    rm -rf /src/build /src/build_sage /tmp/out && \
    mkdir -p /tmp/out && \
    bash /src/build.sh -DBUILD_SAGE=ON && \
    if [ -f /src/build/sage ]; then cp /src/build/sage /tmp/out/sage_c; fi && \
    if [ -f /src/build_sage/sage ]; then cp /src/build_sage/sage /tmp/out/sage_selfhosted; fi && \
    if [ -f /src/build/sage-lsp ]; then cp /src/build/sage-lsp /tmp/out/sage_lsp_c; fi && \
    if [ -f /src/build_sage/sage-lsp ]; then cp /src/build_sage/sage-lsp /tmp/out/sage_lsp_selfhosted; fi && \
    if [ -f /src/examples/hello.sage ] && [ -f /src/build/sage ]; then \
        rm -f /src/examples/hello && \
        /src/build/sage --compile /src/examples/hello.sage && \
        if [ -f /src/examples/hello ]; then cp /src/examples/hello /tmp/out/hello_sage_c; fi; \
    fi && \
    if [ -f /src/examples/hello.sage ] && [ -f /src/build_sage/sage ]; then \
        rm -f /src/examples/hello && \
        /src/build_sage/sage --compile /src/examples/hello.sage && \
        if [ -f /src/examples/hello ]; then cp /src/examples/hello /tmp/out/hello_sage_selfhosted; fi; \
    fi && \
    file /tmp/out/* 2>/dev/null || true && \
    ls -l /tmp/out

FROM scratch
COPY --from=build /tmp/out/ /
