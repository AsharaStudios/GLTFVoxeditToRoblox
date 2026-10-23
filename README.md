<p align="center"><img src="docs/logo.png" width="96" alt="VoxToRoblox logo"></p>

<h1 align="center">VoxToRoblox</h1>

<p align="center">
Convert animated <b>VoxEdit</b> models (glTF / GLB) into <b>Roblox</b>-ready FBX: a single-mesh rig with all its animations, a crisp texture atlas, PBR maps and equipment kits.<br>
A simple Windows app powered by Blender.
</p>

<p align="center"><b>English</b> · <a href="LEEME.md">Español</a></p>

## How to use it (video)

<p align="center">
<a href="https://youtu.be/C37fPBK0E6I"><img src="https://img.youtube.com/vi/C37fPBK0E6I/hqdefault.jpg" width="480" alt="Watch the VoxToRoblox tutorial on YouTube"></a><br>
▶ <a href="https://youtu.be/C37fPBK0E6I">Watch the tutorial on YouTube</a>
</p>

---

## Requirements

- **Windows 10 or 11.** The window uses PowerShell and Windows Forms, which come with Windows.
- **[Blender](https://www.blender.org/download/) 4.4 or newer** (free). Tested with Blender 5.2.
  It is found automatically in `C:\Program Files\Blender Foundation\` (the newest version is used).
  If you installed it in another folder, set its path on the first line of `VoxToRoblox.ps1`.
- **Nothing else for the conversion:** Blender already brings its own Python, numpy and the glTF/FBX add-ons. You do **not** need to install Python.
- **VoxEdit**, to export your models as `.gltf` / `.glb` (with animations).
- **Roblox Studio**, to import the result.
- Only for `PBRTuner.lua` in published games: the Mesh/Image APIs enabled (*Game Settings → Security*) and a verified owner account.

## Quick start

1. Put your `.gltf` / `.glb` files (with their `.bin` and textures, or in subfolders) inside `Input\`.
2. Double-click **`Start VoxEdit to Roblox.exe`**: a window opens with the list of files in `Input\`.
3. Choose the options if you want (height in studs, texture size, PBR maps, sharp pixels, skip already converted, open Output when done).
4. Tick **Equipable** for VoxEdit equipment (helmet, chest, arms, legs, weapon, shield…): those files are converted with the [kit algorithm](#kits-body--equipment--weapons). Files whose name contains *Helmet, Shield, Weapon, Legs, Arms* or *Chest* come ticked already; you can change it.
5. Press **Convert**. Each file shows a preview, its own progress bar and status; the bar at the bottom is the total.
   Results go to `Output\<Name>\`. If a file fails, **Open log** shows the details (`log.txt`).

The window also has buttons to open the **Input** and **Output** folders, **Refresh** the list, **Cancel** a conversion and **Clear Output** (moves everything in `Output` to the Recycle Bin, after asking).
**Language** (top right): English or Spanish. It starts in your Windows language and remembers your choice.

## What you get

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

## Import into Roblox in one go

1. In Studio: **Import 3D** → choose `<Name>_Roblox.fbx` (unit *Stud*).
2. In the importer, check that the animations show up in the tree and click **Import**. The rig is placed in the scene and every animation is uploaded to your inventory.
3. To use them: *Animation Editor → Import from Roblox*, or copy the ID from your inventory.

> The T-pose animation is not included because it is identical to the rest pose.

### Material (the mesh's SurfaceAppearance)

| Property | Map |
|---|---|
| `ColorMap` | `_Atlas` |
| `NormalMap` | `_Normal` |
| `RoughnessMap` | `_Roughness` |
| `MetalnessMap` | `_Metalness` |
| `EmissiveMaskContent` | `_Emissive` (+ `EmissiveStrength` / `EmissiveTint`) |
| `ResampleMode` | `Pixelated` |

Roblox needs each map in its own field (it does not accept a single "packed" PNG) and downsizes any image to 1024×1024 when uploading it.

## Kits (body + equipment + weapons)

In the window, tick **Equipable** on every piece of the kit and press **Convert**. All the ticked files in the same folder are converted together as **one kit**: one shared body, the same scale and the position of every piece.

- Files directly in `Input\`: the kit is named after the word their names share (`Knight_Helmet`, `Knight_Legs` → **Knight**).
- Files in a subfolder (`Input\Pirate\…`): the kit is named after the folder, so you can convert several kits at once.

Put **all** the pieces of a kit together; a kit needs at least one piece exported on the VoxEdit avatar (with the body).
Output goes to `Output\<Kit>_Kit\`:

| File | What it is |
|---|---|
| `<Kit>_Body.fbx` | Rigid rig: one mesh per bone (Motor6D in Roblox) + `HumanoidRootPart` |
| `<Set>.fbx` | One per equipment set, one mesh per bone, in the body's rest pose |
| `<Weapon>.fbx` | Loose weapons: one `Handle` mesh |
| `<Kit>_Animations.json` | Body animations for Studio |
| `<Kit>_Offsets.json` | Position of each piece relative to its bone |
| `<Kit>_Kit.blend` | Everything together for review |
| `<Kit>_report.txt` | Summary |

## Raise / lower the strength in Roblox (`PBRTuner.lua`)

1. Create a **LocalScript** in `StarterPlayerScripts` called `PBRTuner` and paste `PBRTuner.lua`.
2. Give the MeshPart the tag `PBRTuner` and whichever attributes you want (numbers):
   `PBR_Normal 1` · `PBR_Roughness 1` · `PBR_RoughnessAdd 0` · `PBR_Metalness 1` · `PBR_MetalnessAdd 0` · `PBR_Emissive 4`
3. Press **Play** and change the attributes (Client view): it updates instantly. When you like it, set the same values in Edit mode to save them.

## What it does

- Turns the loose VoxEdit pieces into a single mesh with a skeleton.
- Packs all textures into one crisp atlas (no smoothing): each VoxEdit texture is cropped to the area its UVs really use and identical crops are shared, so the atlas is small and every voxel gets more pixels. The atlas sits on a power-of-2 canvas so Roblox does not rescale (and blur) it.
- Optional **Sharp pixels** (`--palette`): cuts every face into flat-colour rectangles so the pixel art stays sharp at any distance (Roblox always smooths mesh textures). Costs about 4x more triangles, so it is off by default.
- Scales to 5.5 studs, feet at the origin, facing Roblox's front. Rest pose = the model's T-pose (detects "T POSE", "T", "TPose"…).
- Merges bones that barely move (by default, if the error is under half a voxel).
- Removes redundant keyframes when exporting.
- The normal map is computed from the colour: dark sinks in and light stands out, with a bevel where colours change.
- It is a custom rig, not R15.

## Command line

Converter:

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python voxedit_to_roblox.py -- FILES [options]
```

Kit:

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python voxedit_kit_to_roblox.py -- GLTFS... [--name Kit] [--out FOLDER]
```

From the command line the results go to `Roblox\<Name>\` next to the glTF (or to `--out`).

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
| `--emis-relative` | | Emissive mask with VoxEdit's intensity (default: everything that glows in pure white; set the brightness with `EmissiveStrength`) |
| `--normal-strength` | `1.0` | Normal map relief strength |
| `--bevel` | `0.25` | Bevel width between voxels of different colour (fraction of a voxel) |
| `--voxel-bevel` | `0` | Bevel on **every** voxel edge, "block" look (try `0.4`) |
| `--roughness` | `0.6` | Base roughness when the model has none (VoxEdit almost never has it) |
| `--rough-var` | `0.35` | Roughness variation: dark is more matte, light is more polished |
| `--metal` | `0` | Base metalness when the model has none |
| `--log-file FILE` | | Write the full log to a file instead of the console |
| `--progress-file`, `--thumb-list` | | Used internally by the window |

## The launcher

`Start VoxEdit to Roblox.exe` is only a small launcher with the logo: it opens `VoxToRoblox.ps1`, which must stay in the same folder. Its source is [`Launcher.cs`](Launcher.cs); to rebuild it (for example after changing `VoxToRoblox.ico`):

```bat
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /win32icon:VoxToRoblox.ico /out:"Start VoxEdit to Roblox.exe" Launcher.cs
```

It is not signed, so Windows may warn that it comes from an unknown publisher when you download it: **More info → Run anyway**, or right-click `VoxToRoblox.ps1` → **Run with PowerShell**.

## License

[MIT](LICENSE) © Ashara Studios — made with love by [Ashara Studios](https://asharastudios.com).
