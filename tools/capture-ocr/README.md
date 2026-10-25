# CaptureOCR

단축키를 누르고 화면 영역을 드래그하면 그 안의 글자를 인식해 클립보드에 복사하는 Windows용 프로그램입니다.
Windows에 들어 있는 OCR 엔진을 쓰기 때문에 따로 설치할 것이 없고, 인터넷 없이 동작합니다.

## 설치

1. 이 폴더(`capture-ocr`)를 PC에 내려받습니다.
2. `install.bat`을 더블클릭합니다.
   - 한국어 OCR 팩이 없으면 설치할지 물어봅니다 (관리자 권한 필요).
   - 시작 메뉴와 시작프로그램에 등록되어 로그인할 때마다 자동으로 켜집니다.
3. 작업 표시줄 트레이에 파란 **T** 아이콘이 보이면 준비 완료입니다.

## 사용법

| 동작 | 방법 |
|---|---|
| 글자 캡처 | `Ctrl + Alt + O` → 영역 드래그 → 클립보드에 복사됨 |
| 취소 | `Esc` 또는 마우스 오른쪽 클릭 |
| 단축키 없이 캡처 | 트레이 아이콘 더블클릭 |
| 종료 | 트레이 아이콘 오른쪽 클릭 → 종료 |

## 설정 바꾸기

`%LOCALAPPDATA%\CaptureOCR\CaptureOCR.ps1` 맨 위에서 단축키와 인식 언어를 바꿀 수 있습니다.
수정한 뒤 트레이에서 종료하고 시작 메뉴의 CaptureOCR로 다시 켜면 반영됩니다.

```powershell
$HotkeyModifiers = 'Ctrl+Alt'   # Ctrl, Alt, Shift, Win 조합
$HotkeyKey       = 'O'
$PreferLanguage  = 'ko'         # 'en' 으로 바꾸면 영어 우선
```

## 제거

`uninstall.bat`을 더블클릭합니다.

## 참고

- Windows 10/11, Windows PowerShell 5.1(기본 탑재)에서 동작합니다.
- 글씨가 아주 작으면 인식률이 떨어지므로 자동으로 2배 확대해서 인식합니다.
- 표 구조나 손글씨는 Windows OCR 특성상 정확도가 낮을 수 있습니다.
