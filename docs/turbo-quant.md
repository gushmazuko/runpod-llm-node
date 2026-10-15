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

> **Note:** TurboQuant was developed by Google Research and Google DeepMind. The `turbo4` KV cache type used by this project is provided by [TheTom's llama.cpp TurboQuant fork](https://github.com/TheTom/llama-cpp-turboquant/tree/feature/turboquant-kv-cache), not upstream `llama.cpp`.

> [!WARNING]
> **Repetition Collapse Risk with `turbo4`**: On certain 27B+ models and merged architectures (particularly Qwen-derived and Multi-Token Prediction models), 4-bit KV cache quantization like `turbo4` can induce catastrophic repetition collapse (endless token loops). For production stability and agentic coding, **`q8_0` for both K and V cache** is the verified rock-solid baseline.

## Recommendation by Setup

### Single GPU (24GB - 48GB VRAM)
Use `q8_0` for both K and V cache. It provides near-lossless attention fidelity, zero risk of repetition collapse, and cuts KV cache footprint in half compared to `f16`.

```ini
cache-type-k = q8_0
cache-type-v = q8_0
```

### Extreme Memory Scenarios
If context memory is completely exhausted on a small GPU (e.g. 256k on 24GB VRAM) and you are running standard LLaMA-3 architectures (non-MTP), `turbo4` can be used on V-cache:

```ini
cache-type-k = q8_0
cache-type-v = turbo4
```

### Multi-GPU / Unified Memory (96GB - 128GB+)
You can comfortably afford `q8_0` or even `f16` for maximum precision.

```ini
cache-type-k = q8_0
cache-type-v = q8_0
```

## Does `turbo8` Exist?

**No.** TurboQuant is specifically designed for 4-bit precision — that's where the quality-size tradeoff is most dramatic. For higher quality, use `q8_0` or `f16`. The algorithm doesn't have an 8-bit variant because `q8_0` is already near-lossless.

## Impact on Tool Use and Agentic Workloads

For agentic workloads (coding assistants, tool-calling, long document analysis), the KV cache holds the entire conversation and tool output history.

- **Stable Tool Calling**: `q8_0` ensures syntax and function call formatting remain 100% intact.
- **Safety**: Avoids the "repetition collapse" loop when long agentic tool histories accumulate.
- **Speed**: Quantized cache reduces memory bandwidth pressure during decoding, accelerating generation speed on memory-bandwidth-bound hardware.

For production use, **`cache-type-k = q8_0` and `cache-type-v = q8_0`** is our strongly recommended default.
