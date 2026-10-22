// "Start VoxEdit to Roblox.exe": opens the VoxToRoblox window (VoxToRoblox.ps1, next to the .exe) without a console.
// It only exists so the launcher can carry the logo. Build it with the C# compiler that comes with Windows:
//   C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /win32icon:VoxToRoblox.ico /out:"Start VoxEdit to Roblox.exe" Launcher.cs
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

static class Launcher
{
    [STAThread]
    static void Main()
    {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "VoxToRoblox.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show("VoxToRoblox.ps1 was not found next to this program.", "VoxToRoblox",
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
