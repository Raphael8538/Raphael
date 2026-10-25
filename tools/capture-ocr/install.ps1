# CaptureOCR 설치: %LOCALAPPDATA%\CaptureOCR 에 복사하고 시작 메뉴·시작프로그램 바로가기를 만든다.
$ErrorActionPreference = 'Stop'

$src  = Split-Path -Parent $MyInvocation.MyCommand.Path
$dest = Join-Path $env:LOCALAPPDATA 'CaptureOCR'
$script = Join-Path $dest 'CaptureOCR.ps1'

Write-Host '== CaptureOCR 설치 ==' -ForegroundColor Cyan

# 1. 파일 복사
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item (Join-Path $src 'CaptureOCR.ps1') $script -Force
Copy-Item (Join-Path $src 'uninstall.ps1') (Join-Path $dest 'uninstall.ps1') -Force
Get-ChildItem $dest | Unblock-File
Write-Host "설치 위치: $dest"

# 2. 한국어 OCR 언어 팩 확인
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$langs = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag }
Write-Host ("사용 가능한 OCR 언어: " + ($langs -join ', '))

if (-not ($langs | Where-Object { $_ -like 'ko*' })) {
    Write-Host '한국어 OCR 팩이 없습니다.' -ForegroundColor Yellow
    $answer = Read-Host '지금 설치할까요? 관리자 권한 창이 뜹니다 (Y/N)'
    if ($answer -match '^[Yy]') {
        $cmd = "Get-WindowsCapability -Online | Where-Object { `$_.Name -like 'Language.OCR*ko-KR*' } | Add-WindowsCapability -Online; Read-Host '완료되었습니다. Enter를 누르세요'"
        Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile', '-Command', $cmd
    }
    else {
        Write-Host '나중에 설정 > 시간 및 언어 > 언어 및 지역에서 한국어를 추가하면 됩니다. (그 전에는 영어 등 다른 언어로 인식)'
    }
}

# 3. 바로가기 생성 (시작 메뉴 + 로그인 시 자동 실행)
$shell = New-Object -ComObject WScript.Shell
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$targets = @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'CaptureOCR.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Startup')) 'CaptureOCR.lnk')
)
foreach ($lnkPath in $targets) {
    $lnk = $shell.CreateShortcut($lnkPath)
    $lnk.TargetPath = $psExe
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$script`""
    $lnk.WorkingDirectory = $dest
    $lnk.WindowStyle = 7
    $lnk.Description = '화면 영역 글자 인식 (Ctrl+Alt+O)'
    $lnk.Save()
}
Write-Host '시작 메뉴와 시작프로그램에 등록했습니다.'

# 4. 실행
Start-Process $psExe -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$script`""
Write-Host ''
Write-Host '설치 완료! 작업 표시줄 트레이에 파란 T 아이콘이 생깁니다.' -ForegroundColor Green
Write-Host 'Ctrl+Alt+O 를 누르고 영역을 드래그하면 글자가 클립보드에 복사됩니다.'
Read-Host 'Enter를 누르면 창이 닫힙니다'
