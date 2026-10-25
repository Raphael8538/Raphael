# CaptureOCR 제거
$ErrorActionPreference = 'SilentlyContinue'

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*CaptureOCR.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'CaptureOCR.lnk')
Remove-Item (Join-Path ([Environment]::GetFolderPath('Startup')) 'CaptureOCR.lnk')
Remove-Item (Join-Path $env:LOCALAPPDATA 'CaptureOCR') -Recurse -Force

Write-Host 'CaptureOCR를 제거했습니다.'
Read-Host 'Enter를 누르면 창이 닫힙니다'
