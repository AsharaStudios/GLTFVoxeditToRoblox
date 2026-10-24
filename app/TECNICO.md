# VoxToRoblox — notas técnicas

[English](TECHNICAL.md) · **Español** · [Volver al LEEME](../LEEME.md)

Todo lo técnico está en esta carpeta `app\`; los lanzadores de la carpeta del proyecto abren las dos ventanas desde aquí.

## Archivos que genera

Por modelo, en `Output\<Nombre>\`:

| Archivo | Qué es |
|---|---|
| `<Nombre>_Roblox.fbx` | Personaje + **todas** las animaciones en un solo archivo — el que se importa en Roblox |
| `<Nombre>_Rig.fbx` | Personaje con esqueleto, sin animaciones |
| `Animations\<Nombre>_*.fbx` | Una animación por archivo (*Animation Editor → Import from FBX Animation*) |
| `<Nombre>_Atlas.png` | Textura única (color) |
| `<Nombre>_Normal.png` | Relieve (normal map, formato OpenGL que usa Roblox) |
| `<Nombre>_Roughness.png` | Rugosidad (negro = brillante, blanco = mate) |
| `<Nombre>_Metalness.png` | Metalicidad (negro = no metal) |
| `<Nombre>_Emissive.png` | Máscara de brillo, blanco = brilla (solo si el modelo tiene vóxeles emisivos) |
| `<Nombre>_Rig.blend` | Rig con todas las animaciones, listo para editar en Blender |
| `<Nombre>_report.txt` | Triángulos, huesos y error de cada animación frente al original |

La animación de T-pose no se incluye en los FBX porque es idéntica a la pose de reposo.

## Material en Roblox (SurfaceAppearance de la malla)

| Propiedad | Mapa |
|---|---|
| `ColorMap` | `_Atlas` |
| `NormalMap` | `_Normal` |
| `RoughnessMap` | `_Roughness` |
| `MetalnessMap` | `_Metalness` |
| `EmissiveMaskContent` | `_Emissive` (+ `EmissiveStrength` / `EmissiveTint`) |

Roblox necesita cada mapa en su propio campo (no admite un solo PNG "empaquetado") y reduce cualquier imagen a 1024×1024 al subirla.
Todo lo que brilla sale en blanco puro en `_Emissive`; qué tan fuerte brilla se ajusta con `EmissiveStrength` (o usa `--emis-relative` para conservar la intensidad de VoxEdit).

## Kits (cuerpo + equipo + armas)

Los archivos marcados como **Equipable** de la misma carpeta se convierten juntos como **un kit**: un solo cuerpo, la misma escala y la posición de cada pieza.

- Archivos sueltos en `Input\`: el kit toma el nombre de la palabra que comparten (`Knight_Helmet`, `Knight_Legs` → **Knight**).
- Archivos en una subcarpeta (`Input\Pirate\…`): el kit se llama como la carpeta; así se pueden convertir varios kits a la vez.
- Un kit necesita al menos una pieza exportada sobre el avatar de VoxEdit (con el cuerpo). La forma del equipo se toma de la pose *Idle* (en la T-pose de VoxEdit el equipo se desarma) y se lleva a la T-pose hueso por hueso.

Sale en `Output\<Kit>_Kit\`:

| Archivo | Qué es |
|---|---|
| `<Kit>_Body.fbx` | Rig rígido: una malla por hueso (Motor6D en Roblox) + `HumanoidRootPart` |
| `<Set>.fbx` | Uno por set de equipo, una malla por hueso, en la pose de reposo del cuerpo |
| `<Arma>.fbx` | Armas sueltas: una malla `Handle` |
| `<Kit>_Animations.json` | Animaciones del cuerpo para Studio (por frame, por hueso, en coordenadas de Roblox) |
| `<Kit>_Offsets.json` | Posición de cada pieza relativa a su hueso |
| `<Kit>_Kit.blend` | Todo junto para revisar |
| `<Kit>_report.txt` | Resumen |

## Subir / bajar la intensidad en Roblox (`PBRTuner.lua`)

1. Crea un **LocalScript** en `StarterPlayerScripts` llamado `PBRTuner` y pega el contenido de `app\PBRTuner.lua`.
2. A la MeshPart ponle el tag `PBRTuner` y los atributos que quieras (números):
   `PBR_Normal 1` · `PBR_Roughness 1` · `PBR_RoughnessAdd 0` · `PBR_Metalness 1` · `PBR_MetalnessAdd 0` · `PBR_Emissive 4`
3. Dale **Play** y cambia los atributos (vista Cliente): se actualiza al instante. Cuando te guste, pon los mismos valores en modo edición para guardarlos.

Usa EditableImage: en juegos publicados hay que activar las APIs de Mesh/Image (*Configuración del juego → Seguridad*) y la cuenta dueña debe estar verificada.

## Qué hace el conversor

- Convierte las piezas sueltas de VoxEdit en una sola malla con esqueleto (un rig propio, no R15).
- Junta todas las texturas en un atlas nítido (sin suavizado): cada textura de VoxEdit se recorta al área que realmente usan sus UV y los recortes idénticos se comparten, así el atlas es pequeño y cada vóxel recibe más píxeles. El atlas va en un lienzo potencia de 2 para que Roblox no lo reescale (ni lo desenfoque).
- Opción **Píxeles nítidos** (`--palette`): corta cada cara en rectángulos de un solo color para que el pixel art se vea nítido a cualquier distancia (Roblox siempre suaviza las texturas de las mallas). Cuesta unas 4 veces más triángulos, por eso viene apagada.
- Escala a 5.5 studs, pies en el origen, mirando al frente de Roblox. Reposo = la T-pose del modelo (detecta "T POSE", "T", "TPose"…).
- Fusiona huesos que casi no se mueven (por defecto, si el error es menor a medio vóxel) y reduce keyframes redundantes.
- El normal map se calcula del color: lo oscuro queda hundido y lo claro en relieve, con un bisel donde cambian los colores.

## Proyectos de VoxEdit → GLTF

`voxedit_project_to_gltf.py` (con los lectores de `voxedit_formats.py`) genera el mismo GLTF que exporta VoxEdit: un par de nodos `<id>-Global` / `<id>-Local` por pieza, la malla que VoxEdit guarda dentro de cada `.vxm`, su textura de paleta y su brillo, y cada animación muestreada por frame a 24 fps. Se comparó con el GLTF que exporta VoxEdit del mismo proyecto: diferencia máxima de 0,0005 vóxeles en cada vértice, frame y animación.

- Lee archivos VXM 12, VXR 9 y VXA 2–4. Si falta un modelo que usa el rig, ese proyecto falla con un mensaje claro y los demás se convierten igual.
- El GLTF toma el nombre de la carpeta del proyecto (una carpeta con varios rigs: `<carpeta> - <rig>`; un rig suelto en `Projects\`: su propio nombre).
- La ventana muestra la vista previa que guarda VoxEdit (`<rig>.vxr.png`) de cada proyecto.

## Desde consola

Conversor (GLTF → Roblox):

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python app\voxedit_to_roblox.py -- ARCHIVOS [opciones]
```

Kit:

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python app\voxedit_kit_to_roblox.py -- GLTFS... [--name Kit] [--out CARPETA]
```

Proyecto de VoxEdit → GLTF (con el Python que trae Blender, que incluye numpy):

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\5.2\python\bin\python.exe" app\voxedit_project_to_gltf.py PROYECTO.vxr SALIDA.gltf
```

Desde consola el resultado para Roblox queda en `Roblox\<Nombre>\` junto al GLTF (o en `--out`).

| Opción | Por defecto | Qué hace |
|---|---|---|
| `--height` | `5.5` | Altura final en studs |
| `--tex` | `1024` | Tamaño de la textura final |
| `--rest "Nombre"` | T-pose | Animación usada como pose de reposo |
| `--max-error` | `0.5` | Error permitido al fusionar huesos (en vóxeles); más alto = menos huesos |
| `--max-bones` | `0` | Límite duro de huesos (0 = sin límite). Forzarlo deforma manos/pelo |
| `--no-reduce` | | No fusionar huesos |
| `--simplify` | `1.0` | Reducción de keyframes (0 = un key por frame) |
| `--anim-skeleton-only` | | FBX de animación sin malla (más livianos; la pose de reposo puede leerse mal) |
| `--no-rotate` | | No girar 180° (si un modelo queda de espaldas) |
| `--no-blend` | | No guardar el `.blend` |
| `--no-combined` | | No generar `<Nombre>_Roblox.fbx` |
| `--out CARPETA` | | Carpeta de salida distinta |
| `--maps-only` | | Solo atlas + mapas PBR, con los **mismos UV** (no toca los FBX, el `.blend` ni las animaciones) |
| `--no-pbr` | | No generar los mapas PBR |
| `--palette` | | Rectángulos de color plano en vez de caras con textura: pixel art nítido, ~4x triángulos (avisa si pasa de los 20 000 por MeshPart de Roblox) |
| `--emis-relative` | | Máscara emisiva con la intensidad de VoxEdit (por defecto: todo lo que brilla en blanco puro) |
| `--normal-strength` | `1.0` | Fuerza del relieve del normal map |
| `--bevel` | `0.25` | Ancho del bisel entre vóxeles de distinto color (fracción del vóxel) |
| `--voxel-bevel` | `0` | Bisel en **todos** los bordes de vóxel, aspecto "bloque" (prueba `0.4`) |
| `--roughness` | `0.6` | Rugosidad base si el modelo no trae la suya (VoxEdit casi nunca la trae) |
| `--rough-var` | `0.35` | Variación de rugosidad: lo oscuro más mate, lo claro más pulido |
| `--metal` | `0` | Metalicidad base si el modelo no trae la suya |
| `--log-file ARCHIVO` | | Escribe el log completo en un archivo en vez de la consola |
| `--progress-file`, `--thumb-list` | | Uso interno de las ventanas |

## Configuración, logs y caché

- **Ruta de Blender:** se encuentra sola en `C:\Program Files\Blender Foundation\` (la versión más nueva). Si no, ponla en la primera línea de `VoxToRoblox.ps1` y `ProjectToGltf.ps1`.
- **Logs:** `app\log.txt` (GLTF → Roblox) y `app\log_projects.txt` (proyectos → GLTF); los botones **Ver log** los abren.
- **Miniaturas e idioma:** se guardan en `%LOCALAPPDATA%\VoxToRoblox\` (`thumbs\` y `settings.txt`).
- La columna Equipable viene marcada cuando el nombre del archivo tiene una de las palabras de `$EquipWords` (`VoxToRoblox.ps1`).

## Los lanzadores

`Start VoxEdit to Roblox.exe` y `Start VoxEdit Project to GLTF.exe` solo abren `app\VoxToRoblox.ps1` y `app\ProjectToGltf.ps1` sin consola (`app\` debe quedar junto a ellos). Su código es [`Launcher.cs`](Launcher.cs); para recompilarlos desde la carpeta del proyecto (por ejemplo si cambias los `.ico`):

```bat
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /win32icon:app\VoxToRoblox.ico /out:"Start VoxEdit to Roblox.exe" app\Launcher.cs
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /define:PROJECT_TO_GLTF /win32icon:app\VoxEditToGltf.ico /out:"Start VoxEdit Project to GLTF.exe" app\Launcher.cs
```

No están firmados. Si Windows los bloquea, las ventanas también se abren con clic derecho en `VoxToRoblox.ps1` / `ProjectToGltf.ps1` → **Ejecutar con PowerShell**. Los `.ps1` deben quedar guardados en UTF-8 con BOM (para los textos en español en Windows PowerShell 5.1).

## Créditos

La estructura de los archivos de proyecto de VoxEdit sigue los lectores de código abierto de [vengi](https://github.com/vengi-voxel/vengi) (MIT, © [Martin Gerhardy, @mgerhardy](https://github.com/mgerhardy)); la conversión en sí se escribió para VoxToRoblox y se comprobó contra las exportaciones de VoxEdit. VoxToRoblox no está afiliado a The Sandbox ni a VoxEdit.
