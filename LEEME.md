<p align="center"><img src="docs/logo.png" width="96" alt="Logo de VoxToRoblox"></p>

<h1 align="center">VoxToRoblox</h1>

<p align="center">
Convierte modelos animados de <b>VoxEdit</b> (glTF / GLB) en FBX listos para <b>Roblox</b>: un rig de una sola malla con todas sus animaciones, un atlas de textura nítido, mapas PBR y kits de equipables.<br>
Una app simple para Windows que usa Blender.
</p>

<p align="center"><a href="README.md">English</a> · <b>Español</b></p>

---

## Requisitos

- **Windows 10 u 11.** La ventana usa PowerShell y Windows Forms, que ya vienen con Windows.
- **[Blender](https://www.blender.org/download/) 4.4 o superior** (gratis). Probado con Blender 5.2.
  Se encuentra solo en `C:\Program Files\Blender Foundation\` (usa la versión más nueva).
  Si lo instalaste en otra carpeta, pon su ruta en la primera línea de `VoxToRoblox.ps1`.
- **Nada más para convertir:** Blender ya trae su propio Python, numpy y los complementos de glTF/FBX. **No** hace falta instalar Python.
- **VoxEdit**, para exportar tus modelos como `.gltf` / `.glb` (con animaciones).
- **Roblox Studio**, para importar el resultado.
- Solo para `PBRTuner.lua` en juegos publicados: activar las APIs de Mesh/Image (*Configuración del juego → Seguridad*) y tener la cuenta dueña verificada.

## Uso rápido

1. Pon los `.gltf` / `.glb` (con sus `.bin` y texturas, o en subcarpetas) dentro de `Input\`.
2. Doble clic en **`Start VoxEdit to Roblox.exe`**: se abre una ventana con la lista de archivos de `Input\`.
3. Elige las opciones si quieres (altura en studs, tamaño de textura, mapas PBR, saltar los ya convertidos, abrir Output al terminar).
4. Marca **Equipable** en los equipables de VoxEdit (casco, pecho, brazos, piernas, arma, escudo…): esos archivos se convierten con el [algoritmo de kit](#kits-cuerpo--equipo--armas). Los que tienen en el nombre *Helmet, Shield, Weapon, Legs, Arms* o *Chest* ya vienen marcados; puedes cambiarlo.
5. Presiona **Convertir**. Cada archivo muestra una miniatura, su barra de progreso y su estado; la barra de abajo es el total.
   El resultado queda en `Output\<Nombre>\`. Si un archivo falla, **Ver log** muestra el detalle (`log.txt`).

La ventana también tiene botones para abrir las carpetas **Input** y **Output**, **Actualizar** la lista, **Cancelar** una conversión y **Limpiar Output** (manda todo lo de `Output` a la Papelera de reciclaje, preguntando antes).
**Idioma** (arriba a la derecha): inglés o español. Abre en el idioma de tu Windows y recuerda lo que elijas.

## Qué se genera

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

## Importar en Roblox de una vez

1. En Studio: **Import 3D** → elige `<Nombre>_Roblox.fbx` (unidad *Stud*).
2. En el importador, revisa que aparezcan las animaciones en el árbol y dale **Import**. El rig queda en la escena y cada animación se sube a tu inventario.
3. Para usarlas: *Animation Editor → Import from Roblox*, o copia el ID desde el inventario.

> La animación de T-pose no se incluye porque es idéntica a la pose de reposo.

### Material (SurfaceAppearance de la malla)

| Propiedad | Mapa |
|---|---|
| `ColorMap` | `_Atlas` |
| `NormalMap` | `_Normal` |
| `RoughnessMap` | `_Roughness` |
| `MetalnessMap` | `_Metalness` |
| `EmissiveMaskContent` | `_Emissive` (+ `EmissiveStrength` / `EmissiveTint`) |
| `ResampleMode` | `Pixelated` |

Roblox necesita cada mapa en su propio campo (no admite un solo PNG "empaquetado") y reduce cualquier imagen a 1024×1024 al subirla.

## Kits (cuerpo + equipo + armas)

En la ventana, marca **Equipable** en cada pieza del kit y presiona **Convertir**. Todos los archivos marcados de la misma carpeta se convierten juntos como **un kit**: un solo cuerpo, la misma escala y la posición de cada pieza.

- Archivos sueltos en `Input\`: el kit toma el nombre de la palabra que comparten (`Knight_Helmet`, `Knight_Legs` → **Knight**).
- Archivos en una subcarpeta (`Input\Pirate\…`): el kit se llama como la carpeta; así puedes convertir varios kits a la vez.

Pon **todas** las piezas del kit juntas; un kit necesita al menos una pieza exportada sobre el avatar de VoxEdit (con el cuerpo).
Sale en `Output\<Kit>_Kit\`:

| Archivo | Qué es |
|---|---|
| `<Kit>_Body.fbx` | Rig rígido: una malla por hueso (Motor6D en Roblox) + `HumanoidRootPart` |
| `<Set>.fbx` | Uno por set de equipo, una malla por hueso, en la pose de reposo del cuerpo |
| `<Arma>.fbx` | Armas sueltas: una malla `Handle` |
| `<Kit>_Animations.json` | Animaciones del cuerpo para Studio |
| `<Kit>_Offsets.json` | Posición de cada pieza relativa a su hueso |
| `<Kit>_Kit.blend` | Todo junto para revisar |
| `<Kit>_report.txt` | Resumen |

## Subir / bajar la intensidad en Roblox (`PBRTuner.lua`)

1. Crea un **LocalScript** en `StarterPlayerScripts` llamado `PBRTuner` y pega `PBRTuner.lua`.
2. A la MeshPart ponle el tag `PBRTuner` y los atributos que quieras (números):
   `PBR_Normal 1` · `PBR_Roughness 1` · `PBR_RoughnessAdd 0` · `PBR_Metalness 1` · `PBR_MetalnessAdd 0` · `PBR_Emissive 4`
3. Dale **Play** y cambia los atributos (vista Cliente): se actualiza al instante. Cuando te guste, pon los mismos valores en modo edición para guardarlos.

## Qué hace

- Convierte las piezas sueltas de VoxEdit en una sola malla con esqueleto.
- Junta todas las texturas en un atlas nítido (sin suavizado).
- Escala a 5.5 studs, pies en el origen, mirando al frente de Roblox. Reposo = la T-pose del modelo (detecta "T POSE", "T", "TPose"…).
- Fusiona huesos que casi no se mueven (por defecto, si el error es menor a medio vóxel).
- Reduce keyframes redundantes al exportar.
- El normal map se calcula del color: lo oscuro queda hundido y lo claro en relieve, con un bisel donde cambian los colores.
- Es un rig propio, no R15.

## Desde consola

Conversor:

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python voxedit_to_roblox.py -- ARCHIVOS [opciones]
```

Kit:

```bat
"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python voxedit_kit_to_roblox.py -- GLTFS... [--name Kit] [--out CARPETA]
```

Desde consola el resultado queda en `Roblox\<Nombre>\` junto al glTF (o en `--out`).

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
| `--emis-relative` | | Máscara emisiva con la intensidad de VoxEdit (por defecto: todo lo que brilla en blanco puro; el brillo se ajusta con `EmissiveStrength`) |
| `--normal-strength` | `1.0` | Fuerza del relieve del normal map |
| `--bevel` | `0.25` | Ancho del bisel entre vóxeles de distinto color (fracción del vóxel) |
| `--voxel-bevel` | `0` | Bisel en **todos** los bordes de vóxel, aspecto "bloque" (prueba `0.4`) |
| `--roughness` | `0.6` | Rugosidad base si el modelo no trae la suya (VoxEdit casi nunca la trae) |
| `--rough-var` | `0.35` | Variación de rugosidad: lo oscuro más mate, lo claro más pulido |
| `--metal` | `0` | Metalicidad base si el modelo no trae la suya |
| `--log-file ARCHIVO` | | Escribe el log completo en un archivo en vez de la consola |
| `--progress-file`, `--thumb-list` | | Uso interno de la ventana |

## El lanzador

`Start VoxEdit to Roblox.exe` es solo un lanzador pequeño con el logo: abre `VoxToRoblox.ps1`, que debe quedar en la misma carpeta. Su código es [`Launcher.cs`](Launcher.cs); para recompilarlo (por ejemplo si cambias `VoxToRoblox.ico`):

```bat
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /win32icon:VoxToRoblox.ico /out:"Start VoxEdit to Roblox.exe" Launcher.cs
```

No está firmado, así que al descargarlo Windows puede avisar que es de un editor desconocido: **Más información → Ejecutar de todas formas**, o clic derecho en `VoxToRoblox.ps1` → **Ejecutar con PowerShell**.

## Licencia

[MIT](LICENSE) © Ashara Studios — hecho con amor por [Ashara Studios](https://asharastudios.com).
