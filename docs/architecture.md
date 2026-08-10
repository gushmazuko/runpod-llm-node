# Architecture

## Overview

This project implements a **private, ephemeral LLM inference node** on RunPod GPUs, connected to the internet through a Cloudflare Tunnel with Zero Trust security.

## Traffic Flow

```
User / Client
     │
     │  HTTPS (TLS 1.3)
     ▼
Cloudflare Edge  ──── WAF / DDoS Protection
     │
     │  Bearer Token checked ← LLM_API_KEY
     │
     │  Encrypted Tunnel (cloudflared)
     ▼
RunPod GPU Pod
     │
     │  localhost:8080
     ▼
llama-server (llama.cpp)
     │
     └── /workspace/models/*.gguf
```

## Components

### RunPod Pod
- Rents GPU(s) on demand — you pay only when the pod is running
- `llama-server` serves an **OpenAI-compatible REST API** on `localhost:8080`
- No public ports are opened on the pod itself
- All outbound connectivity is via the Cloudflare tunnel

### Cloudflare Tunnel (`cloudflared`)
- Establishes an outbound-only encrypted connection from the pod to Cloudflare's edge
- Uses **Remotely Managed** mode: the tunnel configuration (which domain maps to which port) lives in the Cloudflare Zero Trust dashboard — not on the server
- This means the script only needs one `CF_TUNNEL_TOKEN` environment variable; no config files required

### Cloudflare Zero Trust Access
- `api.yourdomain.com` — the public LLM API endpoint, protected only by the `LLM_API_KEY` Bearer token (same model as OpenAI's API)
- `ai.yourdomain.com` — the Open WebUI frontend, protected by Cloudflare Access (OAuth login, no password exposed to the internet)

## Setting Up the Cloudflare Tunnel (First Time)

1. Go to [Cloudflare Zero Trust Dashboard](https://one.cloudflare.com) → **Networks → Tunnels**
2. Click **Create a tunnel** → choose **Cloudflared** → give it a name (e.g. `runpod-llm`)
3. In the **Public Hostname** tab, add:
   - Subdomain: `api`, Domain: `yourdomain.com`, Service: `http://localhost:8080`
4. Copy the **Tunnel Token** shown on the connector screen — this is your `CF_TUNNEL_TOKEN`
5. Save. The tunnel will activate automatically when `cloudflared` connects with this token.

## Security Model

| Layer | Mechanism | Notes |
|---|---|---|
| Transport | TLS 1.3 | Handled by Cloudflare automatically |
| API Authentication | Bearer Token (`LLM_API_KEY`) | 48-char cryptographically random key |
| UI Authentication | Cloudflare Access (OAuth) | Login with your identity provider |
| Network | No open ports on RunPod | All traffic via encrypted tunnel |
| DDoS / Bot Protection | Cloudflare WAF | Free tier covers basic protection |

## Cloudflare MCP Integration

If managing this infrastructure using an AI agent via the `cloudflare-api` MCP server, ensure the OAuth token uses a **Custom** access template with the following permissions granted:

**DNS & Zones:**
- DNS: `Read`, `Write`
- Zone: `Read`

**Cloudflare One / Zero Trust:**
- Teams Connector Cloudflared: `Read`, `Write` (to manage Tunnels)
- Access: `Read`, `Write` (to manage Access Apps, Groups, and Policies)

If the token only has `Read` permissions, agents will be able to inspect the configuration but will fail with `403 Forbidden` when attempting to apply configuration changes (like creating tunnels or access policies).
