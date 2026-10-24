# VoxEdit Project -> GLTF window. Opened by "Start VoxEdit Project to GLTF.exe"; uses only what ships with Windows.
# Lists the VoxEdit projects (.vxr) found in Projects\, turns each one into a GLTF with voxedit_project_to_gltf.py
# (run by Blender's own Python) and writes it to Input\, ready for the "VoxEdit to Roblox" window.
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

$AppDir      = $PSScriptRoot                # (this script, the Python scripts, icons and logs live in app\)
$Root        = Split-Path $AppDir -Parent  # (the launchers, the readmes and Projects / Input live here)
$ProjectsDir = Join-Path $Root 'Projects'
$GltfDir     = Join-Path $Root 'Input'      # (the input of the VoxEdit to Roblox window)
$PyScript    = Join-Path $AppDir 'voxedit_project_to_gltf.py'
$LogFile     = Join-Path $AppDir 'log_projects.txt'
$ProgFile    = Join-Path $env:TEMP "voxtoroblox_projects_progress_$PID.txt"
$JobList     = Join-Path $env:TEMP "voxtoroblox_projects_jobs_$PID.txt"
$AppData     = Join-Path $env:LOCALAPPDATA 'VoxToRoblox'
$Settings    = Join-Path $AppData 'settings.txt'
$OtherTool   = Join-Path $Root 'Start VoxEdit to Roblox.exe'
$WebSite     = 'https://asharastudios.com'
foreach ($d in $ProjectsDir, $GltfDir, $AppData) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

# ------------------------------------------------------------------ languages
$Strings = @{
    en = @{
        BlenderMissing = "Blender was not found.`n`nInstall Blender 4.4 or newer from blender.org, or set its path at the top of app\ProjectToGltf.ps1.`n(Blender's own Python is used to read the VoxEdit projects.)"
        Title = 'VoxEdit Project → GLTF'
        Subtitle = 'Put your VoxEdit project folders (.vxr + .vxm + .vxa) in the Projects folder and press Convert. The GLTF files go to Input.'
        Language = 'Language'
        Skip = 'Skip already converted'; OpenWhenDone = 'Open the Roblox converter when done'
        TipSkip = 'Do not convert projects that already have their GLTF in Input'
        TipOpen = 'Open the VoxEdit to Roblox window when the conversion finishes'
        Empty = "The Projects folder is empty.`nCopy your VoxEdit project folders there (each one with its .vxr), then press Refresh."
        Convert = 'Convert'; Cancel = 'Cancel'; OpenProjects = 'Open Projects'; OpenInput = 'Open Input'
        Refresh = 'Refresh'; OpenLog = 'Open log'; OtherTool = 'GLTF → Roblox'
        TipOther = 'Open the VoxEdit to Roblox window (it converts the GLTF files in Input)'
        Credit = 'Created by Ashara Studios with love'
        ColProject = 'Project'; ColGltf = 'GLTF in Input'; ColAnims = 'Animations'; ColProgress = 'Progress'; ColStatus = 'Status'
        ColExport = 'Export to GLTF'; TipExportCol = 'Tick the projects to convert (click here to tick or untick them all)'
        TipExportRow = 'Export to GLTF: convert this project'; NotSelected = 'Not selected'
        NoneSelected = 'Tick at least one project in the Export to GLTF column'
        Ready = 'Ready'; ConvertedBefore = 'Converted before'; SkipConverted = 'Already converted (skip)'
        Waiting = 'Waiting'; Starting = 'Starting...'; Done = 'Done ({0} s)'
        Error = 'Error - see log'; Stopped = 'Stopped - see log'; NotConverted = 'Not converted'
        Nothing = 'No VoxEdit projects found'; ProjectsIn = '{0} project(s) in Projects'; AlreadyN = ', {0} already converted'
        AllConverted = 'Everything is already converted (untick "Skip already converted" to redo it)'
        StartingPy = 'Starting...'; Converting = 'Converting {0} of {1}: {2}'
        CannotStart = 'Could not start Python: {0}'
        Cancelled = 'Cancelled - {0} of {1} converted'
        Failed = '{0} of {1} converted, {2} failed (see log) - {3}'
        AllDone = 'Done: {0} of {1} converted in {2} - the GLTF files are in Input'
        NoLog = 'There is no log yet: it is created when you convert'
        CloseAsk = 'A conversion is running. Stop it and close?'
        NoOtherTool = 'Start VoxEdit to Roblox.exe was not found next to this program'
    }
    es = @{
        BlenderMissing = "No se encontró Blender.`n`nInstala Blender 4.4 o superior desde blender.org, o pon su ruta al inicio de app\ProjectToGltf.ps1.`n(Se usa el Python que trae Blender para leer los proyectos de VoxEdit.)"
        Title = 'Proyecto VoxEdit → GLTF'
        Subtitle = 'Pon las carpetas de tus proyectos de VoxEdit (.vxr + .vxm + .vxa) en la carpeta Projects y presiona Convertir. Los GLTF quedan en Input.'
        Language = 'Idioma'
        Skip = 'Saltar los ya convertidos'; OpenWhenDone = 'Abrir el conversor a Roblox al terminar'
        TipSkip = 'No convertir los proyectos que ya tienen su GLTF en Input'
        TipOpen = 'Abrir la ventana VoxEdit a Roblox cuando termine la conversión'
        Empty = "La carpeta Projects está vacía.`nCopia ahí las carpetas de tus proyectos de VoxEdit (cada una con su .vxr) y presiona Actualizar."
        Convert = 'Convertir'; Cancel = 'Cancelar'; OpenProjects = 'Abrir Projects'; OpenInput = 'Abrir Input'
        Refresh = 'Actualizar'; OpenLog = 'Ver log'; OtherTool = 'GLTF → Roblox'
        TipOther = 'Abrir la ventana VoxEdit a Roblox (convierte los GLTF de Input)'
        Credit = 'Creado por Ashara Studios con amor'
        ColProject = 'Proyecto'; ColGltf = 'GLTF en Input'; ColAnims = 'Animaciones'; ColProgress = 'Progreso'; ColStatus = 'Estado'
        ColExport = 'Exportar a GLTF'; TipExportCol = 'Marca los proyectos que quieres convertir (clic aquí para marcarlos o desmarcarlos todos)'
        TipExportRow = 'Exportar a GLTF: convertir este proyecto'; NotSelected = 'No seleccionado'
        NoneSelected = 'Marca al menos un proyecto en la columna Exportar a GLTF'
        Ready = 'Listo para convertir'; ConvertedBefore = 'Convertido antes'; SkipConverted = 'Ya convertido (se salta)'
        Waiting = 'En espera'; Starting = 'Iniciando...'; Done = 'Terminado ({0} s)'
        Error = 'Error - ver log'; Stopped = 'Se detuvo - ver log'; NotConverted = 'No convertido'
        Nothing = 'No se encontraron proyectos de VoxEdit'; ProjectsIn = '{0} proyecto(s) en Projects'; AlreadyN = ', {0} ya convertido(s)'
        AllConverted = 'Todo ya está convertido (desmarca "Saltar los ya convertidos" para repetirlo)'
        StartingPy = 'Iniciando...'; Converting = 'Convirtiendo {0} de {1}: {2}'
        CannotStart = 'No se pudo iniciar Python: {0}'
        Cancelled = 'Cancelado - {0} de {1} convertidos'
        Failed = '{0} de {1} convertidos, {2} con error (ver log) - {3}'
        AllDone = 'Listo: {0} de {1} convertidos en {2} - los GLTF están en Input'
        NoLog = 'Todavía no hay log: se crea al convertir'
        CloseAsk = 'Hay una conversión en curso. ¿Detenerla y cerrar?'
        NoOtherTool = 'No se encontró Start VoxEdit to Roblox.exe junto a este programa'
    }
}
$StepsEs = @{
    'Reading rig' = 'Leyendo el rig'; 'Reading animations' = 'Leyendo animaciones'; 'Building models' = 'Armando modelos'
    'Building animations' = 'Armando animaciones'; 'Writing GLTF' = 'Escribiendo GLTF'
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
    if ($Lang -eq 'es' -and $StepsEs.ContainsKey($label)) { return $StepsEs[$label] }
    $label
}

# Blender's own Python (it has numpy): <Blender folder>\<version>\python\bin\python.exe
if (-not (Test-Path -LiteralPath $Blender)) {
    $Blender = Get-ChildItem -LiteralPath "$env:ProgramFiles\Blender Foundation" -Directory -ErrorAction SilentlyContinue |
        Sort-Object { if ($_.Name -match '(\d+)\.(\d+)') { [int]$Matches[1] * 1000 + [int]$Matches[2] } else { 0 } } -Descending |
        ForEach-Object { Join-Path $_.FullName 'blender.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
$Python = $null
if ($Blender) {
    $Python = Get-ChildItem -LiteralPath (Split-Path $Blender) -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+\.\d+$' } | Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'python\bin\python.exe' } |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Python) {
    [void][System.Windows.Forms.MessageBox]::Show((Tr BlenderMissing), 'VoxToRoblox', 'OK', 'Error')
    return
}

# ------------------------------------------------------------------ look (dark, same as VoxToRoblox.ps1)
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
function New-Check($checked) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Checked = $checked; $c.AutoSize = $true
    $c.FlatStyle = 'Flat'; $c.ForeColor = $ColText; $c.FlatAppearance.BorderColor = $ColMuted
    $c.Margin = New-Object System.Windows.Forms.Padding(0, (Px 4), (Px 18), 0)
    $c
}

# ------------------------------------------------------------------ window
$form = New-Object System.Windows.Forms.Form
$form.Font = $Font
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size((Px 900), (Px 590))
$form.MinimumSize = New-Object System.Drawing.Size((Px 680), (Px 440))
$form.BackColor = $ColBg; $form.ForeColor = $ColText
$LogoFile = Join-Path $AppDir 'VoxEditToGltf.ico'
$Logo = $null
try {
    $form.Icon = New-Object System.Drawing.Icon($LogoFile)
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
$title = New-Label ''; $title.Font = $FontTitle; $title.Margin = New-Object System.Windows.Forms.Padding(0)
$titleRow.Controls.Add($title)
$sub = New-Label '' $ColMuted
$sub.Margin = New-Object System.Windows.Forms.Padding(0, (Px 4), 0, 0)
$sub.MaximumSize = New-Object System.Drawing.Size((Px 700), 0)
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
$chkSkip = New-Check $false
$chkOpen = New-Check $false
$opts.Controls.AddRange(@($chkSkip, $chkOpen))
$main.Controls.Add($opts, 0, 1)

# project list
$listBox = New-Object System.Windows.Forms.Panel
$listBox.Dock = 'Fill'; $listBox.AutoScroll = $true; $listBox.BackColor = $ColSurface
$listBox.Margin = New-Object System.Windows.Forms.Padding(0, (Px 12), 0, 0)
$table = New-Object System.Windows.Forms.TableLayoutPanel
$table.Dock = 'Top'; $table.AutoSize = $true; $table.AutoSizeMode = 'GrowAndShrink'; $table.ColumnCount = 7
$table.Padding = New-Object System.Windows.Forms.Padding((Px 8), (Px 4), (Px 12), (Px 6))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('AutoSize')))
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', (Px 60))))
foreach ($w in 30, 24) { [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', $w))) }
[void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute', (Px 86))))
foreach ($w in 22, 24) { [void]$table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent', $w))) }
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
$btnConvert  = New-Button -Primary
$btnCancel   = New-Button; $btnCancel.Visible = $false
$btnOther    = New-Button
$btnInput    = New-Button
$btnProjects = New-Button
$btnRefresh  = New-Button
$btnLog      = New-Button
$btns.Controls.AddRange(@($btnConvert, $btnCancel, $btnOther, $btnInput, $btnProjects, $btnRefresh, $btnLog))
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

function Set-Texts {
    $form.Text = Tr Title; $title.Text = Tr Title
    $sub.Text = Tr Subtitle; $lblLang.Text = Tr Language
    $chkSkip.Text = Tr Skip; $chkOpen.Text = Tr OpenWhenDone
    $tip.SetToolTip($chkSkip, (Tr TipSkip)); $tip.SetToolTip($chkOpen, (Tr TipOpen))
    $empty.Text = Tr Empty
    $btnConvert.Text = Tr Convert; $btnCancel.Text = Tr Cancel; $btnOther.Text = Tr OtherTool
    $btnInput.Text = Tr OpenInput; $btnProjects.Text = Tr OpenProjects; $btnRefresh.Text = Tr Refresh; $btnLog.Text = Tr OpenLog
    $tip.SetToolTip($btnOther, (Tr TipOther))
    $credit.Text = Tr Credit
    $at = $credit.Text.IndexOf('Ashara Studios')
    if ($at -ge 0) { $credit.LinkArea = New-Object System.Windows.Forms.LinkArea($at, 14) }
}

$form.Add_HandleCreated({
    if (-not $Native) { return }
    $on = 1
    if ([VoxToRoblox.Native]::DwmSetWindowAttribute($form.Handle, 20, [ref]$on, 4) -ne 0) {
        [void][VoxToRoblox.Native]::DwmSetWindowAttribute($form.Handle, 19, [ref]$on, 4)
    }
})
$listBox.Add_HandleCreated({ if ($Native) { [void][VoxToRoblox.Native]::SetWindowTheme($listBox.Handle, 'DarkMode_Explorer', $null) } })

# ------------------------------------------------------------------ project list
$script:rows = @{}           # vxr path -> @{ Export; Out; Name; Bar; Status; Waiting; Done }
$script:exportChoice = @{}   # vxr path -> unticked in the Export to GLTF column (everything is ticked by default)
$script:fileKey = ''
$script:proc = $null

$Placeholder = New-Object System.Drawing.Bitmap((Px 48), (Px 48))
& {
    $gr = [System.Drawing.Graphics]::FromImage($Placeholder)
    $gr.SmoothingMode = 'AntiAlias'; $gr.Clear($ColControl)
    $pen = New-Object System.Drawing.Pen($ColMuted, [float](Px 1.5))
    $w = $Placeholder.Width; $c = $w / 2; $r = $w * 0.26
    $p = { param($x, $y) New-Object System.Drawing.PointF([float]$x, [float]$y) }
    $top = & $p $c ($c - $r); $mid = & $p $c $c; $bot = & $p $c ($c + $r)
    $lt = & $p ($c - $r * 0.87) ($c - $r / 2); $rt = & $p ($c + $r * 0.87) ($c - $r / 2)
    $lb = & $p ($c - $r * 0.87) ($c + $r / 2); $rb = & $p ($c + $r * 0.87) ($c + $r / 2)
    $gr.DrawPolygon($pen, [System.Drawing.PointF[]]@($top, $rt, $rb, $bot, $lb, $lt))
    $gr.DrawLines($pen, [System.Drawing.PointF[]]@($lt, $mid, $rt)); $gr.DrawLine($pen, $mid, $bot)
    $pen.Dispose(); $gr.Dispose()
}
$script:imgCache = @{}
function Read-Image($path) {
    if (-not $script:imgCache.ContainsKey($path)) {
        $ms = New-Object System.IO.MemoryStream(, [IO.File]::ReadAllBytes($path))
        $script:imgCache[$path] = [System.Drawing.Image]::FromStream($ms)
    }
    $script:imgCache[$path]
}

function Get-Projects {
    @(Get-ChildItem -LiteralPath $ProjectsDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.vxr' } | Sort-Object FullName)
}
# GLTF name: the project folder's name (a folder with several rigs: "<folder> - <rig>"; a rig loose in Projects: its own name)
function Get-GltfName($vxr) {
    $dir = $vxr.Directory
    if ($dir.FullName.TrimEnd('\') -eq $ProjectsDir.TrimEnd('\')) { return $vxr.BaseName + '.gltf' }
    $rigs = @(Get-ChildItem -LiteralPath $dir.FullName -File | Where-Object { $_.Extension -eq '.vxr' })
    if ($rigs.Count -le 1) { return $dir.Name + '.gltf' }
    $dir.Name + ' - ' + $vxr.BaseName + '.gltf'
}
function Get-AnimCount($vxr) {
    @(Get-ChildItem -LiteralPath $vxr.DirectoryName -File | Where-Object { $_.Extension -eq '.vxa' -and $_.Name.StartsWith($vxr.BaseName + '.') }).Count
}

function Set-Row($path, $text, $color, [double]$frac = -1) {
    $r = $script:rows[$path]
    if (-not $r) { return }
    $r.Status.Text = $text; $r.Status.ForeColor = $color
    Set-Bar $r.Bar $(if ($frac -ge 0) { $frac } else { [double]$r.Bar.Tag }) $color
}

function Add-HeaderRow {
    $table.RowCount = 1
    [void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    # "Export to GLTF" header: a check box that ticks / unticks every project
    $all = New-Object System.Windows.Forms.CheckBox
    $all.Text = Tr ColExport; $all.AutoSize = $true; $all.Anchor = 'None'; $all.Font = $FontSmall
    $all.FlatStyle = 'Flat'; $all.ForeColor = $ColMuted; $all.FlatAppearance.BorderColor = $ColMuted
    $all.Margin = New-Object System.Windows.Forms.Padding(0, (Px 4), (Px 6), (Px 2))
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
    foreach ($h in '', (Tr ColProject), (Tr ColGltf), (Tr ColAnims), (Tr ColProgress), (Tr ColStatus)) {
        $l = New-Label $h $ColMuted
        $l.Font = $FontSmall; $l.Margin = New-Object System.Windows.Forms.Padding((Px 3), (Px 4), 0, (Px 2))
        if ($i -eq 5) { $l.Margin = New-Object System.Windows.Forms.Padding((Px 8), (Px 4), 0, (Px 2)) }
        $table.Controls.Add($l, $i, 0); $i++
    }
}

# the header box shows ticked only when every project is ticked
function Update-ExportAll {
    if (-not $script:exportAll) { return }
    $script:exportAll.Checked = (@($script:rows.Values | Where-Object { -not $_.Export.Checked }).Count -eq 0)
}
function Test-Export($path) { $r = $script:rows[$path]; $r -and $r.Export.Checked }

function New-Cell($text, $color = $ColText) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.ForeColor = $color
    $l.AutoEllipsis = $true; $l.Dock = 'Fill'; $l.TextAlign = 'MiddleLeft'; $l.Height = Px 32
    $l
}

function Add-Row($vxr) {
    $i = $table.RowCount
    $table.RowCount = $i + 1
    [void]$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('AutoSize')))
    $exp = New-Object System.Windows.Forms.CheckBox
    $exp.AutoSize = $true; $exp.Anchor = 'None'; $exp.FlatStyle = 'Flat'
    $exp.FlatAppearance.BorderColor = $ColMuted; $exp.ForeColor = $ColText
    $exp.Checked = -not ($script:exportChoice.ContainsKey($vxr.FullName) -and -not $script:exportChoice[$vxr.FullName])
    $exp.Tag = $vxr.FullName
    $tip.SetToolTip($exp, (Tr TipExportRow))
    $exp.Add_CheckedChanged({
        if ($script:bulk) { return }
        $script:exportChoice[$this.Tag] = $this.Checked
        Update-ExportAll
        if (-not $script:proc) { Update-Statuses }
    })
    $pic = New-Object System.Windows.Forms.PictureBox
    $pic.Size = New-Object System.Drawing.Size((Px 48), (Px 48)); $pic.SizeMode = 'Zoom'; $pic.Anchor = 'None'
    $pic.Margin = New-Object System.Windows.Forms.Padding(0, (Px 2), 0, (Px 2))
    $shot = $vxr.FullName + '.png'   # (VoxEdit saves a screenshot of the rig next to it)
    $pic.Image = $Placeholder
    if (Test-Path -LiteralPath $shot) { try { $pic.Image = Read-Image $shot } catch { } }
    $rel = $vxr.FullName.Substring($ProjectsDir.Length).TrimStart('\')
    $name = New-Cell $rel
    $tip.SetToolTip($name, $vxr.FullName)
    $outName = Get-GltfName $vxr
    $gl = New-Cell $outName $ColMuted
    $tip.SetToolTip($gl, (Join-Path $GltfDir $outName))
    $an = New-Cell ([string](Get-AnimCount $vxr)) $ColMuted
    $bar = New-Bar (Px 6)
    $bar.Anchor = 'Left, Right'
    $bar.Margin = New-Object System.Windows.Forms.Padding((Px 8), 0, (Px 14), 0)
    $st = New-Cell ''
    $table.Controls.Add($exp, 0, $i); $table.Controls.Add($pic, 1, $i); $table.Controls.Add($name, 2, $i)
    $table.Controls.Add($gl, 3, $i); $table.Controls.Add($an, 4, $i); $table.Controls.Add($bar, 5, $i); $table.Controls.Add($st, 6, $i)
    $script:rows[$vxr.FullName] = @{ Export = $exp; Out = (Join-Path $GltfDir $outName); Name = $name; Bar = $bar; Status = $st; Waiting = $false; Done = $false }
}

function Test-Converted($path) { Test-Path -LiteralPath $script:rows[$path].Out }

function Update-Statuses {
    $done = 0
    foreach ($p in $script:rows.Keys) {
        if (-not (Test-Export $p)) { Set-Row $p (Tr NotSelected) $ColMuted 0; continue }
        if (Test-Converted $p) {
            $done++
            if ($chkSkip.Checked) { Set-Row $p (Tr SkipConverted) $ColMuted 1 } else { Set-Row $p (Tr ConvertedBefore) $ColMuted 0 }
        } else {
            Set-Row $p (Tr Ready) $ColText 0
        }
    }
    $n = $script:rows.Count
    Set-Bar $overallBar 0 $ColWork
    $overallLabel.ForeColor = $ColText
    $overallLabel.Text = if ($n -eq 0) { Tr Nothing } else { (Tr ProjectsIn $n) + $(if ($done) { Tr AlreadyN $done } else { '' }) }
}

function Update-List {
    $files = Get-Projects
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
}

# ------------------------------------------------------------------ conversion (one Python for all the projects)
function Set-Busy($busy) {
    foreach ($c in $chkSkip, $btnRefresh, $cmbLang) { $c.Enabled = -not $busy }
    foreach ($r in $script:rows.Values) { $r.Export.Enabled = -not $busy }
    if ($script:exportAll) { $script:exportAll.Enabled = -not $busy }
    $btnConvert.Visible = -not $busy; $btnCancel.Visible = $busy
    if (-not $busy) { $form.Text = Tr Title }
}

function Start-Convert {
    Update-List
    if (-not @($script:rows.Keys | Where-Object { Test-Export $_ }).Count) {
        $overallLabel.ForeColor = $ColErr; $overallLabel.Text = Tr NoneSelected
        return
    }
    $todo = @($script:rows.Keys | Where-Object { (Test-Export $_) -and -not ($chkSkip.Checked -and (Test-Converted $_)) } | Sort-Object)
    if ($todo.Count -eq 0) { $overallLabel.Text = Tr AllConverted; return }
    foreach ($p in $todo) { Set-Row $p (Tr Waiting) $ColMuted 0; $script:rows[$p].Waiting = $true }
    [IO.File]::WriteAllLines($JobList, [string[]]@($todo | ForEach-Object { "$_`t$($script:rows[$_].Out)" }), (New-Object System.Text.UTF8Encoding($false)))
    Remove-Item -LiteralPath $ProgFile, $LogFile -ErrorAction SilentlyContinue
    $script:total = $todo.Count; $script:index = 0; $script:ok = 0; $script:failed = 0
    $script:current = $null; $script:ended = $false; $script:cancelled = $false; $script:offset = 0
    $script:watch = [System.Diagnostics.Stopwatch]::StartNew()
    $overallLabel.ForeColor = $ColText; $overallLabel.Text = Tr StartingPy
    Set-Bar $overallBar 0 $ColWork
    Set-Busy $true
    $psi = New-Object System.Diagnostics.ProcessStartInfo($Python,
        ('-I "{0}" --list "{1}" --progress-file "{2}" --log-file "{3}"' -f $PyScript, $JobList, $ProgFile, $LogFile))
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    try {
        $script:proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        $script:proc = $null
        Set-Busy $false
        $overallLabel.ForeColor = $ColErr; $overallLabel.Text = Tr CannotStart $_.Exception.Message
    }
}

function Set-Overall([double]$frac) {
    $v = if ($script:total) { (($script:index - 1) + $frac) / $script:total } else { 0.0 }
    Set-Bar $overallBar $v
    $form.Text = '{0} - {1}%' -f (Tr Title), [int]([double]$overallBar.Tag * 100)
}

function Read-Progress {
    if (-not (Test-Path -LiteralPath $ProgFile)) { return }
    try { $fs = [IO.File]::Open($ProgFile, 'Open', 'Read', 'ReadWrite') } catch { return }
    try {
        $len = $fs.Length - $script:offset
        if ($len -le 0) { return }
        $bytes = New-Object byte[] $len
        [void]$fs.Seek($script:offset, 'Begin')
        $n = $fs.Read($bytes, 0, $len)
    } finally { $fs.Dispose() }
    $last = [Array]::LastIndexOf($bytes, [byte]10, $n - 1)
    if ($last -lt 0) { return }
    $script:offset += $last + 1
    foreach ($line in [Text.Encoding]::UTF8.GetString($bytes, 0, $last + 1) -split "`n") {
        $f = $line.TrimEnd("`r") -split "`t"
        switch ($f[0]) {
            'FILE' {
                $script:index = [int]$f[1]; $script:current = $f[3]
                $r = $script:rows[$script:current]
                if ($r) { $r.Waiting = $false; $listBox.ScrollControlIntoView($r.Name) }
                Set-Row $script:current (Tr Starting) $ColWork 0
                $overallLabel.Text = Tr Converting $script:index $script:total ([IO.Path]::GetFileName($script:current))
                Set-Overall 0
            }
            'STEP' {
                $frac = [double]::Parse($f[1], $Inv)
                Set-Row $script:current (Tr-Step $f[2]) $ColWork $frac
                Set-Overall $frac
            }
            'DONE' {
                $script:ok++
                $r = $script:rows[$script:current]; if ($r) { $r.Done = $true }
                Set-Row $script:current (Tr Done $f[1]) $ColOk 1
                Set-Overall 1
            }
            'ERROR' {
                $script:failed++
                Set-Row $script:current (Tr Error) $ColErr
                $r = $script:rows[$script:current]; if ($r) { $tip.SetToolTip($r.Status, $f[1]) }
            }
            'END' { $script:ended = $true }
        }
    }
}

function Complete-Convert {
    $p = $script:proc; $script:proc = $null
    $p.Dispose()
    $script:watch.Stop()
    $el = $script:watch.Elapsed
    $time = if ($el.TotalMinutes -ge 1) { '{0}m {1}s' -f [int][Math]::Floor($el.TotalMinutes), $el.Seconds } else { '{0}s' -f [int]$el.TotalSeconds }
    if (-not $script:ended -and $script:current -and -not $script:cancelled -and -not $script:rows[$script:current].Done) {
        $script:failed++
        Set-Row $script:current (Tr Stopped) $ColErr
    }
    foreach ($k in @($script:rows.Keys)) {
        $r = $script:rows[$k]
        if ($r.Waiting -or ($script:cancelled -and $k -eq $script:current -and -not $r.Done)) {
            $r.Waiting = $false
            Set-Row $k (Tr NotConverted) $ColMuted 0
        }
    }
    Remove-Item -LiteralPath $ProgFile, $JobList -ErrorAction SilentlyContinue
    Set-Busy $false
    if ($script:cancelled) {
        $overallLabel.ForeColor = $ColMuted; $overallLabel.Text = Tr Cancelled $script:ok $script:total
        Set-Bar $overallBar ([double]$overallBar.Tag) $ColMuted
    } elseif ($script:failed) {
        $overallLabel.ForeColor = $ColErr; $overallLabel.Text = Tr Failed $script:ok $script:total $script:failed $time
        Set-Bar $overallBar 1 $ColErr
    } else {
        $overallLabel.ForeColor = $ColOk; $overallLabel.Text = Tr AllDone $script:ok $script:total $time
        Set-Bar $overallBar 1 $ColOk
    }
    [System.Media.SystemSounds]::Asterisk.Play()
    if ($chkOpen.Checked -and $script:ok -gt 0 -and -not $script:cancelled) { Open-OtherTool }
}

function Open-OtherTool {
    if (Test-Path -LiteralPath $OtherTool) { Start-Process -FilePath $OtherTool -WorkingDirectory $Root }
    else { $overallLabel.ForeColor = $ColErr; $overallLabel.Text = Tr NoOtherTool }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    if (-not $script:proc) { return }
    Read-Progress
    if ($script:proc.HasExited) { Read-Progress; Complete-Convert }
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
$btnProjects.Add_Click({ Start-Process explorer.exe $ProjectsDir })
$btnInput.Add_Click({ Start-Process explorer.exe $GltfDir })
$btnOther.Add_Click({ Open-OtherTool })
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
    if (-not $script:proc -and ((Get-Projects | ForEach-Object FullName) -join '|') -ne $script:fileKey) { Update-List }
})
$form.Add_FormClosing({
    param($s, $e)
    if ($script:proc -and -not $script:proc.HasExited) {
        $a = [System.Windows.Forms.MessageBox]::Show((Tr CloseAsk), 'VoxToRoblox', 'YesNo', 'Warning')
        if ($a -ne 'Yes') { $e.Cancel = $true; return }
        try { $script:proc.Kill() } catch { }
    }
    Remove-Item -LiteralPath $ProgFile, $JobList -ErrorAction SilentlyContinue
})

Set-Texts
Update-List
$timer.Start()
[void]$form.ShowDialog()
$timer.Dispose()
