@echo off
cd /d "%~dp0"
if not exist "%~dp0install.ps1" goto notextracted
if not exist "%~dp0CaptureOCR.ps1" goto notextracted
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if errorlevel 1 pause
exit /b

:notextracted
echo.
echo  [!] install.ps1 / CaptureOCR.ps1 not found next to install.bat.
echo      Please EXTRACT the zip first:
echo      right-click CaptureOCR.zip - "Extract All", then run install.bat
echo      inside the extracted capture-ocr folder.
echo.
pause
exit /b 1
