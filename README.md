# Satisfactory DX12 on CrossOver — GPTK 4 workflow

This procedure lets **Satisfactory (UE 5.6)** run with the **DirectX 12**
renderer under **CrossOver on Apple silicon**. It replaces the D3DMetal 3.0 that
CrossOver supplies with **D3DMetal 4.0b3** from Apple's Game Porting Toolkit 4
beta 3.

**Status: working** on D3DMetal 4.0b3. Test logs:
[beta 3](testing/beta3.md) (2026-11-04, macOS 27) and
[beta 2](testing/beta2.md) (2026-08-23, macOS 26).

> Each CrossOver update removes the swap. If DX12 starts to crash again, run
> `./reapply-gptk4.sh`. No other maintenance is necessary.

---

## The problem

With stock CrossOver, Satisfactory stops during renderer initialization. This
occurs before the game shows a window. `FactoryGame.log` shows this:

```
LogRHI: Using Default RHI: D3D12
LogRHI: RHI D3D12 with Feature Level SM6 is supported and will be used.
LogD3D12RHI: Bindless resources are supported
Assertion failed: GGlobalSamplerDescriptorHeapSize <= MaximumSamplerHeapSize
  [File: Engine\Source\Runtime\D3D12RHI\Private\D3D12Device.cpp] [Line: 372]

FactoryGameSteam-D3D12RHI-Win64-Shipping.dll!FD3D12Device::SetupAfterDeviceCreation()
FactoryGameSteam-D3D12RHI-Win64-Shipping.dll!FD3D12Adapter::InitializeDevices()
FactoryGameSteam-D3D12RHI-Win64-Shipping.dll!FD3D12DynamicRHI::Init()
```

**Cause.** UE 5.6 calculates the size of its global bindless *sampler*
descriptor heap from the values that the D3D12 device reports. Then it makes
sure that the size is not more than the device maximum. D3DMetal 3.0 reports
values that fail this check. Thus, the RHI does not start.

**These items are not the cause.** Do not examine them:

- Launch options. `-dx12` has no effect. D3D12 is already the *default* RHI for
  this game. That is why the game crashes with no changes.
- Missing VC++ redistributables. This is a different problem on some bottles. It
  gives a *different* symptom: a "Microsoft Visual C++ 2015–2022 Redistributable
  (x64) required" dialog.
- Graphics settings, save files, or a new installation of the game. The crash
  occurs before the game reads these items.

**Fix.** D3DMetal 4 reports correct values. Other users confirm this on the
[CodeWeavers Satisfactory forum](https://www.codeweavers.com/compatibility/crossover/forum/satisfactory?msg=351506).
The same assertion also occurred in
[StarRupture](https://www.codeweavers.com/compatibility/crossover/forum/starrupture?msg=342791).

No CrossOver release contains D3DMetal 4. CrossOver 26.3 (2026-07-21, the
current release) contains 3.0. Thus, you must do the swap manually.

---

## Requirements

| | Necessary |
|---|---|
| Hardware | Apple silicon |
| macOS | 15 Sequoia or newer |
| CrossOver | 26.x |
| Payload | GPTK 4.0 beta 3, extracted to `gptk4-b3/lib/` |
| Bottle graphics engine | **D3DMetal**, not DXVK or DXMT (`CX_GRAPHICS_BACKEND=d3dmetal`) |
| Permission | **App Management** for the terminal (refer to the subsequent section) |

### App Management permission

CrossOver.app is in `/Applications`. It has a Developer ID signature, Apple
notarized it, and the notarization ticket is stapled to it. Thus, macOS does
not let a usual process change it. Each write fails with
`Operation not permitted`. **`sudo` does not solve this problem.**

To give the permission:

1. Open **System Settings → Privacy & Security → App Management**.
2. Find the terminal that runs the script. If it is not in the list, add it
   with **+**.
3. Turn on the permission for the terminal.
4. **Quit the terminal and start it again.** A process that already runs does
   not get the new permission.

**Caution:** This permission lets all programs that you start from that terminal
change installed apps. You can remove the permission when you complete the
procedure. Give it again before the next swap.

---

## Applying it

```sh
./reapply-gptk4.sh
```

You can run the script many times safely. If D3DMetal 4.0b3 is already active,
the script stops immediately. If not, it does these steps:

1. It quits CrossOver.
2. It makes a backup of the stock libraries, with the current CrossOver version
   in the backup name.
3. It installs the payload.
4. It updates the bottle.

`./reapply-gptk4.sh --status` shows the installed version and makes no
changes. `--dry-run` shows the steps and makes no changes.

### What it does

The procedure comes from **Apple**. It is in the Read Me file in the GPTK 4
disk image. A local copy is at `gptk4-b3/Apple-ReadMe.rtf`.

```sh
cd /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk
mv external external.old; mv wine wine.old
ditto "<payload>/lib/" .
```

Apple's procedure then enables the experimental DLSS→MetalFX bridge with these
steps:

- Rename `wine/x86_64-unix/nvngx-on-metalfx.so` to `nvngx.so`.
- Rename `wine/x86_64-windows/nvngx-on-metalfx.dll` to `nvngx.dll`.
- Copy `nvngx.dll` and `nvapi64.dll` into the `windows/system32` folder of the
  bottle.

### Differences from stock CrossOver

CrossOver 26.3 contains `atidxx64`. GPTK 4 does **not** contain it, so Apple's
procedure removes it. GPTK 4 **adds** `d3d10`, which the CrossOver `apple_gptk`
folder does not have. Both differences are correct. CrossOver's `bin/wine` uses
only the path `apple_gptk/external/libd3dshared.dylib`. It does not use the
names of the individual DLLs. Thus, the loader can continue when a file is
missing.

### Steam launch options

```
-dx12 -NOTEXTURESTREAMING
```

`-dx12` is redundant but explicit. `-NOTEXTURESTREAMING` is the one that matters.

Set via Steam's UI (Properties → General), or directly in
`.../Steam/userdata/<id>/config/localconfig.vdf` under the `"526870"` block —
**with Steam closed**, or Steam overwrites the file on exit.

---

## Verifying

A good session writes these lines to the log:

```
LogRHI: Using Default RHI: D3D12
LogD3D12RHI:   Max supported Feature Level 12_2, shader model 6.7,
               binding tier 3, wave ops supported, atomic64 supported
LogFSR: Successfully initialized FSR Upscaling provider using version '3.1.5'
```

(Beta 2 reports shader model 6.6.)

The log must **not** contain a `GGlobalSamplerDescriptorHeapSize` line.

Log: `<bottle>/drive_c/users/crossover/AppData/Local/FactoryGame/Saved/Logs/FactoryGame.log`
Crashes: `.../Saved/Crashes/*/CrashContext.runtime-xml`. The `<ErrorMessage>`
field gives the name of the assertion.

After a swap, the first start of the game is slow. D3DMetal must make its
shader cache again. This is normal, and it occurs only one time.

---

## Known limitations

**Keep CrossOver's DLSS setting off and use FSR.** On beta 3, the setting
(`D3DM_ENABLE_METALFX=1`) makes DLSS available in the game through Apple's
MetalFX bridge. But the setting also makes D3DMetal report the GPU as NVIDIA.
Thus, the game loads NVIDIA's Streamline add-ons. The results in testing were:

- FSR is approximately 20% slower (~32 FPS decreases to ~25 FPS).
- When you disable Streamline, FSR does not become faster again.
- DLSS (~24 to ~30 FPS) is not faster than FSR with the setting off.

The game's frame generation decreases the number of frames that the game
renders. But FSR frame generation also adds interpolated frames. In one test,
the game rendered ~20 FPS and the Metal HUD showed ~40 FPS. Thus, motion is
smoother, but the input latency increases. Frame generation is optional. For
more data, refer to
[testing/beta3.md](testing/beta3.md#dlss-and-d3dm_enable_metalfx). On beta 2,
DLSS was not available, also with the setting on
([testing/beta2.md](testing/beta2.md#dlss)).

**Do not use XeSS.** It starts, but on beta 3 it decreased Satisfactory to less
than 1 FPS. We did not examine the cause. We tested it only with this game.

**The `nvngx` step is necessary only with the setting on.** On beta 3, DLSS
loads its core from `system32\nvngx.dll` in the bottle. `reapply-gptk4.sh`
copies this file into the bottle that `BOTTLE` identifies. If you play from a
different bottle, the script does not copy the file and shows a one-line
message. With the setting off, the bridge does nothing. It adds approximately
100 ms of failed Streamline initialization at startup. The script keeps this
step because it is Apple's documented procedure.

**Harmless messages.** This message shows at startup:
`[GPUBreadCrumb] Failed to OpenExistingHeapFromAddress, error: 80004001`
(`E_NOTIMPL`). It is not a problem. It comes from UE's crash breadcrumb
function, and D3DMetal does not implement that function.

**This is beta software.** GPTK 4.0 **beta 3** has no tests from CodeWeavers.
Other problems can occur in the bottle. The change to the app bundle also breaks
its code signature seal. macOS does not verify apps again after they start, and
CrossOver starts correctly. But it is a real change to a signed, notarized app.
Apple signed the two replacement libraries (`Authority=Software Signing`). Thus,
hardened-runtime library validation accepts them.

---

## Tuning

You can set D3DMetal environment variables for each bottle. Put them in
`cxbottle.conf`, in the `[EnvironmentVariables]` section. The full list is in
`gptk4-b3/Apple-ReadMe.rtf`.

| Variable | Default | Notes |
|---|---|---|
| `D3DM_SUPPORT_DXR` | **on** for M3+ | Translates DirectX Raytracing. If DX12 has problems, **set this to `0` first**. |
| `D3DM_ENABLE_METALFX` | off | CrossOver's DLSS setting. **Keep `0`.** On beta 3, `1` makes DLSS work through MetalFX, but FSR becomes ~20% slower. Refer to the limitations. |
| `D3DM_MTL4` | on, **macOS 27+ only** | Metal 4 backend. On macOS 26, D3DMetal always uses the Metal 3 backend, independent of the GPU. |
| `D3DM_MAX_FPS` | unset | Sets a frame rate limit. |
| `ROSETTA_ADVERTISE_AVX` | off | Tells translated code that AVX is available. |

D3DMetal writes to the system log, with the category `D3DMetal` and the prefix
`D3DM`. You can see these messages in Console.app, or in the terminal if you
start the game from a terminal.

---

## Rolling back

```sh
./revert-gptk4.sh
```

The script restores stock D3DMetal from `backup-stock-apple_gptk-CX<version>/`.
If that backup is not available, it uses `external.old` and `wine.old` in the
`apple_gptk` folder. After the rollback, DX12 crashes again. This is the
expected result.

A full new installation of CrossOver also removes all changes.

**If DX12 does not work at all:** add `-DX11` to the launch options. Forum users
confirm that version 1.2.2 starts with this option, but it has much stutter. Use
it only as a temporary solution.

---

## Files here

| Path | Purpose |
|---|---|
| `reapply-gptk4.sh` | Installs the swap. Safe to run many times. `--status`, `--dry-run`. |
| `revert-gptk4.sh` | Restores stock D3DMetal. |
| `testing/` | Test logs for each beta: machine, sessions, results |
| `gptk4-b3/lib/` | GPTK 4.0b3 payload, with its symlinks. You do not need to download it again. |
| `gptk4-b3/Apple-ReadMe.rtf` | Apple's instructions and list of environment variables |
| `backup-stock-apple_gptk-CX26.3/` | Original D3DMetal 3.0 from CrossOver 26.3 |
| `pre-fix-crash-logs/` | The original crashes, for reference |
| `localconfig.vdf.bak` | Steam configuration before the change to the launch options |
| `Game_Porting_Toolkit_4.0_beta_3.dmg` | Original download (the payload is already extracted) |

The files after `testing/` in the table stay on your computer, and git ignores
them.
Apple owns the payload and the DMG. The Steam configuration and the crash logs
contain account IDs. The local payload lets you do the swap again with one
command. Apple supplies GPTK only to users with a developer login, and Apple
removes old beta builds when a new build is available. **Do not delete
`gptk4-b3/`.**

---

## Upgrading the payload

When a newer GPTK is available (4.0 final, or a later beta), do these steps:

1. Mount the outer DMG.
2. Mount the *Evaluation environment for Windows games* DMG that is in the outer
   DMG.
3. Run `ditto "<mount>/redist/lib" gptk4-bN/lib`. `ditto` keeps the
   `x86_64-unix/*.so` symlinks that point to `libd3dshared.dylib`. `cp` without
   `-R` does not keep them.
4. In `reapply-gptk4.sh`, set `PAYLOAD` to the new folder and `WANT` to the new
   `CFBundleShortVersionString`.
5. Run `reapply-gptk4.sh`.
6. Record the machine, sessions and results in `testing/betaN.md`.
7. Change the **Status** line to point to the new file.

To see the version of a new payload before you install it, run this command:

```sh
plutil -extract CFBundleShortVersionString raw \
  "<mount>/redist/lib/external/D3DMetal.framework/Resources/Info.plist"
```

If a future CrossOver release contains D3DMetal 4, you do not need this
procedure. After each major update, read the
[changelog](https://www.codeweavers.com/crossover/changelog).
