# VoxToRoblox — technical notes

**English** · [Español](TECNICO.md) · [Back to the README](../README.md)

Everything technical lives in this `app\` folder; the launchers in the project folder open the two windows from here.

## Files it creates

Per model, in `Output\<Name>\`:

| File | What it is |
|---|---|
| `<Name>_Roblox.fbx` | Character + **all** animations in one file — the one to import into Roblox |
| `<Name>_Rig.fbx` | Character with skeleton, no animations |
| `Animations\<Name>_*.fbx` | One animation per file (*Animation Editor → Import from FBX Animation*) |
| `<Name>_Atlas.png` | Single colour texture |
| `<Name>_Normal.png` | Relief (normal map, OpenGL format as used by Roblox) |
| `<Name>_Roughness.png` | Roughness (black = shiny, white = matte) |
| `<Name>_Metalness.png` | Metalness (black = not metal) |
| `<Name>_Emissive.png` | Glow mask, white = glows (only if the model has emissive voxels) |
| `<Name>_Rig.blend` | Rig with all animations, ready to edit in Blender |
| `<Name>_report.txt` | Triangles, bones and the error of each animation against the original |

The T-pose animation is not included in the FBX files because it is identical to the rest pose.

## Material in Roblox (the mesh's SurfaceAppearance)

| Property | Map |
|---|---|
| `ColorMap` | `_Atlas` |
| `NormalMap` | `_Normal` |
| `RoughnessMap` | `_Roughness` |
| `MetalnessMap` | `_Metalness` |
| `EmissiveMaskContent` | `_Emissive` (+ `EmissiveStrength` / `EmissiveTint`) |

Roblox needs each map in its own field (it does not accept a single "packed" PNG) and downsizes any image to 1024×1024 when uploading it.
Everything that glows comes out pure white in `_Emissive`; set how bright it is with `EmissiveStrength` (or use `--emis-relative` to keep VoxEdit's own intensity).

## Kits (body + equipment + weapons)

Files ticked as **Equipable** in the same folder are converted together as **one kit**: one shared body, the same scale and the position of every piece.

- Files directly in `Input\`: the kit is named after the word their names share (`Knight_Helmet`, `Knight_Legs` → **Knight**).
- Files in a subfolder (`Input\Pirate\…`): the kit is named after the folder, so several kits can be converted at once.
- A kit needs at least one piece exported on the VoxEdit avatar (with the body). The equipment shape is taken from the *Idle* pose (in VoxEdit's T-pose the equipment collapses) and carried to the T-pose bone by bone.

Output goes to `Output\<Kit>_Kit\`:

| File | What it is |
|---|---|
| `<Kit>_Body.fbx` | Rigid rig: one mesh per bone (Motor6D in Roblox) + `HumanoidRootPart` |
| `<Set>.fbx` | One per equipment set, one mesh per bone, in the body's rest pose |
| `<Weapon>.fbx` | Loose weapons: one `Handle` mesh |
| `<Kit>_Animations.json` | Body animations for Studio (per frame, per bone, in Roblox coordinates) |
| `<Kit>_Offsets.json` | Position of each piece relative to its bone |
| `<Kit>_Kit.blend` | Everything together for review |
| `<Kit>_report.txt` | Summary |

## Raise / lower the strength in Roblox (`PBRTuner.lua`)

1. Create a **LocalScript** in `StarterPlayerScripts` called `PBRTuner` and paste the content of `app\PBRTuner.lua`.
2. Give the MeshPart the tag `PBRTuner` and whichever attributes you want (numbers):
   `PBR_Normal 1` · `PBR_Roughness 1` · `PBR_RoughnessAdd 0` · `PBR_Metalness 1` · `PBR_MetalnessAdd 0` · `PBR_Emissive 4`
3. Press **Play** and change the attributes (Client view): it updates instantly. When you like it, set the same values in Edit mode to save them.

It uses EditableImage: in published games the Mesh/Image APIs must be enabled (*Game Settings → Security*) and the owner account must be verified.

## What the converter does

- Turns the loose VoxEdit pieces into a single mesh with a skeleton (a custom rig, not R15).
- Packs all textures into one crisp atlas (no smoothing): each VoxEdit texture is cropped to the area its UVs really use and identical crops are shared, so the atlas is small and every voxel gets more pixels. The atlas sits on a power-of-2 canvas so Roblox does not rescale (and blur) it.
- Optional **Sharp pixels** (`--palette`): cuts every face into flat-colour rectangles so the pixel art stays sharp at any distance (Roblox always smooths mesh textures). Costs about 4x more triangles, so it is off by default.
- Scales to 5.5 studs, feet at the origin, facing Roblox's front. Rest pose = the model's T-pose (detects "T POSE", "T", "TPose"…).
- Merges bones that barely move (by default, if the error is under half a voxel) and removes redundant keyframes.
- The normal map is computed from the colour: dark sinks in and light stands out, with a bevel where colours change.

## VoxEdit projects → GLTF

`voxedit_project_to_gltf.py` (with the readers in `voxedit_formats.py`) builds the same GLTF that VoxEdit exports: one node pair `<id>-Global` / `<id>-Local` per piece, the mesh VoxEdit stores inside each `.vxm`, its palette texture and glow, and every animation sampled per frame at 24 fps. It was compared with VoxEdit's own GLTF of the same project: largest vertex difference 0.0005 voxels over every piece, frame and animation.

- Reads VXM 12, VXR 9 and VXA 2–4 files. If a model used by the rig is missing, that project fails with a clear message and the others still convert.
- The GLTF is named after the project folder (a folder with several rigs: `<folder> - <rig>`; a rig loose in `Projects\`: its own name).
- The window shows VoxEdit's own preview (`<rig>.vxr.png`) for each project.

## Command line

Converter (GLTF → Roblox):

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python app\voxedit_to_roblox.py -- FILES [options]
```

Kit:

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python app\voxedit_kit_to_roblox.py -- GLTFS... [--name Kit] [--out FOLDER]
```

VoxEdit project → GLTF (with Blender's own Python, which has numpy):

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\5.2\python\bin\python.exe" app\voxedit_project_to_gltf.py PROJECT.vxr OUT.gltf
```

From the command line the Roblox results go to `Roblox\<Name>\` next to the GLTF (or to `--out`).

| Option | Default | What it does |
|---|---|---|
| `--height` | `5.5` | Final height in studs |
| `--tex` | `1024` | Final texture size |
| `--rest "Name"` | T-pose | Animation used as the rest pose |
| `--max-error` | `0.5` | Allowed error when merging bones (in voxels); higher = fewer bones |
| `--max-bones` | `0` | Hard bone limit (0 = no limit). Forcing it deforms hands/hair |
| `--no-reduce` | | Do not merge bones |
| `--simplify` | `1.0` | Keyframe reduction (0 = one key per frame) |
| `--anim-skeleton-only` | | Animation FBX files without the mesh (lighter; the rest pose may be read wrong) |
| `--no-rotate` | | Do not rotate 180° (if a model ends up facing backwards) |
| `--no-blend` | | Do not save the `.blend` |
| `--no-combined` | | Do not build `<Name>_Roblox.fbx` |
| `--out FOLDER` | | A different output folder |
| `--maps-only` | | Atlas + PBR maps only, with the **same UVs** (does not touch the FBX, `.blend` or animations) |
| `--no-pbr` | | Do not generate the PBR maps |
| `--palette` | | Flat-colour rectangles instead of textured faces: sharp pixel art, ~4x triangles (warns above Roblox's 20 000 per MeshPart) |
| `--emis-relative` | | Emissive mask with VoxEdit's intensity (default: everything that glows in pure white) |
| `--normal-strength` | `1.0` | Normal map relief strength |
| `--bevel` | `0.25` | Bevel width between voxels of different colour (fraction of a voxel) |
| `--voxel-bevel` | `0` | Bevel on **every** voxel edge, "block" look (try `0.4`) |
| `--roughness` | `0.6` | Base roughness when the model has none (VoxEdit almost never has it) |
| `--rough-var` | `0.35` | Roughness variation: dark is more matte, light is more polished |
| `--metal` | `0` | Base metalness when the model has none |
| `--log-file FILE` | | Write the full log to a file instead of the console |
| `--progress-file`, `--thumb-list` | | Used internally by the windows |

## Settings, logs and cache

- **Blender path:** found automatically in `C:\Program Files\Blender Foundation\` (the newest version). Otherwise set it on the first line of `VoxToRoblox.ps1` and `ProjectToGltf.ps1`.
- **Logs:** `app\log.txt` (GLTF → Roblox) and `app\log_projects.txt` (projects → GLTF); the **Open log** buttons open them.
- **Previews and language:** kept in `%LOCALAPPDATA%\VoxToRoblox\` (`thumbs\` and `settings.txt`).
- The Equipable column comes ticked when the file name contains one of the words in `$EquipWords` (`VoxToRoblox.ps1`).

## The launchers

`Start VoxEdit to Roblox.exe` and `Start VoxEdit Project to GLTF.exe` only open `app\VoxToRoblox.ps1` and `app\ProjectToGltf.ps1` without a console (keep `app\` next to them). Their source is [`Launcher.cs`](Launcher.cs); to rebuild them from the project folder (for example after changing the `.ico` files):

```bat
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /win32icon:app\VoxToRoblox.ico /out:"Start VoxEdit to Roblox.exe" app\Launcher.cs
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /define:PROJECT_TO_GLTF /win32icon:app\VoxEditToGltf.ico /out:"Start VoxEdit Project to GLTF.exe" app\Launcher.cs
```

They are not signed. If Windows blocks them, the windows can also be opened by right-clicking `VoxToRoblox.ps1` / `ProjectToGltf.ps1` → **Run with PowerShell**. The `.ps1` files must stay saved as UTF-8 with BOM (for the Spanish texts in Windows PowerShell 5.1).

## Credits

The layout of the VoxEdit project files follows the open-source readers of [vengi](https://github.com/vengi-voxel/vengi) (MIT, © [Martin Gerhardy, @mgerhardy](https://github.com/mgerhardy)); the conversion itself was written for VoxToRoblox and checked against VoxEdit's own exports. VoxToRoblox is not affiliated with The Sandbox or VoxEdit.
