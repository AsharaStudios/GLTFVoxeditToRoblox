// Launchers with the logo: they sit in the project root and open a window script from app\, without a console.
//   "Start VoxEdit to Roblox.exe"          -> app\VoxToRoblox.ps1   (GLTF -> Roblox)
//   "Start VoxEdit Project to GLTF.exe"    -> app\ProjectToGltf.ps1 (VoxEdit project -> GLTF), built with /define:PROJECT_TO_GLTF
// Build them from the project root with the C# compiler that comes with Windows:
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /win32icon:app\VoxToRoblox.ico /out:"Start VoxEdit to Roblox.exe" app\Launcher.cs
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /define:PROJECT_TO_GLTF /win32icon:app\VoxEditToGltf.ico /out:"Start VoxEdit Project to GLTF.exe" app\Launcher.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class Launcher
{
#if PROJECT_TO_GLTF
    const string Script = "ProjectToGltf.ps1";
#else
    const string Script = "VoxToRoblox.ps1";
#endif

    [STAThread]
    static void Main()
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "app", Script);
        if (!File.Exists(script))
        {
            MessageBox.Show("app\\" + Script + " was not found next to this program.", "VoxToRoblox",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
            return;
        }
        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = dir;
        Process.Start(psi);
    }
}
