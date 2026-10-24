<p align="center"><img src="app/logo.png" width="96" alt="VoxToRoblox logo"></p>

<h1 align="center">VoxToRoblox</h1>

<p align="center">
Take your animated <b>VoxEdit</b> characters and equipment to <b>Roblox</b> (and Blender) with all their animations and colours.<br>
Two simple Windows apps — no coding needed.
</p>

<p align="center"><b>English</b> · <a href="LEEME.md">Español</a></p>

## How to use it (video)

<p align="center">
<a href="https://youtu.be/C37fPBK0E6I"><img src="https://img.youtube.com/vi/C37fPBK0E6I/hqdefault.jpg" width="480" alt="Watch the VoxToRoblox tutorial on YouTube"></a><br>
▶ <a href="https://youtu.be/C37fPBK0E6I">Watch the tutorial on YouTube</a>
</p>

---

## What you need

- **Windows 10 or 11**
- **[Blender](https://www.blender.org/download/)** 4.4 or newer (free) — just install it, the apps find it by themselves
- **VoxEdit** and **Roblox Studio**

## Option A — straight from your VoxEdit projects

1. Copy your VoxEdit project folders into **`Projects`**.
2. Open **`Start VoxEdit Project to GLTF.exe`** (amber logo).
3. Untick in **Export to GLTF** anything you don't want, and press **Convert**.
4. Press **GLTF → Roblox** to go to the next step (Option B, from step 2).

## Option B — from GLTF files exported by VoxEdit

1. Put your `.gltf` / `.glb` files in **`Input`**.
2. Open **`Start VoxEdit to Roblox.exe`** (blue logo).
3. **Export**: untick anything you don't want to convert.
4. **Equipable**: tick the equipment pieces (helmet, chest, arms, legs, weapon, shield…). The ticked pieces of the same folder become **one kit** that shares a body.
5. Press **Convert**. Your files are in **`Output`**.

## Import into Roblox

1. In Roblox Studio: **Import 3D** → choose `Output\<Name>\<Name>_Roblox.fbx`.
2. Check that the animations show up and press **Import**: the character is placed in the scene and every animation goes to your inventory.
3. To edit the character in Blender, open `<Name>_Rig.blend` from the same folder.

## What's in the folder

| | |
|---|---|
| `Start VoxEdit Project to GLTF.exe` | VoxEdit projects → GLTF |
| `Start VoxEdit to Roblox.exe` | GLTF → Roblox (and Blender) |
| `Projects` | Your VoxEdit project folders |
| `Input` | GLTF files to convert |
| `Output` | The results for Roblox and Blender |
| `app` | The apps themselves — no need to touch it |

The `Projects`, `Input` and `Output` folders are created the first time you open the apps.

## If Windows shows a warning

The apps are not signed, so Windows may say *"Windows protected your PC"* the first time. Click **More info → Run anyway**.

## More information

Developers and advanced users: options, generated files, kits, materials and the command line are in the [technical notes](app/TECHNICAL.md).

## Thanks

To [**vengi**](https://github.com/vengi-voxel/vengi) by [Martin Gerhardy (@mgerhardy)](https://github.com/mgerhardy): its open-source voxel tools document how VoxEdit project files are laid out, which made the *VoxEdit Project → GLTF* app possible.

---

[MIT license](LICENSE) © Ashara Studios — made with love by [Ashara Studios](https://asharastudios.com). Not affiliated with The Sandbox or VoxEdit.
