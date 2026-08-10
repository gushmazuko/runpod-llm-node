#!/bin/bash
# ==============================================================================
# RunPod LLM Node Setup Script (Cosmic Standard)
# ==============================================================================

# Export env vars from PID 1 (useful for SSH sessions in RunPod)
if [ -f /proc/1/environ ]; then
    while IFS= read -r -d '' var; do
        export "$var"
    done < /proc/1/environ
fi

# Configuration via Environment Variables:
#   HF_TOKEN         - HuggingFace API Token (Required)
#   MODEL_REPO       - HuggingFace repository (e.g. DavidAU/Qwen3.6-27B-...)
#   MODEL_FILE       - Exact model filename to download
#   CF_TUNNEL_TOKEN  - Cloudflare Tunnel Token for remote management (Required)
#   LLM_API_KEY      - API Key for llama-server (Optional, auto-generated if empty)
#   PORT             - Local port to run llama-server on (Default: 8080)
#   CTX_SIZE         - Context window in tokens (Default: 32768)
#   N_GPU_LAYERS     - Model layers offloaded to GPU (Default: 99)
#   N_PARALLEL       - Number of server slots (Default: 1)
#   CACHE_TYPE_K     - K cache data type (Default: q8_0)
#   CACHE_TYPE_V     - V cache data type (Default: turbo4)
#   FLASH_ATTN       - Flash Attention mode: on, off, or auto (Default: on)
#   LLAMA_CPP_REPO   - llama.cpp-compatible source repository (Optional)
#   LLAMA_CPP_REF    - Git branch, tag, or revision to build (Optional)
#   LLAMA_CPP_BUILD_JOBS - Parallel build jobs (Optional, defaults to nproc)
#   LLAMA_CPP_CUDA_ARCHITECTURES - CUDA architecture to build (Default: native)
# ==============================================================================

set -Eeuo pipefail

# Default values
PORT="${PORT:-8080}"
CTX_SIZE="${CTX_SIZE:-32768}"
N_GPU_LAYERS="${N_GPU_LAYERS:-99}"
N_PARALLEL="${N_PARALLEL:-1}"
CACHE_TYPE_K="${CACHE_TYPE_K:-q8_0}"
CACHE_TYPE_V="${CACHE_TYPE_V:-turbo4}"
FLASH_ATTN="${FLASH_ATTN:-on}"
BATCH_SIZE="${BATCH_SIZE:-4096}"
UBATCH_SIZE="${UBATCH_SIZE:-2048}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
MODEL_DIR="${WORKSPACE_DIR}/models"
LLAMA_CPP_DIR="${WORKSPACE_DIR}/llama-cpp-turboquant"
LLAMA_CPP_REPO="${LLAMA_CPP_REPO:-https://github.com/TheTom/llama-cpp-turboquant.git}"
LLAMA_CPP_REF="${LLAMA_CPP_REF:-feature/turboquant-kv-cache}"
LLAMA_CPP_BUILD_JOBS="${LLAMA_CPP_BUILD_JOBS:-$(nproc)}"
LLAMA_CPP_CUDA_ARCHITECTURES="${LLAMA_CPP_CUDA_ARCHITECTURES:-native}"
LLAMA_SERVER_BIN="${LLAMA_CPP_DIR}/build/bin/llama-server"

echo "[INFO] Starting LLM Node Initialization..."

# 1. Validate required secrets
if [ -z "${HF_TOKEN:-}" ]; then
    echo "[ERROR] HF_TOKEN environment variable is missing!"
    exit 1
fi

if [ -z "${CF_TUNNEL_TOKEN:-}" ]; then
    echo "[ERROR] CF_TUNNEL_TOKEN environment variable is missing!"
    exit 1
fi

if [ -z "${MODEL_REPO:-}" ]; then
    echo "[ERROR] MODEL_REPO environment variable is missing!"
    exit 1
fi

if [ -z "${MODEL_FILE:-}" ]; then
    echo "[ERROR] MODEL_FILE environment variable is missing!"
    exit 1
fi

# 2. Generate or use API Key
if [ -z "${LLM_API_KEY:-}" ]; then
    echo "[WARN] LLM_API_KEY not provided. Generating a secure random key..."
    LLM_API_KEY="sk-$(openssl rand -hex 24)"
    echo "[INFO] Generated LLM_API_KEY: $LLM_API_KEY"
    echo "       Make sure to copy this to your client/UI!"
else
    echo "[INFO] Using user-provided LLM_API_KEY."
fi

# Save key to file for llama-server
echo "$LLM_API_KEY" > "${WORKSPACE_DIR}/api_key.txt"
chmod 600 "${WORKSPACE_DIR}/api_key.txt"

# 3. Install Dependencies
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq build-essential cmake curl git procps python3-pip wget > /dev/null

python3 -m pip install -q --no-cache-dir --break-system-packages --timeout 20 --retries 2 huggingface_hub hf_transfer
export HF_HOME="${WORKSPACE_DIR}/.cache"
export HF_HUB_ENABLE_HF_TRANSFER=1

# 4. Build llama-server and download the model concurrently (Idempotent)
build_llama_server() {
    if [ -x "$LLAMA_SERVER_BIN" ]; then
        echo "[INFO] Reusing existing llama-server binary."
        return
    fi

    if [ -e "$LLAMA_CPP_DIR" ] && [ ! -d "${LLAMA_CPP_DIR}/.git" ]; then
        echo "[ERROR] $LLAMA_CPP_DIR exists but is not a Git checkout."
        echo "        Remove or rename it, then rerun the script."
        exit 1
    fi

    if [ ! -d "${LLAMA_CPP_DIR}/.git" ]; then
        echo "[INFO] Cloning llama.cpp source ($LLAMA_CPP_REF)..."
        git clone --depth 1 --branch "$LLAMA_CPP_REF" "$LLAMA_CPP_REPO" "$LLAMA_CPP_DIR"
    else
        echo "[INFO] Reusing existing llama.cpp source at $LLAMA_CPP_DIR."
    fi

    export PATH="/usr/local/cuda/bin:$PATH"

    if ! command -v nvcc > /dev/null; then
        echo "[ERROR] CUDA compiler (nvcc) is unavailable in this container image."
        echo "        Use a CUDA development image, such as the RunPod PyTorch image."
        exit 1
    fi

    echo "[INFO] Building CUDA-enabled llama-server..."
    cmake -S "$LLAMA_CPP_DIR" -B "${LLAMA_CPP_DIR}/build" \
        -DLLAMA_CUDA=ON \
        -DCMAKE_CUDA_ARCHITECTURES="$LLAMA_CPP_CUDA_ARCHITECTURES" \
        -DCMAKE_BUILD_TYPE=Release
    cmake --build "${LLAMA_CPP_DIR}/build" \
        --config Release \
        --parallel "$LLAMA_CPP_BUILD_JOBS" \
        --target llama-server
}

download_model() {
    mkdir -p "$MODEL_DIR"

    if [ -s "${MODEL_DIR}/${MODEL_FILE}" ]; then
        echo "[INFO] Reusing existing model file: $MODEL_FILE"
        return
    fi

    echo "[INFO] Downloading model: $MODEL_FILE from $MODEL_REPO..."
    HF_TOKEN="$HF_TOKEN" hf download "$MODEL_REPO" "$MODEL_FILE" \
        --local-dir "$MODEL_DIR"
}

build_llama_server &
BUILD_PID="$!"
download_model &
DOWNLOAD_PID="$!"

BUILD_STATUS=0
DOWNLOAD_STATUS=0
wait "$BUILD_PID" || BUILD_STATUS="$?"
wait "$DOWNLOAD_PID" || DOWNLOAD_STATUS="$?"

if [ "$BUILD_STATUS" -ne 0 ] || [ "$DOWNLOAD_STATUS" -ne 0 ]; then
    echo "[ERROR] Parallel setup failed (build=$BUILD_STATUS, download=$DOWNLOAD_STATUS)."
    exit 1
fi

if [ ! -x "$LLAMA_SERVER_BIN" ]; then
    echo "[ERROR] llama-server build did not produce $LLAMA_SERVER_BIN."
    exit 1
fi

if [ ! -s "${MODEL_DIR}/${MODEL_FILE}" ]; then
    echo "[ERROR] Model download did not produce ${MODEL_DIR}/${MODEL_FILE}."
    exit 1
fi

# 6. Install Cloudflared
if ! command -v cloudflared &> /dev/null; then
    echo "[INFO] Installing cloudflared..."
    wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb \
        -O /tmp/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cloudflared-linux-amd64.deb > /dev/null
    rm /tmp/cloudflared-linux-amd64.deb
fi

# 7. Start Services
is_service_running() {
    local pid_file="$1"
    local pid

    [ -f "$pid_file" ] || return 1
    pid="$(<"$pid_file")"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2> /dev/null
}

SERVER_PID_FILE="${WORKSPACE_DIR}/llama-server.pid"
if is_service_running "$SERVER_PID_FILE"; then
    echo "[INFO] llama-server is already running."
else
    if [ "$FLASH_ATTN" = "on" ]; then
        FLASH_FLAG="--flash-attn on"
    else
        FLASH_FLAG=""
    fi

    echo "[INFO] Starting llama-server on port $PORT..."
    nohup "$LLAMA_SERVER_BIN" \
        -m "${MODEL_DIR}/${MODEL_FILE}" \
        -a "${MODEL_FILE%.gguf}" \
        --host 0.0.0.0 --port "$PORT" \
        -ngl "$N_GPU_LAYERS" \
        -c "$CTX_SIZE" \
        -b "$BATCH_SIZE" \
        -ub "$UBATCH_SIZE" \
        --parallel "$N_PARALLEL" \
        --cont-batching \
        $FLASH_FLAG \
        --cache-type-k "$CACHE_TYPE_K" \
        --cache-type-v "$CACHE_TYPE_V" \
        --jinja \
        --api-key-file "${WORKSPACE_DIR}/api_key.txt" > "${WORKSPACE_DIR}/server.log" 2>&1 &
    echo "$!" > "$SERVER_PID_FILE"
fi

TUNNEL_PID_FILE="${WORKSPACE_DIR}/cloudflared.pid"
if is_service_running "$TUNNEL_PID_FILE"; then
    echo "[INFO] Cloudflare Tunnel is already running."
else
    echo "[INFO] Starting Cloudflare Tunnel (Remotely Managed)..."
    nohup cloudflared tunnel --no-autoupdate run --token "$CF_TUNNEL_TOKEN" > "${WORKSPACE_DIR}/tunnel.log" 2>&1 &
    echo "$!" > "$TUNNEL_PID_FILE"
fi

echo "[SUCCESS] Node initialized and services started in background."
