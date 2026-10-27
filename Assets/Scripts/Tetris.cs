// Tetris.cs — Unity 6용 테트리스 (스크립트 하나로 완성)
// 사용법: 빈 GameObject를 만들고 이 스크립트를 붙인 뒤 Play를 누르세요.
// 블록, 화면, 점수판(uGUI)을 전부 코드가 알아서 만듭니다. 별도 에셋 필요 없음.
//
// 조작: ←/→ (A/D) 이동 | ↓ (S) 천천히 내리기 | ↑ / X / W 오른쪽 회전 | Z 왼쪽 회전
//       Space 바로 떨어뜨리기 | P / Esc 일시정지 | R 다시 시작

using System.Collections.Generic;
using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

public class Tetris : MonoBehaviour
{
    // ───────── 판 크기 ─────────
    const int W = 10;          // 가로 칸 수
    const int H = 20;          // 보이는 세로 칸 수
    const int HIDDEN = 2;      // 화면 위 숨은 줄 (블록이 나오는 곳)

    int[,] board = new int[W, H + HIDDEN]; // 0 = 빈칸, 1~7 = 블록 종류

    // ───────── 7가지 블록 모양 (0,0 기준 상대 좌표) ─────────
    static readonly Vector2Int[][] Shapes =
    {
        null,
        new[] { new Vector2Int(-1, 0), new Vector2Int(0, 0), new Vector2Int(1, 0), new Vector2Int(2, 0) },  // 1: I
        new[] { new Vector2Int(0, 0),  new Vector2Int(1, 0), new Vector2Int(0, 1), new Vector2Int(1, 1) },  // 2: O
        new[] { new Vector2Int(-1, 0), new Vector2Int(0, 0), new Vector2Int(1, 0), new Vector2Int(0, 1) },  // 3: T
        new[] { new Vector2Int(-1, 0), new Vector2Int(0, 0), new Vector2Int(0, 1), new Vector2Int(1, 1) },  // 4: S
        new[] { new Vector2Int(-1, 1), new Vector2Int(0, 1), new Vector2Int(0, 0), new Vector2Int(1, 0) },  // 5: Z
        new[] { new Vector2Int(-1, 1), new Vector2Int(-1, 0), new Vector2Int(0, 0), new Vector2Int(1, 0) }, // 6: J
        new[] { new Vector2Int(-1, 0), new Vector2Int(0, 0), new Vector2Int(1, 0), new Vector2Int(1, 1) },  // 7: L
    };

    static readonly Color[] Colors =
    {
        Color.clear,
        new Color(0.00f, 0.90f, 0.95f), // I 하늘색
        new Color(0.98f, 0.85f, 0.10f), // O 노랑
        new Color(0.65f, 0.25f, 0.90f), // T 보라
        new Color(0.25f, 0.85f, 0.30f), // S 초록
        new Color(0.95f, 0.25f, 0.25f), // Z 빨강
        new Color(0.20f, 0.40f, 0.95f), // J 파랑
        new Color(0.98f, 0.55f, 0.10f), // L 주황
    };

    static readonly Color EmptyColor = new Color(0.12f, 0.12f, 0.16f);
    static readonly int[] LineScores = { 0, 100, 300, 500, 800 };

    // ───────── 현재 블록 상태 ─────────
    int curType, nextType;
    Vector2Int[] curCells;
    Vector2Int curPos;
    readonly List<int> bag = new List<int>();

    // ───────── 게임 상태 ─────────
    int score, lines, level;
    bool gameOver, paused;
    float fallTimer, moveTimer;
    int moveDir;

    const float DAS = 0.17f;  // 길게 누를 때 첫 반복까지 대기
    const float ARR = 0.05f;  // 반복 이동 간격

    // ───────── 화면 요소 ─────────
    Sprite cellSprite;
    Material spriteMat;
    SpriteRenderer[,] boardCells;
    SpriteRenderer[,] previewCells;
    UnityEngine.UI.Text hudText;
    UnityEngine.UI.Text centerText;

    // ════════════════════════════════════════════
    void Start()
    {
        SetupCamera();
        cellSprite = MakeCellSprite();
        Shader sh = Shader.Find("Sprites/Default");
        if (sh != null) spriteMat = new Material(sh);
        BuildBoardVisuals();
        BuildHud();
        NewGame();
    }

    void Update()
    {
        if (gameOver)
        {
            if (Pressed(Act.Restart)) NewGame();
            Render();
            return;
        }

        if (Pressed(Act.Pause)) paused = !paused;
        if (Pressed(Act.Restart)) { NewGame(); return; }
        if (paused) { Render(); return; }

        HandleHorizontal();

        if (Pressed(Act.RotateCW)) Rotate(true);
        if (Pressed(Act.RotateCCW)) Rotate(false);

        if (Pressed(Act.HardDrop))
        {
            int dropped = 0;
            while (IsValid(curCells, curPos + Vector2Int.down)) { curPos += Vector2Int.down; dropped++; }
            score += dropped * 2;
            LockPiece();
            Render();
            return;
        }

        // 중력
        float interval = Mathf.Max(0.05f, 0.8f - (level - 1) * 0.07f);
        bool soft = Held(Act.SoftDrop);
        if (soft) interval = Mathf.Min(interval, 0.05f);

        fallTimer += Time.deltaTime;
        if (fallTimer >= interval)
        {
            fallTimer = 0f;
            if (IsValid(curCells, curPos + Vector2Int.down))
            {
                curPos += Vector2Int.down;
                if (soft) score += 1;
            }
            else
            {
                LockPiece();
            }
        }

        Render();
    }

    // ───────── 게임 진행 ─────────
    void NewGame()
    {
        System.Array.Clear(board, 0, board.Length);
        score = 0; lines = 0; level = 1;
        gameOver = false; paused = false;
        fallTimer = 0f;
        bag.Clear();
        nextType = DrawFromBag();
        SpawnPiece();
    }

    int DrawFromBag()
    {
        // 7-bag: 7종류를 한 번씩 섞어서 꺼냄 (같은 블록만 계속 나오는 것 방지)
        if (bag.Count == 0)
        {
            for (int i = 1; i <= 7; i++) bag.Add(i);
            for (int i = bag.Count - 1; i > 0; i--)
            {
                int j = Random.Range(0, i + 1);
                (bag[i], bag[j]) = (bag[j], bag[i]);
            }
        }
        int t = bag[0];
        bag.RemoveAt(0);
        return t;
    }

    void SpawnPiece()
    {
        curType = nextType;
        nextType = DrawFromBag();
        curCells = (Vector2Int[])Shapes[curType].Clone();
        curPos = new Vector2Int(4, H - 1);
        fallTimer = 0f;
        if (!IsValid(curCells, curPos)) gameOver = true;
    }

    bool IsValid(Vector2Int[] cells, Vector2Int pos)
    {
        foreach (var c in cells)
        {
            Vector2Int p = pos + c;
            if (p.x < 0 || p.x >= W || p.y < 0 || p.y >= H + HIDDEN) return false;
            if (board[p.x, p.y] != 0) return false;
        }
        return true;
    }

    void Rotate(bool clockwise)
    {
        if (curType == 2) return; // O 블록은 회전해도 똑같음

        var rotated = new Vector2Int[4];
        for (int i = 0; i < 4; i++)
        {
            Vector2Int c = curCells[i];
            rotated[i] = clockwise ? new Vector2Int(c.y, -c.x) : new Vector2Int(-c.y, c.x);
        }

        // 벽에 붙어 있으면 옆으로/위로 살짝 밀어서 회전 시도 (월킥)
        Vector2Int[] kicks =
        {
            new Vector2Int(0, 0), new Vector2Int(-1, 0), new Vector2Int(1, 0),
            new Vector2Int(-2, 0), new Vector2Int(2, 0), new Vector2Int(0, 1),
        };
        foreach (var k in kicks)
        {
            if (IsValid(rotated, curPos + k))
            {
                curCells = rotated;
                curPos += k;
                return;
            }
        }
    }

    void HandleHorizontal()
    {
        int dir = 0;
        if (Held(Act.Left)) dir -= 1;
        if (Held(Act.Right)) dir += 1;

        if (dir == 0) { moveDir = 0; return; }

        if (dir != moveDir)
        {
            moveDir = dir;
            TryMove(dir);
            moveTimer = DAS;
        }
        else
        {
            moveTimer -= Time.deltaTime;
            if (moveTimer <= 0f)
            {
                TryMove(dir);
                moveTimer = ARR;
            }
        }
    }

    void TryMove(int dx)
    {
        var target = curPos + new Vector2Int(dx, 0);
        if (IsValid(curCells, target)) curPos = target;
    }

    void LockPiece()
    {
        foreach (var c in curCells)
        {
            Vector2Int p = curPos + c;
            board[p.x, p.y] = curType;
        }

        int cleared = ClearLines();
        if (cleared > 0)
        {
            score += LineScores[cleared] * level;
            lines += cleared;
            level = lines / 10 + 1;
        }

        // 숨은 줄까지 블록이 쌓이면 게임 오버
        for (int x = 0; x < W; x++)
            for (int y = H; y < H + HIDDEN; y++)
                if (board[x, y] != 0) { gameOver = true; return; }

        SpawnPiece();
    }

    int ClearLines()
    {
        int cleared = 0;
        for (int y = 0; y < H + HIDDEN; y++)
        {
            bool full = true;
            for (int x = 0; x < W; x++)
                if (board[x, y] == 0) { full = false; break; }

            if (!full) continue;

            for (int yy = y; yy < H + HIDDEN - 1; yy++)
                for (int x = 0; x < W; x++)
                    board[x, yy] = board[x, yy + 1];
            for (int x = 0; x < W; x++) board[x, H + HIDDEN - 1] = 0;

            cleared++;
            y--; // 내려온 줄을 다시 검사
        }
        return cleared;
    }

    // ───────── 그리기 ─────────
    void Render()
    {
        for (int x = 0; x < W; x++)
            for (int y = 0; y < H; y++)
                boardCells[x, y].color = board[x, y] == 0 ? EmptyColor : Colors[board[x, y]];

        if (!gameOver)
        {
            // 고스트(떨어질 위치 미리보기)
            Vector2Int ghost = curPos;
            while (IsValid(curCells, ghost + Vector2Int.down)) ghost += Vector2Int.down;
            Color ghostColor = Color.Lerp(EmptyColor, Colors[curType], 0.3f);
            foreach (var c in curCells)
            {
                Vector2Int p = ghost + c;
                if (p.y < H) boardCells[p.x, p.y].color = ghostColor;
            }

            // 현재 블록
            foreach (var c in curCells)
            {
                Vector2Int p = curPos + c;
                if (p.y < H) boardCells[p.x, p.y].color = Colors[curType];
            }
        }

        // 다음 블록 미리보기
        for (int x = 0; x < 4; x++)
            for (int y = 0; y < 4; y++)
                previewCells[x, y].color = Color.clear;
        foreach (var c in Shapes[nextType])
            previewCells[c.x + 1, c.y + 1].color = Colors[nextType];

        hudText.text =
            $"SCORE\n{score}\n\nLINES\n{lines}\n\nLEVEL\n{level}\n\n\n" +
            "<size=22>← → : Move\n↓ : Soft drop\n↑ / X : Rotate R\nZ : Rotate L\n" +
            "Space : Hard drop\nP : Pause\nR : Restart</size>";

        if (gameOver) centerText.text = "GAME OVER\n<size=36>Press R to restart</size>";
        else if (paused) centerText.text = "PAUSED";
        else centerText.text = "";
    }

    // ───────── 화면 만들기 ─────────
    void SetupCamera()
    {
        Camera cam = Camera.main;
        if (cam == null)
        {
            var go = new GameObject("Main Camera");
            go.tag = "MainCamera";
            cam = go.AddComponent<Camera>();
        }
        cam.orthographic = true;
        cam.orthographicSize = H / 2f + 1f;
        cam.transform.position = new Vector3(7f, (H - 1) / 2f, -10f);
        cam.transform.rotation = Quaternion.identity;
        cam.clearFlags = CameraClearFlags.SolidColor;
        cam.backgroundColor = new Color(0.05f, 0.05f, 0.08f);
    }

    Sprite MakeCellSprite()
    {
        const int s = 16;
        var tex = new Texture2D(s, s) { filterMode = FilterMode.Point };
        var px = new Color[s * s];
        for (int y = 0; y < s; y++)
            for (int x = 0; x < s; x++)
            {
                bool edge = x == 0 || y == 0 || x == s - 1 || y == s - 1;
                px[y * s + x] = edge ? new Color(0.65f, 0.65f, 0.65f) : Color.white;
            }
        tex.SetPixels(px);
        tex.Apply();
        return Sprite.Create(tex, new Rect(0, 0, s, s), new Vector2(0.5f, 0.5f), s);
    }

    SpriteRenderer MakeCell(Transform parent, Vector3 pos, int order)
    {
        var go = new GameObject("Cell");
        go.transform.SetParent(parent, false);
        go.transform.localPosition = pos;
        var sr = go.AddComponent<SpriteRenderer>();
        sr.sprite = cellSprite;
        sr.sortingOrder = order;
        if (spriteMat != null) sr.sharedMaterial = spriteMat;
        return sr;
    }

    void BuildBoardVisuals()
    {
        var root = new GameObject("TetrisBoard").transform;
        root.SetParent(transform, false);

        // 판 테두리
        var frame = MakeCell(root, new Vector3((W - 1) / 2f, (H - 1) / 2f, 0f), -1);
        frame.transform.localScale = new Vector3(W + 0.4f, H + 0.4f, 1f);
        frame.color = new Color(0.4f, 0.4f, 0.5f);

        boardCells = new SpriteRenderer[W, H];
        for (int x = 0; x < W; x++)
            for (int y = 0; y < H; y++)
                boardCells[x, y] = MakeCell(root, new Vector3(x, y, 0f), 0);

        // 다음 블록 칸
        Vector3 previewOrigin = new Vector3(W + 2, H - 5, 0f);
        var pFrame = MakeCell(root, previewOrigin + new Vector3(1.5f, 1.5f, 0f), -1);
        pFrame.transform.localScale = new Vector3(4.6f, 4.6f, 1f);
        pFrame.color = new Color(0.15f, 0.15f, 0.2f);

        previewCells = new SpriteRenderer[4, 4];
        for (int x = 0; x < 4; x++)
            for (int y = 0; y < 4; y++)
                previewCells[x, y] = MakeCell(root, previewOrigin + new Vector3(x, y, 0f), 0);
    }

    void BuildHud()
    {
        Font font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");

        var canvasGo = new GameObject("TetrisHUD");
        canvasGo.transform.SetParent(transform, false);
        var canvas = canvasGo.AddComponent<Canvas>();
        canvas.renderMode = RenderMode.ScreenSpaceOverlay;
        var scaler = canvasGo.AddComponent<UnityEngine.UI.CanvasScaler>();
        scaler.uiScaleMode = UnityEngine.UI.CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1920, 1080);
        scaler.matchWidthOrHeight = 0.5f;
        canvasGo.AddComponent<UnityEngine.UI.GraphicRaycaster>();

        // 왼쪽 위 점수판
        hudText = MakeText(canvasGo.transform, "ScoreText", font, 34, TextAnchor.UpperLeft);
        var r = hudText.rectTransform;
        r.anchorMin = r.anchorMax = new Vector2(0f, 1f);
        r.pivot = new Vector2(0f, 1f);
        r.anchoredPosition = new Vector2(60f, -60f);
        r.sizeDelta = new Vector2(420f, 900f);

        // 가운데 메시지 (게임 오버 / 일시정지)
        centerText = MakeText(canvasGo.transform, "CenterText", font, 72, TextAnchor.MiddleCenter);
        var c = centerText.rectTransform;
        c.anchorMin = c.anchorMax = new Vector2(0.5f, 0.5f);
        c.pivot = new Vector2(0.5f, 0.5f);
        c.anchoredPosition = Vector2.zero;
        c.sizeDelta = new Vector2(1000f, 300f);
        var outline = centerText.gameObject.AddComponent<UnityEngine.UI.Outline>();
        outline.effectColor = Color.black;
        outline.effectDistance = new Vector2(3f, -3f);
    }

    UnityEngine.UI.Text MakeText(Transform parent, string name, Font font, int size, TextAnchor align)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent, false);
        var t = go.AddComponent<UnityEngine.UI.Text>();
        t.font = font;
        t.fontSize = size;
        t.alignment = align;
        t.color = Color.white;
        t.supportRichText = true;
        t.horizontalOverflow = HorizontalWrapMode.Overflow;
        t.verticalOverflow = VerticalWrapMode.Overflow;
        return t;
    }

    // ───────── 입력 (새 Input System / 옛 Input Manager 둘 다 지원) ─────────
    enum Act { Left, Right, SoftDrop, RotateCW, RotateCCW, HardDrop, Pause, Restart }

#if ENABLE_INPUT_SYSTEM
    static Key[] KeysFor(Act a)
    {
        switch (a)
        {
            case Act.Left:      return new[] { Key.LeftArrow, Key.A };
            case Act.Right:     return new[] { Key.RightArrow, Key.D };
            case Act.SoftDrop:  return new[] { Key.DownArrow, Key.S };
            case Act.RotateCW:  return new[] { Key.UpArrow, Key.X, Key.W };
            case Act.RotateCCW: return new[] { Key.Z };
            case Act.HardDrop:  return new[] { Key.Space };
            case Act.Pause:     return new[] { Key.P, Key.Escape };
            default:            return new[] { Key.R };
        }
    }

    static bool Pressed(Act a)
    {
        var kb = Keyboard.current;
        if (kb == null) return false;
        foreach (var k in KeysFor(a)) if (kb[k].wasPressedThisFrame) return true;
        return false;
    }

    static bool Held(Act a)
    {
        var kb = Keyboard.current;
        if (kb == null) return false;
        foreach (var k in KeysFor(a)) if (kb[k].isPressed) return true;
        return false;
    }
#else
    static KeyCode[] KeysFor(Act a)
    {
        switch (a)
        {
            case Act.Left:      return new[] { KeyCode.LeftArrow, KeyCode.A };
            case Act.Right:     return new[] { KeyCode.RightArrow, KeyCode.D };
            case Act.SoftDrop:  return new[] { KeyCode.DownArrow, KeyCode.S };
            case Act.RotateCW:  return new[] { KeyCode.UpArrow, KeyCode.X, KeyCode.W };
            case Act.RotateCCW: return new[] { KeyCode.Z };
            case Act.HardDrop:  return new[] { KeyCode.Space };
            case Act.Pause:     return new[] { KeyCode.P, KeyCode.Escape };
            default:            return new[] { KeyCode.R };
        }
    }

    static bool Pressed(Act a)
    {
        foreach (var k in KeysFor(a)) if (Input.GetKeyDown(k)) return true;
        return false;
    }

    static bool Held(Act a)
    {
        foreach (var k in KeysFor(a)) if (Input.GetKey(k)) return true;
        return false;
    }
#endif
}
