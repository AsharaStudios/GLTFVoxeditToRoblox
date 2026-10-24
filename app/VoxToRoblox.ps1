# VoxToRoblox - Convert window. Opened by "Start VoxEdit to Roblox.exe"; uses only what ships with Windows (PowerShell + Windows Forms).
# Lists the .gltf/.glb files in Input\, runs voxedit_to_roblox.py in Blender and shows the progress of each file.
# (saved as UTF-8 with BOM so Windows PowerShell 5.1 reads the Spanish texts right)

$Blender = 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'   # if missing, the newest installed Blender is used

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$Native = $true
try {
    Add-Type -Namespace VoxToRoblox -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);
'@
    [void][VoxToRoblox.Native]::SetProcessDPIAware()
} catch { $Native = $false }
[System.Windows.Forms.Application]::EnableVisualStyles()

$AppDir   = $PSScriptRoot                    # (this script, the Python scripts, icons and logs live in app\)
$Root     = Split-Path $AppDir -Parent      # (the launchers, the readmes and Input / Output live here)
$InputDir = Join-Path $Root 'Input'
$OutDir   = Join-Path $Root 'Output'
$PyScript = Join-Path $AppDir 'voxedit_to_roblox.py'
$LogFile  = Join-Path $AppDir 'log.txt'
$ProgFile = Join-Path $env:TEMP "voxtoroblox_progress_$PID.txt"   # (per window: two open windows do not mix their progress)
$AppData  = Join-Path $env:LOCALAPPDATA 'VoxToRoblox'
$Settings = Join-Path $AppData 'settings.txt'
$WebSite  = 'https://asharastudios.com'
foreach ($d in $InputDir, $OutDir, $AppData) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ------------------------------------------------------------------ languages
$Strings = @{
    en = @{
        BlenderMissing = "Blender was not found.`n`nInstall Blender 4.4 or newer from blender.org, or set its path at the top of app\VoxToRoblox.ps1."
        Subtitle = 'Put your VoxEdit .gltf / .glb files in the Input folder and press Convert.'
        Language = 'Language'
        Height = 'Height (studs)'; Texture = 'Texture'
        Pbr = 'PBR maps'; Palette = 'Sharp pixels'; Skip = 'Skip already converted'; OpenWhenDone = 'Open Output when done'
        TipHeight = 'Final height of the character in studs'
        TipTexture = 'Size of the texture atlas (Roblox downsizes anything above 1024)'
        TipPbr = 'Also generate the Normal, Roughness, Metalness and Emissive maps'
        TipPalette = 'Cuts every face into flat-colour rectangles so the pixel art stays sharp in Roblox (about 4x more triangles; kits are not affected)'
        TipSkip = 'Do not convert files that already have <Name>_Roblox.fbx in Output'
        TipOpen = 'Open the Output folder when the conversion finishes'
        Empty = "The Input folder is empty.`nPut .gltf / .glb files there, then press Refresh."
        Convert = 'Convert'; Cancel = 'Cancel'; OpenOutput = 'Open Output'; ClearOutput = 'Clear Output'
        OpenInput = 'Open Input'; Refresh = 'Refresh'; OpenLog = 'Open log'
        TipClear = 'Move everything in the Output folder to the Recycle Bin'
        Credit = 'Created by Ashara Studios with love'
        ColEquip = 'Equipable'; ColFile = 'File'; ColProgress = 'Progress'; ColStatus = 'Status'
        ColExport = 'Export'; TipExportCol = 'Tick the files to convert (click here to tick or untick them all)'
        TipExportRow = 'Export: convert this file'; NotSelected = 'Not selected'
        NoneSelected = 'Tick at least one file in the Export column'
        TipEquipCol = 'Tick VoxEdit equipment (helmet, chest, arms, legs, weapon, shield...). Ticked files in the same folder are converted together as one kit.'
        TipEquipRow = 'Equipable: convert it with the kit algorithm (body + equipment sets)'
        Ready = 'Ready'; ReadyKit = "Ready - kit '{0}'"
        ConvertedBefore = 'Converted before'; SkipConverted = 'Already converted (skip)'
        KitSkip = "Kit '{0}' already converted (skip)"; KitBefore = "Kit '{0}' - converted before"
        Waiting = 'Waiting'; Starting = 'Starting...'; Done = 'Done ({0} s)'; KitSuffix = " - kit '{0}'"
        Error = 'Error - see log'; Stopped = 'Blender stopped - see log'; NotConverted = 'Not converted'
        Nothing = 'Nothing to convert'; FilesIn = '{0} file(s) in Input'; AlreadyN = ', {0} already converted'
        AllConverted = 'Everything is already converted (untick "Skip already converted" to redo it)'
        StartingBlender = 'Starting Blender...'; StartingKit = "Starting Blender for kit '{0}'..."
        Converting = 'Converting {0} of {1}: {2}'; KitName = "kit '{0}'"
        CannotStart = 'Could not start Blender: {0}'
        Cancelled = 'Cancelled - {0} of {1} converted'
        Failed = '{0} of {1} converted, {2} failed (see log) - {3}'
        AllDone = 'Done: {0} of {1} converted in {2}'
        NoLog = 'There is no log yet: it is created when you convert'
        OutputEmpty = 'The Output folder is already empty'
        ClearAsk = 'Move everything in the Output folder ({0} item(s)) to the Recycle Bin?'
        ClearFailed = '{0} item(s) could not be removed (is a file open in another program?)'
        Cleared = 'Output cleared (moved to the Recycle Bin)'
        CloseAsk = 'A conversion is running. Stop it and close?'
    }
    es = @{
        BlenderMissing = "No se encontró Blender.`n`nInstala Blender 4.4 o superior desde blender.org, o pon su ruta al inicio de app\VoxToRoblox.ps1."
        Subtitle = 'Pon tus archivos .gltf / .glb de VoxEdit en la carpeta Input y presiona Convertir.'
        Language = 'Idioma'
        Height = 'Altura (studs)'; Texture = 'Textura'
        Pbr = 'Mapas PBR'; Palette = 'Píxeles nítidos'; Skip = 'Saltar los ya convertidos'; OpenWhenDone = 'Abrir Output al terminar'
        TipHeight = 'Altura final del personaje en studs'
        TipTexture = 'Tamaño del atlas de textura (Roblox reduce todo lo que pase de 1024)'
        TipPbr = 'Generar también los mapas Normal, Roughness, Metalness y Emissive'
        TipPalette = 'Corta cada cara en rectángulos de un solo color para que el pixel art se vea nítido en Roblox (unas 4 veces más triángulos; no afecta a los kits)'
        TipSkip = 'No convertir los archivos que ya tienen <Nombre>_Roblox.fbx en Output'
        TipOpen = 'Abrir la carpeta Output cuando termine la conversión'
        Empty = "La carpeta Input está vacía.`nPon ahí archivos .gltf / .glb y presiona Actualizar."
        Convert = 'Convertir'; Cancel = 'Cancelar'; OpenOutput = 'Abrir Output'; ClearOutput = 'Limpiar Output'
        OpenInput = 'Abrir Input'; Refresh = 'Actualizar'; OpenLog = 'Ver log'
        TipClear = 'Mandar todo lo de la carpeta Output a la Papelera de reciclaje'
        Credit = 'Creado por Ashara Studios con amor'
        ColEquip = 'Equipable'; ColFile = 'Archivo'; ColProgress = 'Progreso'; ColStatus = 'Estado'
        ColExport = 'Exportar'; TipExportCol = 'Marca los archivos que quieres convertir (clic aquí para marcarlos o desmarcarlos todos)'
        TipExportRow = 'Exportar: convertir este archivo'; NotSelected = 'No seleccionado'
        NoneSelected = 'Marca al menos un archivo en la columna Exportar'
        TipEquipCol = 'Marca los equipables de VoxEdit (casco, pecho, brazos, piernas, arma, escudo...). Los archivos marcados de la misma carpeta se convierten juntos como un kit.'
        TipEquipRow = 'Equipable: se convierte con el algoritmo de kit (cuerpo + sets de equipo)'
        Ready = 'Listo para convertir'; ReadyKit = "Listo - kit '{0}'"
        ConvertedBefore = 'Convertido antes'; SkipConverted = 'Ya convertido (se salta)'
        KitSkip = "Kit '{0}' ya convertido (se salta)"; KitBefore = "Kit '{0}' - convertido antes"
        Waiting = 'En espera'; Starting = 'Iniciando...'; Done = 'Terminado ({0} s)'; KitSuffix = " - kit '{0}'"
        Error = 'Error - ver log'; Stopped = 'Blender se detuvo - ver log'; NotConverted = 'No convertido'
        Nothing = 'Nada para convertir'; FilesIn = '{0} archivo(s) en Input'; AlreadyN = ', {0} ya convertido(s)'
        AllConverted = 'Todo ya está convertido (desmarca "Saltar los ya convertidos" para repetirlo)'
        StartingBlender = 'Iniciando Blender...'; StartingKit = "Iniciando Blender para el kit '{0}'..."
        Converting = 'Convirtiendo {0} de {1}: {2}'; KitName = "kit '{0}'"
        CannotStart = 'No se pudo iniciar Blender: {0}'
        Cancelled = 'Cancelado - {0} de {1} convertidos'
        Failed = '{0} de {1} convertidos, {2} con error (ver log) - {3}'
        AllDone = 'Listo: {0} de {1} convertidos en {2}'
        NoLog = 'Todavía no hay log: se crea al convertir'
        OutputEmpty = 'La carpeta Output ya está vacía'
        ClearAsk = '¿Mandar todo lo de la carpeta Output ({0} elemento(s)) a la Papelera de reciclaje?'
        ClearFailed = 'No se pudieron quitar {0} elemento(s) (¿hay un archivo abierto en otro programa?)'
        Cleared = 'Output limpia (enviado a la Papelera de reciclaje)'
        CloseAsk = 'Hay una conversión en curso. ¿Detenerla y cerrar?'
    }
}
# the steps voxedit_to_roblox.py / voxedit_kit_to_roblox.py report (always in English)
$StepsEs = @{
    'Importing' = 'Importando'; 'Reading animations' = 'Leyendo animaciones'; 'Merging bones' = 'Fusionando huesos'
    'Building atlas' = 'Creando atlas'; 'PBR maps' = 'Mapas PBR'; 'Building animations' = 'Creando animaciones'
    'Exporting FBX' = 'Exportando FBX'; 'Exporting animations' = 'Exportando animaciones'
    'Exporting Roblox FBX' = 'Exportando FBX para Roblox'; 'Saving .blend' = 'Guardando .blend'
    'Building body' = 'Creando cuerpo'; 'Saving animations' = 'Guardando animaciones'
}
$Languages = [ordered]@{ en = 'English'; es = 'Español' }

$Lang = if ((Get-Culture).TwoLetterISOLanguageName -eq 'es') { 'es' } else { 'en' }
try {
    $saved = (Get-Content -LiteralPath $Settings -ErrorAction Stop | Where-Object { $_ -like 'lang=*' } | Select-Object -First 1) -replace '^lang=', ''
    if ($Strings.ContainsKey($saved)) { $Lang = $saved }
} catch { }

function Tr([string]$key) {
    $s = $Strings[$Lang][$key]
    if ($args.Count) { $s -f $args } else { $s }
}
function Tr-Step([string]$label) {
    if ($Lang -ne 'es') { return $label }
    if ($StepsEs.ContainsKey($label)) { return $StepsEs[$label] }
    if ($label -like 'Reading *') { return 'Leyendo ' + $label.Substring(8) }
    if ($label -like 'Exporting *') { return 'Exportando ' + $label.Substring(10) }
    $label
}

if (-not (Test-Path -LiteralPath $Blender)) {
    $Blender = Get-ChildItem -LiteralPath "$env:ProgramFiles\Blender Foundation" -Directory -ErrorAction SilentlyContinue |
        Sort-Object { if ($_.Name -match '(\d+)\.(\d+)') { [int]$Matches[1] * 1000 + [int]$Matches[2] } else { 0 } } -Descending |
        ForEach-Object { Join-Path $_.FullName 'blender.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Blender) {
    [void][System.Windows.Forms.MessageBox]::Show((Tr BlenderMissing), 'VoxToRoblox', 'OK', 'Error')
    return
}

# ------------------------------------------------------------------ look (dark)
$g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $Scale = $g.DpiX / 96; $g.Dispose()
function Px([double]$v) { [int][Math]::Round($v * $Scale) }
function Rgb($r, $g, $b) { [System.Drawing.Color]::FromArgb($r, $g, $b) }
$ColBg      = Rgb 32 32 32
$ColSurface = Rgb 43 43 43
$ColControl = Rgb 55 55 55
$ColHover   = Rgb 70 70 70
$ColBorder  = Rgb 85 85 85
$ColTrack   = Rgb 62 62 62
$ColText    = Rgb 232 232 232
$ColMuted   = Rgb 160 160 160
$ColOk      = Rgb 108 203 95
$ColErr     = Rgb 255 120 120
$ColWork    = Rgb 96 205 255
$ColAccent  = Rgb 0 120 212
$ColLink    = Rgb 96 205 255
$Font      = New-Object System.Drawing.Font('Segoe UI', 9.5)
$FontBold  = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
$FontTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 16)
$FontSmall = New-Object System.Drawing.Font('Segoe UI', 8.5)
$Inv       = [System.Globalization.CultureInfo]::InvariantCulture

function New-Label($text, $color = $ColText) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.ForeColor = $color; $l.AutoSize = $true
    $l.Margin = New-Object System.Windows.Forms.Padding(0, (Px 6), (Px 6), 0)
    $l
}
function New-Button([switch]$Primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.AutoSize = $true
    $b.MinimumSize = New-Object System.Drawing.Size((Px 100), (Px 34))
    $b.Margin = New-Object System.Windows.Forms.Padding((Px 6), 0, 0, 0)
    $b.FlatStyle = 'Flat'; $b.ForeColor = $ColText; $b.UseVisualStyleBackColor = $false
    if ($Primary) {
        $b.Font = $FontBold; $b.ForeColor = [System.Drawing.Color]::White
        $b.BackColor = $ColAccent; $b.FlatAppearance.BorderSize = 0; $b.FlatAppearance.BorderColor = $ColAccent
        $b.FlatAppearance.MouseOverBackColor = Rgb 26 140 230
        $b.Add_EnabledChanged({ $this.BackColor = if ($this.Enabled) { $ColAccent } else { $ColControl } })
    } else {
        $b.BackColor = $ColControl; $b.FlatAppearance.BorderColor = $ColBorder
        $b.FlatAppearance.MouseOverBackColor = $ColHover
    }
    $b
}
# flat progress bar (the Windows one ignores colours): a track panel with a fill panel inside
function New-Bar($height) {
    $track = New-Object System.Windows.Forms.Panel
    $track.Height = $height; $track.BackColor = $ColTrack; $track.Tag = 0.0
    $fill = New-Object System.Windows.Forms.Panel
    $fill.Dock = 'Left'; $fill.Width = 0; $fill.BackColor = $ColWork
    $track.Controls.Add($fill)
    $track.Add_Resize({ Update-Bar $this })
    $track
}
function Update-Bar($track) { $track.Controls[0].Width = [int]($track.ClientSize.Width * [double]$track.Tag) }
function Set-Bar($track, [double]$frac, $color = $null) {
    $track.Tag = [Math]::Max(0.0, [Math]::Min(1.0, $frac))
    if ($color) { $track.Controls[0].BackColor = $color }
    Update-Bar $track
}

# ------------------------------------------------------------------ window
$form = New-Object System.Windows.Forms.Form
$form.Text = 'VoxToRoblox'
$form.Font = $Font
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size((Px 880), (Px 590))
$form.MinimumSize = New-Object System.Drawing.Size((Px 640), (Px 440))
$form.BackColor = $ColBg; $form.ForeColor = $ColText
$LogoFile = Join-Path $AppDir 'VoxToRoblox.ico'
$Logo = $null
try {
    $form.Icon = New-Object System.Drawing.Icon($LogoFile)
    # big logo for the header: the last (256 px) PNG stored inside the .ico
    $ico = [IO.File]::ReadAllBytes($LogoFile)
    $e = 6 + 16 * ([BitConverter]::ToUInt16($ico, 4) - 1)
    $Logo = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream($ico, [BitConverter]::ToInt32($ico, $e + 12), [BitConverter]::ToInt32($ico, $e + 8))))
} catch { }
$tip = New-Object System.Windows.Forms.ToolTip

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = 'Fill'; $main.ColumnCount = 1
$main.Padding = New-Object System.Windows.Forms.Padding((Px 16), (Px 16), (Px 16), (Px 8))
[void]$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
foreach ($st in 'AutoSize', 'AutoSize', 'Percent', 'AutoSize', 'AutoSize', 'AutoSize', 'AutoSize') {
    [void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle($st, 100)))
}
$form.Controls.Add($main)

# header: logo + title + subtitle on the left, language on the right
$headerRow = New-Object System.Windows.Forms.TableLayoutPanel
$headerRow.ColumnCount = 2; $headerRow.AutoSize = $true; $headerRow.Dock = 'Fill'; $headerRow.Margin = New-Object System.Windows.Forms.Padding(0)
[void]$headerRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', 100)))
[void]$headerRow.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
$header = New-Object System.Windows.Forms.FlowLayoutPanel
$header.FlowDirection = 'TopDown'; $header.WrapContents = $false; $header.AutoSize = $true; $header.Margin = New-Object System.Windows.Forms.Padding(0)
$titleRow = New-Object System.Windows.Forms.FlowLayoutPanel
$titleRow.AutoSize = $true; $titleRow.WrapContents = $false; $titleRow.Margin = New-Object System.Windows.Forms.Padding(0)
if ($Logo) {
    $logoPic = New-Object System.Windows.Forms.PictureBox
    $logoPic.Image = $Logo; $logoPic.SizeMode = 'Zoom'
    $logoPic.Size = New-Object System.Drawing.Size((Px 30), (Px 30))
    $logoPic.Margin = New-Object System.Windows.Forms.Padding(0, (Px 2), (Px 8), 0)
    $titleRow.Controls.Add($logoPic)
}
$title = New-Label 'VoxToRoblox'; $title.Font = $FontTitle; $title.Margin = New-Object System.Windows.Forms.Padding(0)
$titleRow.Controls.Add($title)
$sub = New-Label '' $ColMuted
$sub.Margin = New-Object System.Windows.Forms.Padding(0, (Px 4), 0, 0)
$header.Controls.AddRange(@($titleRow, $sub))
$langBox = New-Object System.Windows.Forms.FlowLayoutPanel
$langBox.AutoSize = $true; $langBox.WrapContents = $false; $langBox.Anchor = 'Top, Right'; $langBox.Margin = New-Object System.Windows.Forms.Padding(0)
$lblLang = New-Label '' $ColMuted
$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.DropDownStyle = 'DropDownList'; [void]$cmbLang.Items.AddRange(@($Languages.Values))
$cmbLang.SelectedIndex = @($Languages.Keys).IndexOf($Lang); $cmbLang.Width = Px 96
$cmbLang.FlatStyle = 'Flat'; $cmbLang.BackColor = $ColControl; $cmbLang.ForeColor = $ColText
$cmbLang.Margin = New-Object System.Windows.Forms.Padding(0, (Px 2), 0, 0)
$langBox.Controls.AddRange(@($lblLang, $cmbLang))
$headerRow.Controls.Add($header, 0, 0); $headerRow.Controls.Add($langBox, 1, 0)
$main.Controls.Add($headerRow, 0, 0)

# options
$opts = New-Object System.Windows.Forms.FlowLayoutPanel
$opts.AutoSize = $true; $opts.Dock = 'Fill'; $opts.WrapContents = $true
$opts.Margin = New-Object System.Windows.Forms.Padding(0, (Px 12), 0, 0)
$lblHeight = New-Label ''
$numHeight = New-Object System.Windows.Forms.NumericUpDown
$numHeight.DecimalPlaces = 1; $numHeight.Increment = 0.5; $numHeight.Minimum = 1; $numHeight.Maximum = 100
$numHeight.Value = 5.5; $numHeight.Width = Px 64
$numHeight.BackColor = $ColControl; $numHeight.ForeColor = $ColText; $numHeight.BorderStyle = 'FixedSingle'
$numHeight.Margin = New-Object System.Windows.Forms.Padding(0, (Px 2), (Px 18), 0)
$lblTex = New-Label ''
$cmbTex = New-Object System.Windows.Forms.ComboBox
$cmbTex.DropDownStyle = 'DropDownList'; [void]$cmbTex.Items.AddRange(@('512', '1024', '2048', '4096'))
$cmbTex.SelectedItem = '1024'; $cmbTex.Width = Px 72
$cmbTex.FlatStyle = 'Flat'; $cmbTex.BackColor = $ColControl; $cmbTex.ForeColor = $ColText
$cmbTex.Margin = New-Object System.Windows.Forms.Padding(0, (Px 2), (Px 18), 0)
function New-Check($checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Checked = $checked; $c.AutoSize = $true
    $c.FlatStyle = 'Flat'; $c.ForeColor = $ColText; $c.FlatAppearance.BorderColor = $ColMuted
    $c.Margin = New-Object System.Windows.Forms.Padding(0, (Px 4), (Px 18), 0)
    $c
}
$chkPbr  = New-Check $true
$chkPalette = New-Check $false
$chkSkip = New-Check $false
$chkOpen = New-Check $false
$opts.Controls.AddRange(@($lblHeight, $numHeight, $lblTex, $cmbTex, $chkPbr, $chkPalette, $chkSkip, $chkOpen))
$main.Controls.Add($opts, 0, 1)

# file list
$listBox = New-Object System.Windows.Forms.Panel
$listBox.Dock = 'Fill'; $listBox.AutoScroll = $true; $listBox.BackColor = $ColSurface
$listBox.Margin = New-Object System.Windows.Forms.Padding(0, (Px 12), 0, 0)
$table = New-Object System.Windows.Forms.TableLayoutPanel
$table.Dock = 'Top'; $table.AutoSize = $true; $table.AutoSizeMode = 'GrowAndShrink'; $table.ColumnCount = 6
$table.Padding = New-Object System.Windows.Forms.Padding((Px 4), (Px 4), (Px 12), (Px 6))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', (Px 84))))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', (Px 84))))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', (Px 56))))
foreach ($w in 40, 30, 30) { [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', $w))) }
$empty = New-Label '' $ColMuted
$empty.Dock = 'Fill'; $empty.AutoSize = $false; $empty.TextAlign = 'MiddleCenter'
$listBox.Controls.AddRange(@($table, $empty))
$main.Controls.Add($listBox, 0, 2)

# overall progress
$overallLabel = New-Label ''
$overallLabel.Margin = New-Object System.Windows.Forms.Padding(0, (Px 12), 0, (Px 6))
$main.Controls.Add($overallLabel, 0, 3)
$overallBar = New-Bar (Px 6)
$overallBar.Dock = 'Fill'; $overallBar.Margin = New-Object System.Windows.Forms.Padding(0)
$main.Controls.Add($overallBar, 0, 4)

# buttons (right to left)
$btns = New-Object System.Windows.Forms.FlowLayoutPanel
$btns.FlowDirection = 'RightToLeft'; $btns.AutoSize = $true; $btns.Dock = 'Fill'; $btns.WrapContents = $false
$btns.Margin = New-Object System.Windows.Forms.Padding(0, (Px 14), 0, 0)
$btnConvert = New-Button -Primary
$btnCancel  = New-Button; $btnCancel.Visible = $false
$btnOutput  = New-Button
$btnClear   = New-Button
$btnInput   = New-Button
$btnRefresh = New-Button
$btnLog     = New-Button
$btns.Controls.AddRange(@($btnConvert, $btnCancel, $btnOutput, $btnClear, $btnInput, $btnRefresh, $btnLog))
$main.Controls.Add($btns, 0, 5)
$form.AcceptButton = $btnConvert

# credit
$credit = New-Object System.Windows.Forms.LinkLabel
$credit.AutoSize = $true; $credit.Font = $FontSmall; $credit.ForeColor = $ColMuted
$credit.LinkColor = $ColLink; $credit.ActiveLinkColor = $ColText; $credit.VisitedLinkColor = $ColLink
$credit.LinkBehavior = 'HoverUnderline'; $credit.Anchor = 'None'
$credit.Margin = New-Object System.Windows.Forms.Padding(0, (Px 12), 0, 0)
$tip.SetToolTip($credit, $WebSite)
$credit.Add_LinkClicked({ Start-Process $WebSite })
$main.Controls.Add($credit, 0, 6)

# every fixed text of the window, in the current language
function Set-Texts {
    $sub.Text = Tr Subtitle; $lblLang.Text = Tr Language
    $lblHeight.Text = Tr Height; $lblTex.Text = Tr Texture
    $chkPbr.Text = Tr Pbr; $chkPalette.Text = Tr Palette; $chkSkip.Text = Tr Skip; $chkOpen.Text = Tr OpenWhenDone
    $tip.SetToolTip($numHeight, (Tr TipHeight)); $tip.SetToolTip($cmbTex, (Tr TipTexture))
    $tip.SetToolTip($chkPbr, (Tr TipPbr)); $tip.SetToolTip($chkPalette, (Tr TipPalette)); $tip.SetToolTip($chkSkip, (Tr TipSkip)); $tip.SetToolTip($chkOpen, (Tr TipOpen))
    $empty.Text = Tr Empty
    $btnConvert.Text = Tr Convert; $btnCancel.Text = Tr Cancel; $btnOutput.Text = Tr OpenOutput
    $btnClear.Text = Tr ClearOutput; $btnInput.Text = Tr OpenInput; $btnRefresh.Text = Tr Refresh; $btnLog.Text = Tr OpenLog
    $tip.SetToolTip($btnClear, (Tr TipClear))
    $credit.Text = Tr Credit
    $at = $credit.Text.IndexOf('Ashara Studios')
    if ($at -ge 0) { $credit.LinkArea = New-Object System.Windows.Forms.LinkArea($at, 14) }
}

# dark title bar and scrollbars (Windows 10 1809+; older versions just keep the light ones)
$form.Add_HandleCreated({
    if (-not $Native) { return }
    $on = 1
    if ([VoxToRoblox.Native]::DwmSetWindowAttribute($form.Handle, 20, [ref]$on, 4) -ne 0) {
        [void][VoxToRoblox.Native]::DwmSetWindowAttribute($form.Handle, 19, [ref]$on, 4)
    }
})
$listBox.Add_HandleCreated({ if ($Native) { [void][VoxToRoblox.Native]::SetWindowTheme($listBox.Handle, 'DarkMode_Explorer', $null) } })

# ------------------------------------------------------------------ file list
$KitScript = Join-Path $AppDir 'voxedit_kit_to_roblox.py'
$script:rows = @{}           # path -> @{ Check; Thumb; ThumbPath; Name; Bar; Status; Waiting; Done }
$script:equipChoice = @{}    # path -> what the user ticked (overrides the name rule)
$script:exportChoice = @{}   # path -> unticked in the Export column (everything is ticked by default)
$script:fileKey = ''
$script:proc = $null

# ------------------------------------------------------------------ thumbnails
# rendered by Blender in the background (voxedit_to_roblox.py --thumb-list) and cached per file + date
$ThumbDir  = Join-Path $AppData 'thumbs'
$ThumbList = Join-Path $env:TEMP "voxtoroblox_thumbs_$PID.txt"
if (-not (Test-Path -LiteralPath $ThumbDir)) { New-Item -ItemType Directory -Path $ThumbDir -Force | Out-Null }
$script:thumbProc = $null

$ThumbPlaceholder = New-Object System.Drawing.Bitmap((Px 44), (Px 44))
& {
    $gr = [System.Drawing.Graphics]::FromImage($ThumbPlaceholder)
    $gr.SmoothingMode = 'AntiAlias'; $gr.Clear($ColControl)
    $pen = New-Object System.Drawing.Pen($ColMuted, [float](Px 1.5))
    $w = $ThumbPlaceholder.Width; $c = $w / 2; $r = $w * 0.26
    $p = { param($x, $y) New-Object System.Drawing.PointF([float]$x, [float]$y) }
    $top = & $p $c ($c - $r); $mid = & $p $c $c; $bot = & $p $c ($c + $r)
    $lt = & $p ($c - $r * 0.87) ($c - $r / 2); $rt = & $p ($c + $r * 0.87) ($c - $r / 2)
    $lb = & $p ($c - $r * 0.87) ($c + $r / 2); $rb = & $p ($c + $r * 0.87) ($c + $r / 2)
    $gr.DrawPolygon($pen, [System.Drawing.PointF[]]@($top, $rt, $rb, $bot, $lb, $lt))
    $gr.DrawLines($pen, [System.Drawing.PointF[]]@($lt, $mid, $rt)); $gr.DrawLine($pen, $mid, $bot)
    $pen.Dispose(); $gr.Dispose()
}

function Get-ThumbPath($file) {
    $key = "$($file.FullName)|$($file.LastWriteTimeUtc.Ticks)|$($file.Length)"
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $hash = -join ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($key)) | ForEach-Object { $_.ToString('x2') })
    $md5.Dispose()
    Join-Path $ThumbDir "$hash.png"
}
$script:thumbCache = @{}     # thumb path -> Image (loaded once, reused every time the list is rebuilt)
function Read-Image($path) {
    if (-not $script:thumbCache.ContainsKey($path)) {
        # (from memory, so the PNG is not kept locked)
        $ms = New-Object System.IO.MemoryStream(, [IO.File]::ReadAllBytes($path))
        $script:thumbCache[$path] = [System.Drawing.Image]::FromStream($ms)
    }
    $script:thumbCache[$path]
}

function Start-Thumbnails {
    if ($script:thumbProc) { return }
    $todo = @($script:rows.GetEnumerator() | Where-Object {
        -not (Test-Path -LiteralPath $_.Value.ThumbPath) -and -not (Test-Path -LiteralPath ($_.Value.ThumbPath + '.failed')) })
    if ($todo.Count -eq 0) { return }
    [IO.File]::WriteAllLines($ThumbList, [string[]]@($todo | ForEach-Object { "$($_.Key)`t$($_.Value.ThumbPath)" }), (New-Object System.Text.UTF8Encoding($false)))
    $psi = New-Object System.Diagnostics.ProcessStartInfo($Blender,
        ('-b --factory-startup --python "{0}" -- --thumb-list "{1}"' -f $PyScript, $ThumbList))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $script:thumbJob = @{}
    foreach ($t in $todo) { $script:thumbJob[$t.Value.ThumbPath] = $true }
    try { $script:thumbProc = [System.Diagnostics.Process]::Start($psi) } catch { $script:thumbProc = $null }
}

# called by the timer: show the thumbnails that are ready
function Update-Thumbnails {
    $running = $script:thumbProc -and -not $script:thumbProc.HasExited
    foreach ($r in $script:rows.Values) {
        if ($r.Thumb.Image -ne $ThumbPlaceholder) { continue }
        if (Test-Path -LiteralPath $r.ThumbPath) { try { $r.Thumb.Image = Read-Image $r.ThumbPath } catch { } }
        elseif (-not $running -and $script:thumbProc -and $script:thumbJob.ContainsKey($r.ThumbPath)) {
            [IO.File]::WriteAllText($r.ThumbPath + '.failed', '')   # (not retried until the file changes)
        }
    }
    if ($script:thumbProc -and -not $running) {
        $script:thumbProc.Dispose(); $script:thumbProc = $null
        Start-Thumbnails   # (files added while it was running)
    }
}

function Get-InputFiles {
    @(Get-ChildItem -LiteralPath $InputDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.gltf', '.glb' } | Sort-Object FullName)
}

function Get-SafeName($n) {
    # same as safe() in voxedit_kit_to_roblox.py
    $n = $n.Replace([string][char]0xF1, 'n').Replace([string][char]0xD1, 'N')
    $n = ($n -replace '[^A-Za-z0-9_]+', '_').Trim('_')
    if ($n) { $n } else { 'X' }
}
function Get-OutName($path) {
    # same folder name voxedit_to_roblox.py uses
    $name = [IO.Path]::GetFileNameWithoutExtension($path)
    $b = $name -replace '(?i)[_\- ]?(gltf|glb)$', ''
    if (-not $b) { $b = $name }
    $b -replace '[^A-Za-z0-9_]+', '_'
}
function Test-Converted($path) {
    $b = Get-OutName $path
    Test-Path -LiteralPath (Join-Path $OutDir "$b\$($b)_Roblox.fbx")
}

# the Equipable column comes ticked when the file name has one of these words
$EquipWords = 'Helmet', 'Shield', 'Weapon', 'Legs', 'Arms', 'Chest'
function Test-Equipable($file) { $file.BaseName -match "(?i)$($EquipWords -join '|')" }
function Test-Ticked($path) { $r = $script:rows[$path]; $r -and $r.Check.Checked }
function Test-Export($path) { $r = $script:rows[$path]; $r -and $r.Export.Checked }

# ticked files are grouped into kits by folder; the kit is named after the subfolder,
# or (directly in Input) after the word the file names share, e.g. Knight_Helmet + Knight_Legs -> Knight
function Get-KitName($dir, $paths) {
    if ($dir.TrimEnd('\') -ne $InputDir.TrimEnd('\')) { return Get-SafeName (Split-Path $dir -Leaf) }
    $skip = 'legs', 'leg', 'arms', 'arm', 'chest', 'helmet', 'head', 'weapon', 'shield', 'body', 'equip',
            'tier', 'set', 'ii', 'iii', 'iv', 'de', 'del', 'la', 'el', 'the', 'of'
    $count = @{}; $order = 0
    foreach ($p in $paths) {
        $seen = @{}
        foreach ($w in ([IO.Path]::GetFileNameWithoutExtension($p) -split '[^A-Za-z0-9]+')) {
            $k = $w.ToLower()
            if ($w.Length -lt 2 -or $skip -contains $k -or $seen.ContainsKey($k)) { continue }
            $seen[$k] = 1
            if ($count.ContainsKey($k)) { $count[$k].N++ } else { $count[$k] = @{ N = 1; Word = $w; Order = $order++ } }
        }
    }
    if ($count.Count -eq 0) { return 'Kit' }
    $best = $count.Values | Sort-Object @{ Expression = { $_.N }; Descending = $true }, @{ Expression = { $_.Order } } | Select-Object -First 1
    Get-SafeName $best.Word
}
function Get-Kits {
    $groups = [ordered]@{}
    foreach ($p in ($script:rows.Keys | Sort-Object)) {
        if (-not (Test-Ticked $p) -or -not (Test-Export $p)) { continue }
        $dir = [IO.Path]::GetDirectoryName($p)
        if (-not $groups.Contains($dir)) { $groups[$dir] = New-Object System.Collections.ArrayList }
        [void]$groups[$dir].Add($p)
    }
    foreach ($dir in $groups.Keys) {
        $name = Get-KitName $dir $groups[$dir]
        @{ Name = $name; Paths = @($groups[$dir]); Out = (Join-Path $OutDir "$($name)_Kit") }
    }
}
function Test-KitConverted($kit) { Test-Path -LiteralPath (Join-Path $kit.Out "$($kit.Name)_Kit.blend") }

function Set-Row($path, $text, $color, [double]$frac = -1) {
    $r = $script:rows[$path]
    if (-not $r) { return }
    $r.Status.Text = $text; $r.Status.ForeColor = $color
    Set-Bar $r.Bar $(if ($frac -ge 0) { $frac } else { [double]$r.Bar.Tag }) $color
}

function Add-HeaderRow {
    $table.RowCount = 1
    [void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    # "Export" header: a check box that ticks / unticks every file
    $all = New-Object System.Windows.Forms.CheckBox
    $all.Text = Tr ColExport; $all.AutoSize = $true; $all.Anchor = 'None'; $all.Font = $FontSmall
    $all.FlatStyle = 'Flat'; $all.ForeColor = $ColMuted; $all.FlatAppearance.BorderColor = $ColMuted
    $all.Margin = New-Object System.Windows.Forms.Padding(0, (Px 4), 0, (Px 2))
    $all.Checked = $true
    $tip.SetToolTip($all, (Tr TipExportCol))
    $all.Add_Click({
        $script:bulk = $true
        foreach ($r in $script:rows.Values) { $r.Export.Checked = $this.Checked; $script:exportChoice[$r.Export.Tag] = $this.Checked }
        $script:bulk = $false
        if (-not $script:proc) { Update-Statuses }
    })
    $script:exportAll = $all
    $table.Controls.Add($all, 0, 0)
    $i = 1
    foreach ($h in (Tr ColEquip), '', (Tr ColFile), (Tr ColProgress), (Tr ColStatus)) {
        $l = New-Label $h $ColMuted
        $l.Font = $FontSmall; $l.Margin = New-Object System.Windows.Forms.Padding((Px 3), (Px 4), 0, (Px 2))
        if ($i -eq 1) { $l.Anchor = 'None'; $tip.SetToolTip($l, (Tr TipEquipCol)) }
        if ($i -eq 4) { $l.Margin = New-Object System.Windows.Forms.Padding((Px 8), (Px 4), 0, (Px 2)) }
        $table.Controls.Add($l, $i, 0); $i++
    }
}

# the header box shows ticked only when every file is ticked
function Update-ExportAll {
    if (-not $script:exportAll) { return }
    $script:exportAll.Checked = (@($script:rows.Values | Where-Object { -not $_.Export.Checked }).Count -eq 0)
}

function Add-Row($file) {
    $i = $table.RowCount
    $table.RowCount = $i + 1
    [void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    $exp = New-Object System.Windows.Forms.CheckBox
    $exp.AutoSize = $true; $exp.Anchor = 'None'; $exp.FlatStyle = 'Flat'
    $exp.FlatAppearance.BorderColor = $ColMuted; $exp.ForeColor = $ColText
    $exp.Checked = -not ($script:exportChoice.ContainsKey($file.FullName) -and -not $script:exportChoice[$file.FullName])
    $exp.Tag = $file.FullName
    $tip.SetToolTip($exp, (Tr TipExportRow))
    $exp.Add_CheckedChanged({
        if ($script:bulk) { return }
        $script:exportChoice[$this.Tag] = $this.Checked
        Update-ExportAll
        if (-not $script:proc) { Update-Statuses }
    })
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.AutoSize = $true; $chk.Anchor = 'None'; $chk.FlatStyle = 'Flat'
    $chk.FlatAppearance.BorderColor = $ColMuted; $chk.ForeColor = $ColText
    $chk.Checked = if ($script:equipChoice.ContainsKey($file.FullName)) { $script:equipChoice[$file.FullName] } else { Test-Equipable $file }
    $chk.Tag = $file.FullName
    $tip.SetToolTip($chk, (Tr TipEquipRow))
    $chk.Add_CheckedChanged({
        $script:equipChoice[$this.Tag] = $this.Checked
        if (-not $script:proc) { Update-Statuses }
    })
    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Size = New-Object System.Drawing.Size((Px 44), (Px 44)); $pic.SizeMode = 'Zoom'; $pic.Anchor = 'None'
    $pic.Margin = New-Object System.Windows.Forms.Padding(0, (Px 2), 0, (Px 2))
    $thumb = Get-ThumbPath $file
    $pic.Image = if (Test-Path -LiteralPath $thumb) { Read-Image $thumb } else { $ThumbPlaceholder }
    $name = New-Object System.Windows.Forms.Label
    $name.Text = $file.FullName.Substring($InputDir.Length).TrimStart('\')
    $name.AutoEllipsis = $true; $name.Dock = 'Fill'; $name.TextAlign = 'MiddleLeft'; $name.Height = Px 32
    $name.ForeColor = $ColText
    $tip.SetToolTip($name, $file.FullName)
    $bar = New-Bar (Px 6)
    $bar.Anchor = 'Left, Right'
    $bar.Margin = New-Object System.Windows.Forms.Padding((Px 8), 0, (Px 14), 0)
    $st = New-Object System.Windows.Forms.Label
    $st.AutoEllipsis = $true; $st.Dock = 'Fill'; $st.TextAlign = 'MiddleLeft'
    $table.Controls.Add($exp, 0, $i); $table.Controls.Add($chk, 1, $i); $table.Controls.Add($pic, 2, $i)
    $table.Controls.Add($name, 3, $i); $table.Controls.Add($bar, 4, $i); $table.Controls.Add($st, 5, $i)
    $script:rows[$file.FullName] = @{ Export = $exp; Check = $chk; Thumb = $pic; ThumbPath = $thumb; Name = $name; Bar = $bar; Status = $st; Waiting = $false; Done = $false }
}

# idle status of every row (which kit it goes to, whether it was converted before)
function Update-Statuses {
    $done = 0
    foreach ($kit in @(Get-Kits)) {
        $conv = Test-KitConverted $kit
        if ($conv) { $done++ }
        foreach ($p in $kit.Paths) {
            if ($conv -and $chkSkip.Checked) { Set-Row $p (Tr KitSkip $kit.Name) $ColMuted 1 }
            elseif ($conv) { Set-Row $p (Tr KitBefore $kit.Name) $ColMuted 0 }
            else { Set-Row $p (Tr ReadyKit $kit.Name) $ColText 0 }
        }
    }
    foreach ($p in $script:rows.Keys) {
        if (-not (Test-Export $p)) { Set-Row $p (Tr NotSelected) $ColMuted 0; continue }
        if (Test-Ticked $p) { continue }
        if (Test-Converted $p) {
            $done++
            if ($chkSkip.Checked) { Set-Row $p (Tr SkipConverted) $ColMuted 1 }
            else { Set-Row $p (Tr ConvertedBefore) $ColMuted 0 }
        } else {
            Set-Row $p (Tr Ready) $ColText 0
        }
    }
    $n = $script:rows.Count
    Set-Bar $overallBar 0 $ColWork
    $overallLabel.ForeColor = $ColText
    $overallLabel.Text = if ($n -eq 0) { Tr Nothing }
                         else { (Tr FilesIn $n) + $(if ($done) { Tr AlreadyN $done } else { '' }) }
}

function Update-List {
    $files = Get-InputFiles
    $script:fileKey = ($files | ForEach-Object FullName) -join '|'
    $table.SuspendLayout()
    foreach ($c in @($table.Controls)) { $c.Dispose() }
    $table.Controls.Clear(); $table.RowStyles.Clear(); $table.RowCount = 0
    $script:rows = @{}
    Add-HeaderRow
    foreach ($f in $files) { Add-Row $f }
    $table.ResumeLayout()
    $empty.Visible = ($files.Count -eq 0)
    $table.Visible = ($files.Count -gt 0)
    $btnConvert.Enabled = ($files.Count -gt 0)
    Update-ExportAll
    Update-Statuses
    Start-Thumbnails
}

# ------------------------------------------------------------------ conversion
# a run is a queue of jobs, one Blender each: first all the normal models together, then one job per kit
function Set-Busy($busy) {
    foreach ($c in $numHeight, $cmbTex, $chkPbr, $chkPalette, $chkSkip, $btnRefresh, $btnClear, $cmbLang) { $c.Enabled = -not $busy }
    foreach ($r in $script:rows.Values) { $r.Check.Enabled = -not $busy; $r.Export.Enabled = -not $busy }
    if ($script:exportAll) { $script:exportAll.Enabled = -not $busy }
    $btnConvert.Visible = -not $busy; $btnCancel.Visible = $busy
    if (-not $busy) { $form.Text = 'VoxToRoblox' }
}

function Start-Convert {
    Update-List
    $script:jobs = New-Object System.Collections.ArrayList
    if (-not @($script:rows.Keys | Where-Object { Test-Export $_ }).Count) {
        $overallLabel.ForeColor = $ColErr; $overallLabel.Text = Tr NoneSelected
        return
    }
    $normal = @($script:rows.Keys | Where-Object { (Test-Export $_) -and -not (Test-Ticked $_) -and -not ($chkSkip.Checked -and (Test-Converted $_)) } | Sort-Object)
    if ($normal.Count) { [void]$script:jobs.Add(@{ Kind = 'normal'; Paths = $normal; Units = $normal.Count }) }
    foreach ($kit in @(Get-Kits)) {
        if ($chkSkip.Checked -and (Test-KitConverted $kit)) { continue }
        [void]$script:jobs.Add(@{ Kind = 'kit'; Name = $kit.Name; Paths = $kit.Paths; Out = $kit.Out; Units = 1 })
    }
    if ($script:jobs.Count -eq 0) {
        $overallLabel.Text = Tr AllConverted
        return
    }
    foreach ($j in $script:jobs) {
        foreach ($p in $j.Paths) { Set-Row $p (Tr Waiting) $ColMuted 0; $script:rows[$p].Waiting = $true }
    }
    $script:total = 0
    foreach ($j in $script:jobs) { $script:total += $j.Units }
    $script:base = 0; $script:index = 0; $script:jobIdx = -1
    $script:ok = 0; $script:failed = 0; $script:cancelled = $false; $script:fatal = $null
    $script:watch = [System.Diagnostics.Stopwatch]::StartNew()
    Remove-Item -LiteralPath $LogFile -ErrorAction SilentlyContinue
    Set-Bar $overallBar 0 $ColWork
    Set-Busy $true
    Start-NextJob
}

function Start-NextJob {
    $script:jobIdx++
    $j = $script:jobs[$script:jobIdx]
    $script:job = $j; $script:curRows = @(); $script:ended = $false; $script:offset = 0
    Remove-Item -LiteralPath $ProgFile -ErrorAction SilentlyContinue
    $q = { '"' + $args[0] + '"' }
    $common = @('--height', $numHeight.Value.ToString($Inv), '--tex', $cmbTex.SelectedItem,
                '--progress-file', (& $q $ProgFile), '--log-file', (& $q $LogFile))
    if (-not $chkPbr.Checked) { $common += '--no-pbr' }
    if ($j.Kind -eq 'kit') {
        $argv = @('-b', '--factory-startup', '--python', (& $q $KitScript), '--') + @($j.Paths | ForEach-Object { & $q $_ }) +
                @('--name', $j.Name, '--out', (& $q $j.Out)) + $common
        $overallLabel.Text = Tr StartingKit $j.Name
    } else {
        $argv = @('-b', '--factory-startup', '--python', (& $q $PyScript), '--') + @($j.Paths | ForEach-Object { & $q $_ }) +
                @('--out', (& $q $OutDir)) + $common
        if ($chkPalette.Checked) { $argv += '--palette' }
        $overallLabel.Text = Tr StartingBlender
    }
    $overallLabel.ForeColor = $ColText
    $psi = New-Object System.Diagnostics.ProcessStartInfo($Blender, ($argv -join ' '))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    try {
        $script:proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        $script:proc = $null
        $script:fatal = Tr CannotStart $_.Exception.Message
        Complete-Convert
    }
}

function Set-Overall([double]$frac) {
    $v = if ($script:total) { (($script:index - 1) + $frac) / $script:total } else { 0.0 }
    Set-Bar $overallBar $v
    $form.Text = 'VoxToRoblox - {0}%' -f [int]([double]$overallBar.Tag * 100)
}
function Set-CurRows($text, $color, [double]$frac = -1) { foreach ($p in $script:curRows) { Set-Row $p $text $color $frac } }

function Read-Progress {
    if (-not (Test-Path -LiteralPath $ProgFile)) { return }
    try {
        $fs = [IO.File]::Open($ProgFile, 'Open', 'Read', 'ReadWrite')
    } catch { return }
    try {
        $len = $fs.Length - $script:offset
        if ($len -le 0) { return }
        $bytes = New-Object byte[] $len
        [void]$fs.Seek($script:offset, 'Begin')
        $n = $fs.Read($bytes, 0, $len)
    } finally { $fs.Dispose() }
    $last = [Array]::LastIndexOf($bytes, [byte]10, $n - 1)
    if ($last -lt 0) { return }   # (only complete lines)
    $script:offset += $last + 1
    $kit = ($script:job.Kind -eq 'kit')
    foreach ($line in [Text.Encoding]::UTF8.GetString($bytes, 0, $last + 1) -split "`n") {
        $f = $line.TrimEnd("`r") -split "`t"
        switch ($f[0]) {
            'FILE' {
                $script:index = $script:base + [int]$f[1]
                $script:curRows = @(if ($kit) { $script:job.Paths } else { $f[3] })
                foreach ($p in $script:curRows) { $r = $script:rows[$p]; if ($r) { $r.Waiting = $false } }
                Set-CurRows (Tr Starting) $ColWork 0
                $r = $script:rows[$script:curRows[0]]
                if ($r) { $listBox.ScrollControlIntoView($r.Name) }
                $what = if ($kit) { Tr KitName $script:job.Name } else { [IO.Path]::GetFileName($f[3]) }
                $overallLabel.Text = Tr Converting $script:index $script:total $what
                Set-Overall 0
            }
            'STEP' {
                $frac = [double]::Parse($f[1], $Inv)
                Set-CurRows (Tr-Step $f[2]) $ColWork $frac
                Set-Overall $frac
            }
            'DONE' {
                $script:ok++
                foreach ($p in $script:curRows) { $r = $script:rows[$p]; if ($r) { $r.Done = $true } }
                Set-CurRows ((Tr Done $f[1]) + $(if ($kit) { Tr KitSuffix $script:job.Name } else { '' })) $ColOk 1
                Set-Overall 1
            }
            'ERROR' {
                $script:failed++
                Set-CurRows (Tr Error) $ColErr
                foreach ($p in $script:curRows) { $r = $script:rows[$p]; if ($r) { $tip.SetToolTip($r.Status, $f[1]) } }
            }
            'FATAL' { $script:ended = $true; $script:fatal = $f[1] }
            'END'   { $script:ended = $true }
        }
    }
}

# the current Blender finished: next job, or the end of the run
function Complete-Job {
    $p = $script:proc; $script:proc = $null
    $p.Dispose()
    if (-not $script:ended -and $script:curRows.Count -and -not $script:cancelled) {
        $script:failed++
        Set-CurRows (Tr Stopped) $ColErr
    }
    $script:base += $script:job.Units
    if (-not $script:cancelled -and -not $script:fatal -and $script:jobIdx + 1 -lt $script:jobs.Count) { Start-NextJob }
    else { Complete-Convert }
}

function Complete-Convert {
    $script:watch.Stop()
    $el = $script:watch.Elapsed
    $time = if ($el.TotalMinutes -ge 1) { '{0}m {1}s' -f [int][Math]::Floor($el.TotalMinutes), $el.Seconds } else { '{0}s' -f [int]$el.TotalSeconds }
    foreach ($k in @($script:rows.Keys)) {
        $r = $script:rows[$k]
        if ($r.Waiting -or ($script:cancelled -and $script:curRows -contains $k -and -not $r.Done)) {
            $r.Waiting = $false
            Set-Row $k (Tr NotConverted) $ColMuted 0
        }
    }
    Remove-Item -LiteralPath $ProgFile -ErrorAction SilentlyContinue
    Set-Busy $false
    if ($script:fatal) {
        $overallLabel.ForeColor = $ColErr; $overallLabel.Text = $script:fatal; $script:fatal = $null
        Set-Bar $overallBar 1 $ColErr
    } elseif ($script:cancelled) {
        $overallLabel.ForeColor = $ColMuted; $overallLabel.Text = Tr Cancelled $script:ok $script:total
        Set-Bar $overallBar ([double]$overallBar.Tag) $ColMuted
    } elseif ($script:failed) {
        $overallLabel.ForeColor = $ColErr
        $overallLabel.Text = Tr Failed $script:ok $script:total $script:failed $time
        Set-Bar $overallBar 1 $ColErr
    } else {
        $overallLabel.ForeColor = $ColOk
        $overallLabel.Text = Tr AllDone $script:ok $script:total $time
        Set-Bar $overallBar 1 $ColOk
    }
    [System.Media.SystemSounds]::Asterisk.Play()
    if ($chkOpen.Checked -and $script:ok -gt 0 -and -not $script:cancelled) { Start-Process explorer.exe $OutDir }
}

# empties Output\ to the Recycle Bin (so a mistake can be undone)
function Clear-Output($items) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $failed = 0
    foreach ($it in $items) {
        try {
            if ($it.PSIsContainer) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($it.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($it.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
            }
        } catch { $failed++ }
    }
    Update-Statuses
    if ($failed) {
        $overallLabel.ForeColor = $ColErr
        $overallLabel.Text = Tr ClearFailed $failed
    } else {
        $overallLabel.ForeColor = $ColOk
        $overallLabel.Text = Tr Cleared
    }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    if ($script:thumbProc) { Update-Thumbnails }
    if (-not $script:proc) { return }
    Read-Progress
    if ($script:proc.HasExited) { Read-Progress; Complete-Job }
})

# ------------------------------------------------------------------ events
$btnConvert.Add_Click({ Start-Convert })
$btnCancel.Add_Click({
    if ($script:proc -and -not $script:proc.HasExited) {
        $script:cancelled = $true
        try { $script:proc.Kill() } catch { }
    }
})
$btnRefresh.Add_Click({ Update-List })
$btnInput.Add_Click({ Start-Process explorer.exe $InputDir })
$btnOutput.Add_Click({ Start-Process explorer.exe $OutDir })
$btnClear.Add_Click({
    $items = @(Get-ChildItem -LiteralPath $OutDir -Force -ErrorAction SilentlyContinue)
    if ($items.Count -eq 0) { $overallLabel.ForeColor = $ColText; $overallLabel.Text = Tr OutputEmpty; return }
    $a = [System.Windows.Forms.MessageBox]::Show((Tr ClearAsk $items.Count), 'VoxToRoblox', 'YesNo', 'Warning')
    if ($a -ne 'Yes') { return }
    Clear-Output $items
})
$btnLog.Add_Click({
    if (Test-Path -LiteralPath $LogFile) { Start-Process notepad.exe $LogFile }
    else { $overallLabel.Text = Tr NoLog }
})
$chkSkip.Add_CheckedChanged({ if (-not $script:proc) { Update-Statuses } })
$cmbLang.Add_SelectedIndexChanged({
    $new = @($Languages.Keys)[$cmbLang.SelectedIndex]
    if ($new -eq $script:Lang) { return }
    $script:Lang = $new
    try { Set-Content -LiteralPath $Settings -Value "lang=$new" -Encoding ASCII } catch { }
    Set-Texts
    if (-not $script:proc) { Update-List }
})
$form.Add_Activated({
    # files added to Input while the window was in the background
    if (-not $script:proc -and ((Get-InputFiles | ForEach-Object FullName) -join '|') -ne $script:fileKey) { Update-List }
})
$form.Add_FormClosing({
    param($s, $e)
    if ($script:proc -and -not $script:proc.HasExited) {
        $a = [System.Windows.Forms.MessageBox]::Show((Tr CloseAsk), 'VoxToRoblox', 'YesNo', 'Warning')
        if ($a -ne 'Yes') { $e.Cancel = $true; return }
        try { $script:proc.Kill() } catch { }
    }
    if ($script:thumbProc -and -not $script:thumbProc.HasExited) { try { $script:thumbProc.Kill() } catch { } }
    Remove-Item -LiteralPath $ThumbList, $ProgFile -ErrorAction SilentlyContinue
})

Set-Texts
Update-List
$timer.Start()
[void]$form.ShowDialog()
$timer.Dispose()
