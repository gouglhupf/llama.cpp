# Personal test image: CUDA 13 + sm_86 (RTX 3090), static build with native CPU tuning.
# Intended for testing PR #21067 (prefetch weights) on the build machine itself.
# GGML_NATIVE=ON assumes the machine running the container is the same as the one
# building it (AVX2+ tuned for the host CPU, which matters with --cpu-moe).
ARG UBUNTU_VERSION=24.04
ARG CUDA_VERSION=13.4.1
ARG GCC_VERSION=14

ARG BASE_CUDA_DEV_CONTAINER=docker.io/nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}
ARG BASE_CUDA_RUN_CONTAINER=docker.io/nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu${UBUNTU_VERSION}

FROM ${BASE_CUDA_DEV_CONTAINER} AS build

ARG GCC_VERSION
# RTX 3090 = Ampere = compute capability 8.6
ARG CUDA_DOCKER_ARCH=86

RUN apt-get update && \
    apt-get install -y gcc-${GCC_VERSION} g++-${GCC_VERSION} build-essential cmake git libgomp1

ENV CC=gcc-${GCC_VERSION} CXX=g++-${GCC_VERSION} CUDAHOSTCXX=g++-${GCC_VERSION}

WORKDIR /app

COPY . .

RUN cmake -B build \
    -DGGML_NATIVE=ON \
    -DGGML_CUDA=ON \
    -DGGML_BACKEND_DL=OFF \
    -DGGML_CPU_ALL_VARIANTS=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DCMAKE_CUDA_ARCHITECTURES=${CUDA_DOCKER_ARCH} && \
    cmake --build build --config Release -j$(nproc) --target llama-server llama-bench llama-cli

FROM ${BASE_CUDA_RUN_CONTAINER}

RUN apt-get update && \
    apt-get install -y libgomp1 curl && \
    apt autoremove -y && \
    apt clean -y && \
    rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/build/bin/llama-server /app/build/bin/llama-bench /app/build/bin/llama-cli /app/

ENV LLAMA_ARG_HOST=0.0.0.0
ENV LLAMA_ARG_PORT=8080

HEALTHCHECK CMD [ "curl", "-f", "http://localhost:8080/health" ]

ENTRYPOINT [ "/app/llama-server" ]
