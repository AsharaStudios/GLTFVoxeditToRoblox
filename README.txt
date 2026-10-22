VoxToRoblox 1.4 - from animated VoxEdit glTF to Roblox
======================================================
(Spanish version: LEEME.txt)

REQUIREMENTS (what must be installed)
  - Windows 10 or 11. The window uses PowerShell and Windows Forms, which come with Windows.
  - Blender 4.4 or newer (free: https://www.blender.org/download/). Tested with Blender 5.2.
    It is found automatically in C:\Program Files\Blender Foundation\ (the newest version is used).
    If you installed it in another folder, set its path on the first line of VoxToRoblox.ps1.
  - Nothing else for the conversion: Blender already brings its own Python, numpy and the glTF/FBX add-ons.
    You do NOT need to install Python separately.
  - VoxEdit, to export your models as .gltf / .glb (with animations).
  - Roblox Studio, to import the result.
  - Only for PBRTuner.lua in published games: the Mesh/Image APIs enabled
    (Game Settings > Security) and a verified owner account.

QUICK START (Input / Output folders)
  1. Put your .gltf / .glb files (with their .bin and textures, or in subfolders) inside Input\.
  2. Double-click "Start VoxEdit to Roblox.exe": a window opens with the list of files in Input\.
  3. Choose the options if you want (height in studs, texture size, PBR maps, skip already converted,
     open Output when done) and press Convert.
  4. Tick "Equipable" for VoxEdit equipment (helmet, chest, arms, legs, weapon, shield...): those files are
     converted with the kit algorithm (see KIT below). Files whose name has Helmet, Shield, Weapon, Legs, Arms
     or Chest come ticked already; you can change it. Each file shows a small preview (made by Blender the first
     time, then kept in %LOCALAPPDATA%\VoxToRoblox\thumbs).
  5. Each file shows its own progress bar and status; the bar at the bottom is the total.
     Results go to Output\<Name>\. If a file fails, "Open log" shows the details (log.txt).
  The window also has buttons to open the Input and Output folders, Refresh the list, Cancel a conversion
  and "Clear Output", which moves everything in Output to the Recycle Bin (it asks first).
  Language (top right): English or Spanish. The window starts in your Windows language and remembers your choice.

WHAT YOU GET (per model, in Output\<Name>\)
  <Name>_Roblox.fbx         character + ALL animations in one file (the one to import into Roblox)
  <Name>_Rig.fbx            character with skeleton, no animations
  Animations\<Name>_*.fbx   one animation per file (Animation Editor > Import from FBX Animation)
  <Name>_Atlas.png          single texture (colour)
  <Name>_Normal.png         relief (normal map, OpenGL format as used by Roblox)
  <Name>_Roughness.png      roughness (black = shiny, white = matte)
  <Name>_Metalness.png      metalness (black = not metal)
  <Name>_Emissive.png       glow mask, white = glows (only if the VoxEdit model has emissive voxels)
  <Name>_Rig.blend          rig with ALL animations, ready to edit in Blender
  <Name>_report.txt         triangles, bones and the error of each animation against the original

IMPORT INTO ROBLOX IN ONE GO
  1. In Studio: Import 3D > choose <Name>_Roblox.fbx (unit "Stud").
  2. In the importer window check that the animations show up in the tree and click Import.
     The rig is placed in the scene and every animation is uploaded to your inventory.
  3. To use them: Animation Editor > Import from Roblox, or copy the ID from your inventory.
  (The T-pose animation is not included because it is identical to the rest pose.)

MAPS ONLY (without touching what you already have)
  Run the converter from the command line with --maps-only (see OPTIONS): it rebuilds the atlas and the 4 maps
  with the SAME UVs, without rewriting the FBX files, the .blend or the animations
  (useful for models already imported and edited).

KIT (body + equipment sets + weapons)
  In the window, tick "Equipable" on every piece of the kit and press Convert. All the ticked files in the same
  folder are converted together as ONE kit (one shared body, same scale, the position of every piece):
    - files directly in Input\: the kit is named after the word their names share (Knight_Helmet, Knight_Legs -> Knight)
    - files in a subfolder (Input\Pirate\...): the kit is named after the folder, so you can convert several kits at once
  Put ALL the pieces of a kit together; a kit needs at least one piece exported on the VoxEdit avatar (with the body).
  From the command line:
    "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python voxedit_kit_to_roblox.py -- GLTFS... [--name Kit] [--out FOLDER]
  Output goes to Output\<Kit>_Kit\ (command line: Roblox\<Kit>_Kit\ next to the first glTF, or --out):
     <Kit>_Body.fbx           rigid rig: one mesh per bone (Motor6D in Roblox) + HumanoidRootPart
     <Set>.fbx                one per equipment set, one mesh per bone, in the body's rest pose
     <Weapon>.fbx             loose weapons: one "Handle" mesh
     <Kit>_Animations.json    body animations for Studio
     <Kit>_Offsets.json       position of each piece relative to its bone
     <Kit>_Kit.blend          everything together for review
     <Kit>_report.txt

MATERIAL IN ROBLOX (the mesh's SurfaceAppearance)
  ColorMap = _Atlas   NormalMap = _Normal   RoughnessMap = _Roughness   MetalnessMap = _Metalness
  EmissiveMaskContent = _Emissive (+ EmissiveStrength / EmissiveTint)   ResampleMode = Pixelated
  Roblox needs each map in its own field: it does not accept a single "packed" PNG.
  Roblox downsizes any image to 1024x1024 when uploading it.

RAISE / LOWER THE STRENGTH IN ROBLOX (PBRTuner.lua)
  1. Create a LocalScript in StarterPlayerScripts called PBRTuner and paste PBRTuner.lua.
  2. Give the MeshPart the tag "PBRTuner" and whichever attributes you want (numbers):
       PBR_Normal 1   PBR_Roughness 1   PBR_RoughnessAdd 0   PBR_Metalness 1   PBR_MetalnessAdd 0   PBR_Emissive 4
  3. Press Play and change the attributes (Client view): it updates instantly.
     When you like it, set the same values in Edit mode to save them.

WHAT IT DOES
  - Turns the loose VoxEdit pieces into a single mesh with a skeleton.
  - Packs all textures into one crisp atlas (no smoothing).
  - Scales to 5.5 studs, feet at the origin, facing Roblox's front. Rest pose = the model's T-pose (detects "T POSE", "T", "TPose"...).
  - Merges bones that barely move (by default, if the error is under half a voxel).
  - Removes redundant keyframes when exporting.

OPTIONS (from the command line)
  "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python voxedit_to_roblox.py -- FILES [options]
  --height 5.5            final height in studs
  --tex 1024              final texture size
  --rest "Name"           force the animation used as the rest pose
  --max-error 0.5         allowed error when merging bones (in voxels); higher = fewer bones
  --max-bones 0           hard bone limit (0 = no limit). Careful: forcing it deforms hands/hair
  --no-reduce             do not merge bones
  --simplify 1.0          keyframe reduction (0 = one key per frame)
  --anim-skeleton-only    animation FBX files without the mesh (lighter; the rest pose may be read wrong)
  --no-rotate             do not rotate 180 degrees (if a model ends up facing backwards)
  --no-blend              do not save the .blend
  --no-combined           do not build <Name>_Roblox.fbx
  --out FOLDER            a different output folder
  --maps-only             atlas + PBR maps only (does not touch the FBX, .blend or animations)
  --no-pbr                do not generate the PBR maps
  --emis-relative         emissive mask with VoxEdit's intensity (default: everything that glows in pure white)
  --normal-strength 1.0   normal map relief strength
  --bevel 0.25            bevel width between voxels of different colour (fraction of a voxel)
  --voxel-bevel 0         bevel on EVERY voxel edge, "block" look (try 0.4)
  --roughness 0.6         base roughness when the model has none (VoxEdit almost never has it)
  --rough-var 0.35        roughness variation: dark is more matte, light is more polished
  --metal 0               base metalness when the model has none
  --log-file FILE         write the full log to FILE instead of the console
  --progress-file FILE    progress lines for the Convert window (used internally)
  --thumb-list FILE       only render previews: one "source.gltf<TAB>preview.png" per line (used internally)

NOTES
  - "Start VoxEdit to Roblox.exe" is only a small launcher with the logo: it opens VoxToRoblox.ps1 (it must stay
    in the same folder). Its source is Launcher.cs; to rebuild it after changing the logo (VoxToRoblox.ico):
      C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /win32icon:VoxToRoblox.ico /out:"Start VoxEdit to Roblox.exe" Launcher.cs
    If you download it from the internet, Windows may warn that it is from an unknown publisher (it is not signed):
    "More info" > "Run anyway", or right-click VoxToRoblox.ps1 > "Run with PowerShell".
  - Requires Blender 4.4 or newer. If Blender is not in C:\Program Files\Blender Foundation\,
    set its path on the first line of VoxToRoblox.ps1.
  - VoxEdit's emissive glow comes out in <Name>_Emissive.png (put it in EmissiveMaskContent).
    Everything that glows is pure white (100%); set how bright it is with EmissiveStrength in Roblox.
    Use --emis-relative to keep VoxEdit's own intensity per voxel instead.
  - The normal map is computed from the colour: dark sinks in and light stands out,
    with a bevel where colours change. With an upscaled atlas (x4 or more) the bevel shows per voxel.
  - It is a custom rig, not R15.
