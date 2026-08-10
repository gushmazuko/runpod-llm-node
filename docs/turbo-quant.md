# KV Cache Quantization: TurboQuant vs f16

One of the most impactful performance levers in `llama.cpp` is the **KV cache format** — how the model stores its "memory" of the conversation context in GPU VRAM.

## The Problem: Context Uses A Lot of VRAM

As context grows, so does the KV cache. On a single RTX 3090 (24GB), a 256k context window with full-precision (f16) cache would require ~26GB — more than the card has.

## The Solution: Cache Quantization

`llama.cpp` allows you to quantize the KV cache independently from the model weights, using the `--cache-type-k` and `--cache-type-v` flags.

## VRAM Comparison (single RTX 3090, Qwen 27B Q8)

| Context Size | f16 cache | q8_0 cache | turbo4 cache |
|:---|:---:|:---:|:---:|
| 32k | ~3.5 GB | ~1.8 GB | ~0.9 GB |
| 96k | ~10 GB | ~5 GB | ~2.5 GB |
| **256k** | **~26 GB** ❌ | **~13 GB** ✅ | **~6 GB** ✅ |
| 1M | ~104 GB | ~52 GB | ~24 GB |

## Cache Format Options

| Format | Description | Quality | VRAM |
|---|---|---|---|
| `f16` | Full 16-bit precision. No compression | ⭐⭐⭐ Lossless | ████████ Highest |
| `q8_0` | 8-bit quantization. Negligible quality loss | ⭐⭐⭐ Near-lossless | ████░░░░ Half |
| `q4_0` | 4-bit quantization | ⭐⭐ Noticeable on long contexts | ██░░░░░░ Quarter |
| `turbo4` | 4-bit, TurboQuant algorithm — designed to match q8 quality at q4 size | ⭐⭐⭐ Near-lossless | ██░░░░░░ Quarter |

> **Note:** `turbo4` is a Cloudflare Research algorithm integrated into `llama.cpp`. It uses a higher-quality 4-bit quantization scheme specifically designed for the KV cache attention patterns, achieving near-8-bit quality at 4-bit storage cost.

## Recommendation by Setup

### Single GPU (24GB VRAM)
Use `q8_0` for best quality within VRAM limits, or `turbo4` to push context windows beyond what `f16` or `q8_0` allow.

```ini
cache-type-k = q8_0
cache-type-v = turbo4
```

### Multi-GPU (4x 24GB = 96GB VRAM)
You can afford `f16` for maximum quality. Only switch to `q8_0`/`turbo4` if you need extreme context windows (500k+) or want to run multiple models in parallel.

```ini
cache-type-k = f16
cache-type-v = f16
```

## Does `turbo8` Exist?

**No.** TurboQuant is specifically designed for 4-bit precision — that's where the quality-size tradeoff is most dramatic. For higher quality, use `f16`. The algorithm doesn't have an 8-bit variant because `q8_0` is already near-lossless.

## Impact on Tool Use and Agentic Workloads

For agentic workloads (coding assistants, tool-calling, long document analysis), the KV cache holds the entire conversation and tool output history. A compressed cache means:

- **More history fits** without swapping or truncation
- **Faster prefill** when processing large contexts
- **Risk**: Potential micro-degradation on extremely long contexts (500k+) with `turbo4`

For most use cases, `cache-type-k = q8_0` with `cache-type-v = turbo4` is the best balance.
