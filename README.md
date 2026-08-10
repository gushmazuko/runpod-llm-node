# RunPod LLM Node

> Rent the GPU. Keep the memory.

Run any GGUF model on an on-demand RunPod GPU and expose it as a stable, authenticated, OpenAI-compatible API through Cloudflare Tunnel.

The key idea is separation: **Open WebUI and your chat history stay on a server you control, while RunPod provides replaceable compute only.** Your browser UI, users, files, and long-term conversation history do not need to live on an expensive or ephemeral GPU pod. At the same time, AI agents, SDKs, and other OpenAI-compatible clients can reach the model directly from the internet with a standard Bearer API key.

The node is designed to be operated by an AI coding agent such as Claude Code or Codex with the Cloudflare and RunPod MCP servers connected. Configure the private template once, ask the agent to launch the LLM, do your work, then ask it to stop the pod. GPU billing stops while your private chat system remains online.

[![Runtime](https://img.shields.io/badge/runtime-Bash-4EAA25?logo=gnu-bash&logoColor=white)](runpod_init.sh)
[![API](https://img.shields.io/badge/API-OpenAI--compatible-412991)](https://github.com/TheTom/llama-cpp-turboquant/tree/feature/turboquant-kv-cache/tools/server)
[![Inference](https://img.shields.io/badge/inference-llama.cpp%20TurboQuant-111111)](https://github.com/TheTom/llama-cpp-turboquant/tree/feature/turboquant-kv-cache)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#license)

Created and maintained by [gushmazuko](https://github.com/gushmazuko).

## Why this project exists

A cloud GPU should not become the system of record for your AI life.

Putting Open WebUI, chat history, model weights, and inference on the same rental GPU couples private data to disposable infrastructure. It also means paying GPU prices to keep a lightweight web application and database online.

RunPod LLM Node splits the stack into three independent layers:

1. **Your server is the memory.** A self-hosted Open WebUI instance stores users, chats, files, and application state on infrastructure you control.
2. **RunPod is the muscle.** The pod loads the model, processes the current request, streams tokens back, and can be stopped or replaced without taking your chat database with it.
3. **Cloudflare is the front door.** A stable domain reaches the pod through an outbound-only tunnel, without publishing the inference port through RunPod.

This gives you a private chat experience for humans and a familiar API endpoint for agents, without turning the GPU provider into your permanent application host.

## Architecture

```text
                       CONTROL PLANE - AI-OPERATED

 Claude Code / Codex  --->  Cloudflare MCP + RunPod MCP
                            launch, verify, and stop the node

 Claude Code / Codex  --->  interactive SSH
                            initialize and diagnose the live pod

                       PERSISTENT - INFRASTRUCTURE YOU CONTROL

 Browser  ---------->  Open WebUI on your server
                       - users and authentication
                       - chat history and files
                       - webui.db and backups
                                  |
                                  | OpenAI-compatible HTTPS request
 Inference agents / SDKs ----------+ Authorization: Bearer <LLM_API_KEY>
                                  |
                                  v
                         Cloudflare edge
                                  |
                         outbound-only tunnel
                                  |
                                  v
                       DISPOSABLE - RUNPOD GPU

                         llama-server :8080
                         - GGUF inference
                         - no chat database
                         - no public inference port
                                  |
                                  v
                         /workspace volume
                         - model weights
                         - compiled binary
                         - API key file
                         - operational logs
```

Open WebUI is deliberately **not** installed on the RunPod pod by this project. Run it on your own always-on server or VPS, back up its data there, and connect it to the public API endpoint created here.

## Operated by your AI agent

This is not merely a shell script for a cloud GPU. It is an agent-operated inference node. Give Claude Code, Codex, or another capable agent access to both the Cloudflare and RunPod MCP servers, point it at this repository, and ask it to launch or stop the LLM. The agent reads the repository instructions and handles the infrastructure workflow.

Interactive SSH remains the explicit execution and diagnostic channel inside the pod. The agent must never hide `runpod_init.sh` execution in Docker `dockerStartCmd`, template `args`, or an On-Start Script.

### What "private" means here

This architecture keeps persistent chat ownership with you, but it does not pretend that inference happens without moving data:

- Prompts and generated tokens pass through Cloudflare and are processed on the RunPod GPU while a request is active.
- This project does not install a conversation database or persist Open WebUI chat history on RunPod.
- The RunPod network volume is persistent by design. It stores model and build artifacts, the API key file, and service logs so a replacement pod can reuse them.
- Cloudflare and RunPod account settings, logs, and provider policies remain part of your threat model. Review them for your privacy and compliance requirements.
- This is a self-hosted, privacy-oriented architecture, not an air-gapped or end-to-end encrypted system.

## What you get

- A stable `https://api.yourdomain.com/v1` endpoint for Open WebUI, coding agents, automation, and OpenAI-compatible SDKs
- AI-operated launch and shutdown through Cloudflare and RunPod MCP after one-time template setup
- Bearer-token authentication enforced by `llama-server`
- No RunPod HTTP exposure for the inference service
- An outbound-only Cloudflare Tunnel with Cloudflare's network and security layer in front
- CUDA-native compilation for the selected GPU architecture
- Parallel model download and `llama-server` compilation on first boot
- Idempotent reruns that reuse the model, compiled binary, and running processes
- A portable `/workspace` network volume for fast pod replacement within a compatible RunPod data center
- Configurable context size, GPU offload, continuous batching, Flash Attention, and KV cache types
- Optional TurboQuant KV cache support for fitting longer contexts into limited VRAM

## Why this stack

| Component | Why it is here |
|---|---|
| [RunPod](https://www.runpod.io/) | Provides on-demand GPUs without making the rental pod the permanent home of your UI or chats. A network volume lets model artifacts survive pod replacement. |
| [llama.cpp TurboQuant fork](https://github.com/TheTom/llama-cpp-turboquant/tree/feature/turboquant-kv-cache) | Builds `llama-server` with CUDA and TurboQuant KV cache support, runs quantized GGUF models, and exposes an OpenAI-compatible API with streaming and tool-call support. |
| [Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/) | Gives the pod a stable public hostname through outbound-only connections, so port `8080` does not need to be published by RunPod. |
| Bearer API key | Uses the authentication pattern already understood by OpenAI clients. The key is checked at `llama-server`, behind the tunnel. |
| [Open WebUI](https://openwebui.com/) on your server | Keeps the chat database, users, uploaded files, and backups on infrastructure you control instead of the GPU rental. |
| Claude Code or Codex with MCP | Uses Cloudflare and RunPod MCP to operate the infrastructure on your behalf. |
| Environment variables | Keep one reusable script configurable without baking tokens, model choices, or deployment details into source code. |
| Interactive SSH initialization | Keeps live execution observable and debuggable. The pod starts clean, waits, and is initialized explicitly instead of hiding execution in Docker template arguments. |
| TurboQuant fork | Trades KV cache size for longer context windows. It is useful on VRAM-constrained GPUs, but remains an advanced, experimental choice. |

## What the script does

[`runpod_init.sh`](runpod_init.sh) performs the node bootstrap:

1. Reads configuration from environment variables and validates required secrets.
2. Generates a 192-bit random API key when `LLM_API_KEY` is not supplied.
3. Installs build and download dependencies.
4. Builds CUDA-enabled `llama-server` and downloads the selected GGUF model in parallel.
5. Installs `cloudflared`.
6. Starts `llama-server` and the remotely managed Cloudflare Tunnel in the background.
7. Reuses existing artifacts and processes when safely rerun.

The script itself does **not** create a RunPod pod, create the Cloudflare Tunnel, deploy Open WebUI, or configure automatic startup. The AI agent handles the surrounding infrastructure through Cloudflare and RunPod MCP, while live initialization remains explicit over SSH.

## Quick start

### 1. Prerequisites

You need:

- A [RunPod](https://www.runpod.io/) account with GPU access
- An SSH public key added under RunPod account settings
- A [Hugging Face](https://huggingface.co/) account and token with access to your chosen GGUF model
- A domain on [Cloudflare](https://www.cloudflare.com/)
- An AI coding agent such as Claude Code or Codex with both Cloudflare and RunPod MCP connected
- A machine from which you can open an interactive SSH session

Clone this repository on your administration machine so you can review the script and documentation:

```bash
git clone https://github.com/gushmazuko/runpod-llm-node.git
cd runpod-llm-node
```

### 2. Bootstrap Cloudflare once

Ask the AI agent to use Cloudflare MCP to configure the Tunnel, DNS, and Access for this project. Grant the MCP server the permissions described in [Architecture](docs/architecture.md#cloudflare-mcp-integration). The agent reads the repository documentation and handles the rest.

### 3. Configure the private RunPod template once

Create a private template for a clean GPU pod that waits for manual initialization. Do not put `runpod_init.sh` in the Docker start command, template `args`, or an On-Start Script.

| RunPod setting | Recommended value | Reason |
|---|---|---|
| GPU | Enough VRAM for the model weights and KV cache | Context length and concurrency also consume VRAM. |
| Container image | CUDA development image with `nvcc`, for example `runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404` | The script compiles a CUDA-native `llama-server`. |
| Container disk | At least 30 GB | Holds the base container and temporary build dependencies. |
| Network volume | Model size plus at least 20 percent, mounted at `/workspace` | Preserves the model and compiled binary independently of the pod. |
| Start behavior | A clean pod waiting with `sleep infinity` | Initialization is performed manually through SSH. |
| Exposed HTTP ports | None | The inference API is published only through Cloudflare Tunnel. |
| Exposed TCP ports | `22` only | Used for SSH administration. Do not expose port `8080`. |

Save the template once. After that, the normal workflow is for an AI agent to find and deploy it through RunPod MCP instead of recreating pod configuration by hand.

### 4. Add environment variables

Use RunPod Secrets for sensitive values. Never commit real tokens to this repository or bake them into a public template.

| Variable | Required | Default | Purpose |
|---|---:|---|---|
| `HF_TOKEN` | Yes | - | Hugging Face access token |
| `MODEL_REPO` | Yes | - | Repository containing the GGUF model, such as `bartowski/Qwen2.5-Coder-32B-Instruct-GGUF` |
| `MODEL_FILE` | Yes | - | Exact `.gguf` filename in that repository |
| `CF_TUNNEL_TOKEN` | Yes | - | Token for the remotely managed Cloudflare Tunnel |
| `LLM_API_KEY` | No | Generated | Bearer key shared with Open WebUI and API clients |
| `PORT` | No | `8080` | Local `llama-server` port |
| `CTX_SIZE` | No | `32768` | Context window in tokens |
| `N_GPU_LAYERS` | No | `99` | Layers offloaded to the GPU |
| `N_PARALLEL` | No | `1` | Concurrent server slots |
| `CACHE_TYPE_K` | No | `q8_0` | K side of the KV cache |
| `CACHE_TYPE_V` | No | `turbo4` | V side of the KV cache |

Set `LLM_API_KEY` explicitly when clients already depend on a fixed key. If omitted, the generated key is shown in the initialization output and stored at `/workspace/api_key.txt` with mode `600`.

See [Configuration Reference](docs/configuration.md) for additional tuning variables.

### 5. Deploy through RunPod MCP

Ask Claude Code or Codex to read `AGENTS.md` and use the Cloudflare and RunPod MCP servers to launch the node. The agent handles GPU selection, deployment, verification, and the SSH workflow. It must not rewrite template `dockerStartCmd` or `args` to execute the initialization script automatically.

### 6. Initialize through interactive SSH

The AI agent performs initialization through the pod-specific interactive SSH endpoint. For manual recovery, the connection will resemble one of these:

```bash
ssh POD_USER@ssh.runpod.io -i ~/.ssh/id_ed25519
```

```bash
ssh root@POD_PUBLIC_IP -p MAPPED_PORT -i ~/.ssh/id_ed25519
```

Inside the pod, download, inspect, and run the script manually:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/gushmazuko/runpod-llm-node/main/runpod_init.sh \
  -o /tmp/runpod_init.sh
less /tmp/runpod_init.sh
bash /tmp/runpod_init.sh
```

The first run compiles the server and downloads the model. Later runs reuse `/workspace` when the same network volume is attached.

### 7. Verify the public API

From your administration machine:

```bash
export LLM_BASE_URL='https://api.yourdomain.com/v1'
export LLM_API_KEY='replace-with-your-key'

curl "$LLM_BASE_URL/models" \
  -H "Authorization: Bearer $LLM_API_KEY"
```

Test a chat completion:

```bash
curl "$LLM_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $LLM_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "replace-with-the-model-id-from-v1-models",
    "messages": [
      {"role": "user", "content": "Reply with: private inference is online"}
    ],
    "stream": false
  }'
```

## Connect Open WebUI without moving your chats to RunPod

Run Open WebUI on your own server with persistent storage. In Open WebUI:

1. Open **Admin Settings -> Connections -> OpenAI**.
2. Add a new OpenAI-compatible connection.
3. Set the URL to `https://api.yourdomain.com/v1`.
4. Set the API key to your `LLM_API_KEY`.
5. Save and let Open WebUI discover the model through `/v1/models`.

Open WebUI sends the active conversation context to the model for inference, but its persistent chat history remains in the Open WebUI database on your server. Protect the UI separately, for example with Cloudflare Access and your identity provider.

## Connect AI agents and SDKs

Most OpenAI-compatible tools only need two values:

```bash
export OPENAI_BASE_URL='https://api.yourdomain.com/v1'
export OPENAI_API_KEY='replace-with-your-key'
```

Point the client at `OPENAI_BASE_URL` and choose the model ID returned by `/v1/models`. No RunPod-specific SDK is required in the client.

The single Bearer key is suitable for a private deployment with trusted clients. For public or multi-tenant use, add per-client credentials, rate limits, audit controls, and key rotation in front of this endpoint.

## Operations

Day-to-day operation is deliberately simple: ask your AI agent to launch the LLM, use the returned OpenAI-compatible endpoint, and ask the agent to stop the pod when your work is complete. The agent uses Cloudflare MCP, RunPod MCP, and interactive SSH as required.

```bash
# Follow inference logs
tail -f /workspace/server.log

# Follow tunnel logs
tail -f /workspace/tunnel.log

# Check the origin directly from inside the pod
curl http://localhost:8080/health \
  -H "Authorization: Bearer $(cat /workspace/api_key.txt)"
```

When inference is not needed, tell the agent to stop the pod so GPU billing stops while the pod and its persistent disk remain available. The next time you need the model, ask the agent to launch it again.

## Security model

| Layer | Control | Important boundary |
|---|---|---|
| Client transport | HTTPS to Cloudflare | Cloudflare terminates the client TLS connection. |
| Origin connectivity | Outbound-only Cloudflare Tunnel | RunPod port `8080` is not exposed publicly. |
| API authentication | `LLM_API_KEY` checked by `llama-server` | Cloudflare Tunnel does not validate this Bearer key for you. |
| UI authentication | Your Open WebUI authentication, optionally Cloudflare Access | Open WebUI is outside this project and must be secured separately. |
| Secrets | RunPod Secrets and environment variables | The API key is also written to `/workspace/api_key.txt`. Protect the volume and tunnel token. |
| Administration | SSH key authentication on port `22` | SSH remains an exposed management path and should be restricted and monitored. |
| Persistent data | Open WebUI database on your server | The pod has no chat database, but operational logs and infrastructure-provider retention still require review. |

For an internet-facing or shared deployment, consider Cloudflare rate limiting, WAF policies, API key rotation, and a dedicated API gateway for per-user authorization.

## Model and performance guidance

Model weight quantization and KV cache quantization solve different problems:

- Start with a `Q4_K_M` or `Q5_K_M` GGUF when speed and VRAM efficiency matter.
- Use `Q6_K` or `Q8_0` when maximum weight precision matters more than throughput and memory use.
- Keep `CACHE_TYPE_K=q8_0` for a high-quality K cache.
- Use `CACHE_TYPE_V=turbo4` to reduce V-cache VRAM use and reach longer contexts, understanding that it relies on the configured TurboQuant fork.
- Reduce `CTX_SIZE`, `N_PARALLEL`, batch size, or model quantization when the server runs out of VRAM.

Read [KV Cache Quantization](docs/turbo-quant.md) before using aggressive long-context settings.

## Documentation

| Document | Contents |
|---|---|
| [Architecture](docs/architecture.md) | Traffic flow, security model, Cloudflare Tunnel, and MCP permissions |
| [Configuration Reference](docs/configuration.md) | Environment variables and inference tuning |
| [KV Cache Quantization](docs/turbo-quant.md) | `f16`, `q8_0`, and TurboQuant tradeoffs |

## Known boundaries

- The default build uses a third-party TurboQuant fork and branch, not upstream `llama.cpp`.
- The script targets Debian or Ubuntu based CUDA development images with `apt-get` and `nvcc`.
- `cloudflared` is currently installed from the latest AMD64 Debian package.
- Automatic boot supervision, health-based restart, metrics, and multi-node failover are outside the current scope.
- A single API key does not provide per-user authorization, quotas, or tenant isolation.
- RunPod network volumes are persistent infrastructure. Delete or sanitize them explicitly when you no longer need the stored artifacts.

## Contributing

Issues and pull requests are welcome. Useful reports include:

- GPU model and VRAM
- RunPod image
- GGUF model and quantization
- Context size and parallel slot count
- Relevant lines from `server.log` or `tunnel.log`, with secrets removed
- Exact reproduction steps

Please never post Hugging Face tokens, Cloudflare tunnel tokens, API keys, or unredacted private prompts.

If this architecture helps you, star the repository and share what you built with it.

## License

MIT
