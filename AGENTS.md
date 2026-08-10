# AGENTS.md

This file provides context for AI coding agents working in this repository.

## What This Project Is

A parameterized bash script that initializes a private LLM inference node on RunPod, exposing an OpenAI-compatible API via a Cloudflare Tunnel.

## Source of Truth

Read `docs/` before making any changes:

- [`docs/architecture.md`](docs/architecture.md) — full stack design and security model
- [`docs/configuration.md`](docs/configuration.md) - environment variables and tuning reference
- [`docs/turbo-quant.md`](docs/turbo-quant.md) — KV cache quantization details

## Key Files

| File | Purpose |
|---|---|
| `runpod_init.sh` | Main entry point — do not hardcode secrets here |

## Rules

- **ABSOLUTE RULE**: Always work via interactive SSH! Never change the Docker template (`dockerStartCmd` or `args`) to automate the bash script execution. Spawn a clean pod that waits (`sleep infinity`), get the SSH URL, connect, and run commands manually.
- All configuration must flow through **environment variables**, never hardcoded values
- `runpod_init.sh` must remain idempotent and reusable by anyone
- Secrets (tokens, API keys) must never appear in committed files

## Cloudflare MCP Permissions

When authorizing the `cloudflare-api` MCP server via OAuth, the AI agent needs specific permissions to manage the infrastructure. See the **Cloudflare MCP Integration** section in [`docs/architecture.md`](docs/architecture.md) for the exact required scopes.
