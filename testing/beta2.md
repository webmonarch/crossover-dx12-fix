# GPTK 4.0 beta 2 (D3DMetal 4.0b2): test log

**Result: working.** Verified 2026-08-23. Several clean DX12 sessions.

## Test machine

| | |
|---|---|
| Hardware | M5 Max, 40-core GPU |
| macOS | 26.6.2 (25G83) |
| CrossOver | 26.3.0.39832 |
| D3DMetal | 4.0b2 (stock CrossOver ships 3.0) |
| Bottle | `Satisfactory`, `CX_GRAPHICS_BACKEND=d3dmetal`, `D3DM_ENABLE_METALFX=1` |
| Bottle env | also `WINEMSYNC=1`, `WINED3DMETAL=1`, `DXMT_ENABLE_NVEXT=1` from bottle creation |
| VC++ redist | v14.51.36247 x64+x86 already installed |
| Launch options | `-dx12 -NOTEXTURESTREAMING` |

On macOS 26, D3DMetal always uses its Metal 3 backend (`D3DM_MTL4` needs
macOS 27), whatever the GPU advertises.

## Renderer

```
LogRHI: Using Default RHI: D3D12
LogD3D12RHI:   Max supported Feature Level 12_2, shader model 6.6,
               binding tier 3, wave ops supported, atomic64 supported
LogFSR: Successfully initialized FSR Upscaling provider using version '3.1.5'
LogXeSSRHI: Loading XeSS library 2.0.1 on AMD RHI D3D12 — Intel XeSS effect supported
```

No `GGlobalSamplerDescriptorHeapSize` assertion.

## DLSS

DLSS was unavailable, even with `D3DM_ENABLE_METALFX=1` and the `nvngx` bridge
installed:

```
LogDLSS: NVIDIA NGX DLSS supported SR=0 RR=0
[streamline] Disabling DLSS-G since it is not supported on current hardware
```

D3DMetal 4.0b2 reports the GPU as **`AMD Compatibility Mode`** (VendorId
`1002`, DeviceId `0x66af`), and NGX requires an NVIDIA adapter. Apple documents
the MetalFX bridge as experimental, and it didn't engage for this title.

| Upscaler | Status |
|---|---|
| FSR | ✅ 3.1.5, initializes and runs |
| XeSS | ✅ 2.0.10 (library 2.0.1) |
| DLSS Super Resolution | ❌ `SR=0` |
| DLSS Ray Reconstruction | ❌ `RR=0`. Irrelevant: the game ships with RT off |
| DLSS-G / frame gen | ❌ unsupported on this adapter |

FSR registered an `FSRSwapchainProvider`, the hook its frame interpolation
uses.

### Where the NVIDIA libraries load from

Satisfactory ships its own NVIDIA stack (`nvngx_dlss.dll`, `nvngx_dlssd.dll`,
`nvngx_dlssg.dll`, `sl.*.dll`). Streamline loads it from the game's own
`FactoryGame/Plugins/**/Binaries/ThirdParty/Win64`. On this beta the bridge was
inert: about 100 ms of failed Streamline init at startup, plus some log noise.

Beta 3 changed this. See [beta3.md](beta3.md).
