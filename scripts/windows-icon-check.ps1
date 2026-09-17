param([Parameter(Mandatory=$true)][string]$Bundle, [Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference = 'Stop'
# Run only on an ephemeral Windows build runner. Never inspect other windows.
New-Item -ItemType Directory -Force $Output | Out-Null
$Output = (Resolve-Path $Output).Path
$installer = (Get-ChildItem "$Bundle/nsis/*-setup.exe" | Select-Object -First 1).FullName
$install = Join-Path $Output 'installed'
$setup = Start-Process $installer -ArgumentList @('/S', "/D=$install") -Wait -PassThru
if ($setup.ExitCode -ne 0) { throw "Installer failed: $($setup.ExitCode)" }
$exe = Join-Path $install 'linger-client.exe'
python scripts/package-icons.py --pe $installer --pe $exe --pe (Join-Path $install 'uninstall.exe')
if ($LASTEXITCODE -ne 0) { throw 'Packaged Windows icon mismatch' }

# The MSI must contain the same executable, not a separately stale build.
$msi = (Get-ChildItem "$Bundle/msi/*.msi" | Select-Object -First 1).FullName
$msiRoot = Join-Path $Output 'msi'
$extract = Start-Process msiexec.exe -ArgumentList @('/a', "`"$msi`"", '/qn', "TARGETDIR=`"$msiRoot`"") -Wait -PassThru
if ($extract.ExitCode -ne 0) { throw "MSI extraction failed: $($extract.ExitCode)" }
$msiExe = Get-ChildItem $msiRoot -Recurse -Filter linger-client.exe | Select-Object -First 1
if (!$msiExe -or (Get-FileHash $exe).Hash -ne (Get-FileHash $msiExe.FullName).Hash) { throw 'MSI executable differs' }

$shell = New-Object -ComObject WScript.Shell
$shortcuts = @()
foreach ($folder in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop'))) {
    foreach ($file in Get-ChildItem $folder -Filter '*linger*.lnk' -Recurse) {
        $shortcut = $shell.CreateShortcut($file.FullName)
        if ($shortcut.TargetPath -eq $exe) {
            if ($shortcut.IconLocation -and $shortcut.IconLocation -notlike "$exe,*") { throw 'Shortcut uses another icon' }
            $shortcuts += $file.Name
        }
    }
}
if ($shortcuts.Count -eq 0) { throw 'No installed Linger shortcut points to the packaged executable' }
Write-Output 'PASS installed shortcut identity and MSI executable'

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LingerIconProbe {
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", EntryPoint="GetClassLongPtrW")] public static extern IntPtr GetClassLongPtr(IntPtr h, int i);
}
'@
$app = Start-Process $exe -PassThru
try {
    for ($i = 0; $i -lt 100; $i++) {
        Start-Sleep -Milliseconds 200
        $app.Refresh()
        if ($app.HasExited) { throw 'Installed app exited before opening a window' }
        if ($app.MainWindowHandle -ne [IntPtr]::Zero) { break }
    }
    if ($app.MainWindowHandle -eq [IntPtr]::Zero) { throw 'Installed app did not open a window' }
    $icon = [LingerIconProbe]::SendMessage($app.MainWindowHandle, 0x7F, [IntPtr]1, [IntPtr]::Zero)
    if ($icon -eq [IntPtr]::Zero) { $icon = [LingerIconProbe]::GetClassLongPtr($app.MainWindowHandle, -14) }
    if ($icon -eq [IntPtr]::Zero) { throw 'Running app has no window/taskbar icon' }
    $bitmap = [System.Drawing.Icon]::FromHandle($icon).ToBitmap()
    $bitmap.Save((Join-Path $Output 'running-window-icon.png'))
    $bitmap.Dispose()
    Write-Output 'PASS running window supplies an icon; inspect running-window-icon.png for appearance'
} finally {
    if (!$app.HasExited) { Stop-Process -Id $app.Id }
}
