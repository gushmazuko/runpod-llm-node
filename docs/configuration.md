# Configuration Reference

## Environment Variables

All configuration is passed to the `runpod_init.sh` script via environment variables — no files need to be modified.

| Variable | Required | Default | Description |
|---|---|---|---|
| `HF_TOKEN` | ✅ | — | HuggingFace API token. Get it at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) |
| `MODEL_REPO` | ✅ | — | HuggingFace repository path (reference: `DavidAU/Qwen3.6-27B-Fable-Fusion-711-Uncensored-Heretic-NM-DAU-NEO-MAX-MTP-GGUF`) |
| `MODEL_FILE` | ✅ | — | Exact `.gguf` filename within the repo (reference: `Qwen3.6-27B-Fable-Fus-711-UnHeretic-NM-DAU-NEO-MAX-NEO-Q6_K.gguf`) |
| `CF_TUNNEL_TOKEN` | ✅ | — | Cloudflare Tunnel token. Retrieved from Zero Trust dashboard → Tunnels |
| `LLM_API_KEY` | ☑️ | auto-generated | Bearer token for the API. If not provided, a secure 48-char key is generated and printed to the logs |
| `PORT` | ☑️ | `8080` | Local port for `llama-server` to listen on |
| `CTX_SIZE` | ☑️ | `32768` | Context window in tokens |
| `N_GPU_LAYERS` | ☑️ | `99` | Number of model layers offloaded to the GPU |
| `N_PARALLEL` | ☑️ | `1` | Number of concurrent server slots |
| `CACHE_TYPE_K` | ☑️ | `q8_0` | K cache data type |
| `CACHE_TYPE_V` | ☑️ | `turbo4` | V cache data type provided by the TurboQuant build |
| `FLASH_ATTN` | ☑️ | `on` | Flash Attention mode: `on`, `off`, or `auto` |
| `LLAMA_CPP_REPO` | ☑️ | `https://github.com/TheTom/llama-cpp-turboquant.git` | Source repository used to build `llama-server` with CUDA on the first run |
| `LLAMA_CPP_REF` | ☑️ | `feature/turboquant-kv-cache` | Git branch, tag, or revision to build from the source repository |
| `LLAMA_CPP_BUILD_JOBS` | ☑️ | `nproc` | Number of parallel compiler jobs. Lower this value if the Pod runs out of RAM during the build |
| `LLAMA_CPP_CUDA_ARCHITECTURES` | ☑️ | `native` | CUDA architecture compiled for the current Pod GPU. Keep `native` for the fastest first build |

### Where to set them in RunPod

When deploying a new Pod:
1. Choose your GPU and base image (e.g. RunPod PyTorch)
2. Expand **"Environment Variables"** section
3. Add each variable as a key-value pair
4. Save the overrides as a private template
5. Deploy the template with the RunPod MCP server
6. Use the Pod-specific SSH command returned after deployment to run `runpod_init.sh`

The project intentionally does not use a RunPod On-Start Script. Pod lifecycle
and initialization are controlled by the AI agent through MCP and the generated
SSH endpoint.

## Llama.cpp Server API

The server exposes a fully **OpenAI-compatible API** at `http://localhost:$PORT/v1`:

```
GET  /v1/models          — List available models
POST /v1/chat/completions — Chat inference
POST /v1/completions      — Raw completion
GET  /health             — Health check
```

Any client that supports OpenAI can point to your tunnel URL with your API key.
