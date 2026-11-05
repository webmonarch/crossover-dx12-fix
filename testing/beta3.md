# GPTK 4.0 beta 3 (D3DMetal 4.0b3): test log

**Result: working.** Verified 2026-11-04. Nine clean DX12 sessions.

## Test machine

| | |
|---|---|
| Hardware | M5 Max |
| macOS | 27.0.1 (26A434) |
| CrossOver | 26.3 |
| D3DMetal | 4.0b3 (stock CrossOver ships 3.0) |
| Bottle | `Steam`, `CX_GRAPHICS_BACKEND=d3dmetal` |
| Output | 3840×2160, 60% screen percentage (render 2304×1296) |
| Launch options | none of our own (`Command Line: -NO_EOS_OVERLAY`, plus `-d3d12` in two runs, both added by the launcher), except `-slnoswapchainprovider` in three test runs. No `-dx12`, no `-NOTEXTURESTREAMING` |

On macOS 27, D3DMetal's Metal 4 backend (`D3DM_MTL4`) is on by default, so
these results come from that backend. Beta 2 was tested on the Metal 3 backend.

## Sessions

| Log (local time) | D3DMetal | Result |
|---|---|---|
| 14:49, 15:32 | 3.0, before the swap | crashed: `GGlobalSamplerDescriptorHeapSize <= MaximumSamplerHeapSize` |
| 16:11, 16:12 | 4.0b3 | D3D12, exited cleanly |
| 16:19 to 16:33 | 4.0b3 | D3D12, about 14 min, DLSS switched on and off several times, exited cleanly |
| 17:11 to 17:45 | 4.0b3 | six D3D12 sessions for the performance runs below, all exited cleanly |

The 16:19 session had no DX flag and still ran D3D12, the game's default. The 15:19 and 16:16 sessions ran on D3D11 and aren't counted. The only crash
reports from the day are the two from before the swap.

## Renderer

```
LogD3D12RHI:   Max supported Feature Level 12_2, shader model 6.7, binding tier 3,
               wave ops supported, atomic64 supported
LogFSR: Successfully initialized FSR Upscaling provider using version '3.1.5'
LogXeSSModule: XeSS successfully initialized
```

Beta 3 reports shader model **6.7**; beta 2 reported 6.6.

## DLSS and `D3DM_ENABLE_METALFX`

Beta 3 changed how the GPU is reported once CrossOver's DLSS setting is on.

| | `D3DM_ENABLE_METALFX=0` | `D3DM_ENABLE_METALFX=1` |
|---|---|---|
| Adapter reported | `VendorId: 1002, DeviceId: 66af` (AMD) | `VendorId: 10de, DeviceId: 2684` (NVIDIA) |
| UE RHI | `AMD D3D12` | `NVIDIA D3D12` |
| DLSS | `SR=0 RR=0` | `SR=1 RR=1`, via `system32\nvngx.dll` (Apple's MetalFX bridge) |
| Reflex | `lowLatencyAvailable=0` | `lowLatencyAvailable=1` |
| Swap chain owner | FSR's `FSRSwapchainProvider` | Streamline's `FStreamlineD3D12DXGISwapchainProvider` |

The adapter name stays `AMD Compatibility Mode` either way; only the vendor and
device IDs change. Once the GPU reports as NVIDIA, the game starts its NVIDIA
stack (Streamline with DLSS-G, Reflex and DeepDVC), and Streamline hooks the
swap chain. Several of the NVIDIA calls fail under translation:

```
dlss_gEntry.cpp:390[setFlipConfig] NvAPI_D3D12_SetFlipConfig() returned -1
deepDVCEntry.cpp:352[slOnPluginStartup] NGX parameter indicating DeepDVCContext support cannot be found
ota.cpp:136[execThreadProc] Failed to create process C:\windows\system32\nvngx_update.exe ...
```

DLSS itself is MetalFX underneath. It creates a normal NGX feature at the same
render resolution FSR uses, so it brings no resolution advantage:

```
Creating NGX DLSS Feature SrcRect=[0x0->2304x1296], DestRect=[0x0->3840x2160],
ScaleX=0.600000, NGXDLSSPreset=Preset C(3), NGXPerfQuality=Balanced(1), DenoiseMode=Off
```

### Performance

All runs on 2026-11-04, same save and spot, 4K output, 60% screen percentage,
**VSync off**, frame generation off unless noted. FPS was read off the in-game
counter and cross-checked against the log's frame counter over 10 s windows.

| Run | `D3DM_ENABLE_METALFX` | Streamline | FSR | DLSS |
|---|---|---|---|---|
| A | `0` | inactive (AMD adapter) | **~32** | not available |
| B | `1` | on (stock) | ~25 | ~24 |
| C/D | `1` | off (`r.Streamline.InitializePlugin=0`) | ~25 | ~30 |

- **The setting costs FSR about 20%** (~32 to ~25), and disabling Streamline
  doesn't win it back. The cost sits in NVIDIA mode itself: either the game's
  NVIDIA-specific paths, or D3DMetal behaving differently when it reports an
  NVIDIA GPU. Which one hasn't been isolated.
- The best DLSS result (~30) doesn't beat FSR with the setting off (~32).
- Streamline may cost DLSS a few FPS (~24 vs ~30), but that rests on single
  runs.
- An earlier comparison with VSync on gave ~40 vs ~30. On a 120 Hz display,
  VSync snaps the frame rate to 120/n (30, 24, 20…), so those figures were
  quantized and are superseded by the table above.

How each run was confirmed from `FactoryGame.log`:

- A: `VendorId: 1002`, `SR=0`, `Skip registering IDXGISwapchainProvider`.
- B: `VendorId: 10de`, `Registering FStreamlineD3D12DXGISwapchainProvider`.
- C/D: `Initialization of StreamlineCore is disabled`, still `SR=1`.

### Frame generation

Turning on the game's frame generation **lowered** the rendered frame rate:
FSR ~32 to ~25 with the setting off, and ~25 to ~18 with it on. DLSS went from
~24 to ~20 with the setting on. The in-game counter matches the log's frame
counter, so it shows rendered frames, not generated ones, and it flickers with
frame gen on. Whether interpolated frames actually reach the display hasn't
been checked. Either way, the rendered rate drops by 5 to 7 FPS, which adds
input latency.

### Upscaler summary

| Upscaler | Setting off | Setting on |
|---|---|---|
| FSR | ✅ 3.1.5, ~32 FPS | ✅ ~25 FPS |
| XeSS | ⚠️ 2.0.10 (library 2.0.1) initializes | ❌ **below 1 FPS** |
| DLSS Super Resolution | ❌ `SR=0` | ✅ via MetalFX, ~24 to ~30 FPS |
| DLSS Ray Reconstruction | ❌ | `RR=1`. Irrelevant: the game ships with RT off |
| Frame generation | lowers rendered FPS | lowers rendered FPS |

### Where the NVIDIA libraries load from

With the setting on, NGX finds the game's `nvngx_dlss.dll` in
`FactoryGame/Plugins/DLSS/Binaries/ThirdParty/Win64`, but loads its core from
the bottle:

```
Loading C:\windows\system32\nvngx.dll succeeded
NVSDK_NGX_D3D12_Init_with_ProjectID(...) -> (1 NVSDK_NGX_Result_Success)
```

So on beta 3 the `system32` copy that `reapply-gptk4.sh` makes is what lets
DLSS start. On beta 2 it did nothing.

## Other notes

- **XeSS is unusable.** It initializes cleanly, but selecting it dropped the
  game below 1 FPS. The cause hasn't been investigated, and this was only tested
  with Satisfactory.

- `Encountered 100 PSO creation hitches ... 0 of them were precached`: the
  shader cache was still warming after the swap, so expect stutter in early
  sessions.
- `Could not find user setting with id 't.MaxFPS'`: the game's saved FPS cap
  may not be applied. The performance runs used `t.MaxFPS 0` (uncapped) anyway.
- `-slnoswapchainprovider` (found in the Streamline plugin) works:
  `Skip registering IDXGISwapchainProvider, due to -slnoswapchainprovider command line`.
  It didn't help FPS.
