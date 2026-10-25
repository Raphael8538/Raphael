# CaptureOCR - 단축키로 화면 영역을 선택하면 글자를 인식해 클립보드에 복사한다.
# Windows PowerShell 5.1 전용 (Windows 내장 OCR 엔진 Windows.Media.Ocr 사용).

# ===== 설정 =====
$HotkeyModifiers = 'Ctrl+Alt'   # Ctrl, Alt, Shift, Win 을 + 로 조합
$HotkeyKey       = 'O'          # System.Windows.Forms.Keys 이름 (예: O, T, F9)
$PreferLanguage  = 'ko'         # 우선 사용할 OCR 언어 (없으면 Windows 사용자 언어)
# ================

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -ne 5) {
    Write-Error 'Windows PowerShell 5.1 (powershell.exe)에서 실행해야 합니다.'
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.Runtime.WindowsRuntime

Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class CaptureOcrHotkey : NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    const int WM_HOTKEY = 0x0312;
    const uint MOD_NOREPEAT = 0x4000;
    public event EventHandler Pressed;

    public CaptureOcrHotkey() { CreateHandle(new CreateParams()); }

    public bool Register(uint mods, uint vk) { return RegisterHotKey(Handle, 1, mods | MOD_NOREPEAT, vk); }

    protected override void WndProc(ref Message m) {
        if (m.Msg == WM_HOTKEY && Pressed != null) Pressed(this, EventArgs.Empty);
        base.WndProc(ref m);
    }

    public void Dispose() { UnregisterHotKey(Handle, 1); DestroyHandle(); }
}

public static class CaptureOcrDpi {
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    // 배율(125%, 150% 등)과 모니터별 배율이 달라도 실제 픽셀 좌표로 캡처하기 위함
    public static void Enable() {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch (EntryPointNotFoundException) { }
        SetProcessDPIAware();
    }
}
'@

[CaptureOcrDpi]::Enable()
[System.Windows.Forms.Application]::EnableVisualStyles()

# ----- 중복 실행 방지 -----
$mutex = New-Object System.Threading.Mutex($false, 'Local\CaptureOCR_SingleInstance')
if (-not $mutex.WaitOne(0)) {
    [System.Windows.Forms.MessageBox]::Show('CaptureOCR가 이미 실행 중입니다.', 'CaptureOCR') | Out-Null
    exit
}

# ----- WinRT OCR 준비 -----
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.FileAccessMode, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]

$asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1

function Wait-WinRt($Operation, [Type]$ResultType) {
    $task = $asTaskGeneric.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $task.Wait(-1) | Out-Null
    $task.Result
}

function New-OcrEngine {
    $lang = [Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages |
        Where-Object { $_.LanguageTag -like "$PreferLanguage*" } | Select-Object -First 1
    if ($lang) { return [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang) }
    [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
}

$ocrEngine = New-OcrEngine
if (-not $ocrEngine) {
    [System.Windows.Forms.MessageBox]::Show(
        "사용할 수 있는 OCR 언어 팩이 없습니다.`n`n설정 > 시간 및 언어 > 언어 및 지역에서 한국어를 추가하거나, install.ps1을 다시 실행해 OCR 팩을 설치하세요.",
        'CaptureOCR', 'OK', 'Error') | Out-Null
    exit 1
}

function Invoke-Ocr([System.Drawing.Bitmap]$Bitmap) {
    # 작은 글씨는 인식률이 떨어지므로 2배 확대 (OCR 최대 크기 안에서)
    $max = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
    $scale = 1
    if ($Bitmap.Width * 2 -le $max -and $Bitmap.Height * 2 -le $max -and ($Bitmap.Width * $Bitmap.Height) -lt 2000000) { $scale = 2 }

    $img = New-Object System.Drawing.Bitmap ($Bitmap.Width * $scale), ($Bitmap.Height * $scale)
    $g = [System.Drawing.Graphics]::FromImage($img)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($Bitmap, 0, 0, $img.Width, $img.Height)
    $g.Dispose()

    $tmp = Join-Path $env:TEMP ("CaptureOCR_{0}.png" -f [guid]::NewGuid())
    $img.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
    $img.Dispose()

    try {
        $file    = Wait-WinRt ([Windows.Storage.StorageFile]::GetFileFromPathAsync($tmp)) ([Windows.Storage.StorageFile])
        $stream  = Wait-WinRt ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
        $decoder = Wait-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $soft    = Wait-WinRt ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $result  = Wait-WinRt ($ocrEngine.RecognizeAsync($soft)) ([Windows.Media.Ocr.OcrResult])
        $soft.Dispose()
        $stream.Dispose()
        ($result.Lines | ForEach-Object { $_.Text }) -join "`r`n"
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

# ----- 영역 선택 오버레이 -----
function Select-ScreenRegion {
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen

    $shot = New-Object System.Drawing.Bitmap $vs.Width, $vs.Height
    $g = [System.Drawing.Graphics]::FromImage($shot)
    $g.CopyFromScreen($vs.Left, $vs.Top, 0, 0, $vs.Size)
    $g.Dispose()

    $dim = New-Object System.Drawing.Bitmap $vs.Width, $vs.Height
    $g = [System.Drawing.Graphics]::FromImage($dim)
    $g.DrawImage($shot, 0, 0, $vs.Width, $vs.Height)
    $shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(110, 0, 0, 0))
    $g.FillRectangle($shade, 0, 0, $vs.Width, $vs.Height)
    $shade.Dispose()
    $g.Dispose()

    $full    = New-Object System.Drawing.Rectangle 0, 0, $vs.Width, $vs.Height
    $primary = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $hintAt  = New-Object System.Drawing.PointF ($primary.Left - $vs.Left + 24), ($primary.Top - $vs.Top + 24)
    $font    = New-Object System.Drawing.Font 'Malgun Gothic', 12
    $pen     = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(0, 162, 255)), 2

    $state = @{ Dragging = $false; Start = [System.Drawing.Point]::Empty; Rect = [System.Drawing.Rectangle]::Empty }

    $form = New-Object System.Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.StartPosition   = 'Manual'
    $form.Bounds          = $vs
    $form.TopMost         = $true
    $form.ShowInTaskbar   = $false
    $form.KeyPreview      = $true
    $form.Cursor          = [System.Windows.Forms.Cursors]::Cross
    [System.Windows.Forms.Form].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($form, $true, $null)

    $form.add_Shown({ $form.Activate() })
    $form.add_KeyDown({ if ($_.KeyCode -eq 'Escape') { $form.DialogResult = 'Cancel' } })

    $form.add_MouseDown({
        if ($_.Button -eq 'Right') { $form.DialogResult = 'Cancel'; return }
        if ($_.Button -ne 'Left') { return }
        $state.Dragging = $true
        $state.Start = $_.Location
    })

    $form.add_MouseMove({
        if (-not $state.Dragging) { return }
        $old = $state.Rect
        $x = [Math]::Min($state.Start.X, $_.X); $y = [Math]::Min($state.Start.Y, $_.Y)
        $w = [Math]::Abs($_.X - $state.Start.X); $h = [Math]::Abs($_.Y - $state.Start.Y)
        $state.Rect = [System.Drawing.Rectangle]::Intersect((New-Object System.Drawing.Rectangle $x, $y, $w, $h), $full)
        $dirty = [System.Drawing.Rectangle]::Union($old, $state.Rect)
        $dirty.Inflate(4, 4)
        $form.Invalidate($dirty)
    })

    $form.add_MouseUp({
        if (-not $state.Dragging) { return }
        $state.Dragging = $false
        if ($state.Rect.Width -gt 3 -and $state.Rect.Height -gt 3) { $form.DialogResult = 'OK' }
        else { $state.Rect = [System.Drawing.Rectangle]::Empty; $form.Invalidate() }
    })

    $form.add_Paint({
        $gr = $_.Graphics
        $gr.DrawImage($dim, $full, $full, [System.Drawing.GraphicsUnit]::Pixel)
        if ($state.Rect.Width -gt 0 -and $state.Rect.Height -gt 0) {
            $gr.DrawImage($shot, $state.Rect, $state.Rect, [System.Drawing.GraphicsUnit]::Pixel)
            $gr.DrawRectangle($pen, $state.Rect)
        }
        else {
            $gr.DrawString('드래그해서 글자 영역을 선택하세요  ·  Esc / 오른쪽 클릭: 취소', $font, [System.Drawing.Brushes]::White, $hintAt)
        }
    })

    $crop = $null
    if ($form.ShowDialog() -eq 'OK') {
        $crop = $shot.Clone($state.Rect, $shot.PixelFormat)
    }

    $form.Dispose(); $pen.Dispose(); $font.Dispose(); $dim.Dispose(); $shot.Dispose()
    $crop
}

function Set-ClipboardText([string]$Text) {
    for ($i = 0; $i -lt 5; $i++) {
        try { [System.Windows.Forms.Clipboard]::SetText($Text); return }
        catch { Start-Sleep -Milliseconds 100 }
    }
    throw '클립보드에 복사하지 못했습니다.'
}

# ----- 트레이 아이콘 -----
function New-TrayIcon {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(0, 120, 215))), 0, 0, 31, 31)
    $f = New-Object System.Drawing.Font 'Segoe UI', 15, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
    $g.DrawString('T', $f, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF 0, 0, 32, 32), $fmt)
    $g.Dispose(); $f.Dispose()
    [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$hotkeyLabel = "$HotkeyModifiers+$HotkeyKey"

$tray = New-Object System.Windows.Forms.NotifyIcon
$tray.Icon = New-TrayIcon
$tray.Text = "CaptureOCR ($hotkeyLabel)"
$tray.Visible = $true

$busy = @{ Value = $false }

$runCapture = {
    if ($busy.Value) { return }
    $busy.Value = $true
    try {
        $bmp = Select-ScreenRegion
        if (-not $bmp) { return }
        try { $text = Invoke-Ocr $bmp } finally { $bmp.Dispose() }

        if ([string]::IsNullOrWhiteSpace($text)) {
            $tray.ShowBalloonTip(2000, 'CaptureOCR', '인식된 글자가 없습니다.', 'Warning')
            return
        }
        Set-ClipboardText $text
        $preview = if ($text.Length -gt 120) { $text.Substring(0, 120) + '…' } else { $text }
        $tray.ShowBalloonTip(2000, '클립보드에 복사했습니다', $preview, 'Info')
    }
    catch {
        $tray.ShowBalloonTip(4000, 'CaptureOCR 오류', $_.Exception.Message, 'Error')
    }
    finally {
        $busy.Value = $false
    }
}

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$null = $menu.Items.Add("영역 캡처 ($hotkeyLabel)", $null, { & $runCapture })
$null = $menu.Items.Add('-')
$null = $menu.Items.Add('종료', $null, { [System.Windows.Forms.Application]::Exit() })
$tray.ContextMenuStrip = $menu
$tray.add_MouseDoubleClick({ & $runCapture })

# ----- 단축키 등록 -----
$modMap = @{ alt = 1; ctrl = 2; control = 2; shift = 4; win = 8 }
$mods = 0
foreach ($m in $HotkeyModifiers -split '\+') { $mods = $mods -bor $modMap[$m.Trim().ToLower()] }
$vk = [int][System.Windows.Forms.Keys]$HotkeyKey

$hotkey = New-Object CaptureOcrHotkey
if (-not $hotkey.Register([uint32]$mods, [uint32]$vk)) {
    $tray.ShowBalloonTip(5000, 'CaptureOCR', "$hotkeyLabel 단축키를 다른 프로그램이 쓰고 있습니다. 트레이 아이콘을 더블클릭해 사용하거나 스크립트 상단에서 단축키를 바꾸세요.", 'Warning')
}
else {
    $tray.ShowBalloonTip(2000, 'CaptureOCR 실행 중', "$hotkeyLabel 로 화면 글자를 복사하세요.", 'Info')
}
$hotkey.add_Pressed({ & $runCapture })

try {
    [System.Windows.Forms.Application]::Run()
}
finally {
    $hotkey.Dispose()
    $tray.Visible = $false
    $tray.Dispose()
    $mutex.ReleaseMutex()
}
