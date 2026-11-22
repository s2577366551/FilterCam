import io

files = [
    "FilterCam/Camera/CameraService.swift",
    "FilterCam/Camera/CameraServicing.swift",
    "FilterCam/Photo/PhotoLibrarySaver.swift",
    "FilterCam/Photo/Watermark.swift",
    "FilterCam/UI/CameraScreen.swift",
    "FilterCam/UI/CameraViewModel.swift",
    "FilterCam/UI/ShutterButton.swift",
    "FilterCam/UI/TopBar.swift",
    "FilterCam/UI/WatermarkSheet.swift",
    "FilterCam/UI/PhotoPreviewView.swift",
]

for f in files:
    s = io.open(f, encoding="utf-8").read()
    out = []
    i = 0
    n = len(s)
    mode = None
    while i < n:
        c = s[i]
        if mode is None:
            if c == '"':
                mode = "str"
            elif c == "/" and i + 1 < n and s[i + 1] == "/":
                mode = "line"
            elif c == "/" and i + 1 < n and s[i + 1] == "*":
                mode = "block"
                i += 1
            elif c in "{}()[]":
                out.append(c)
            i += 1
        elif mode == "str":
            if c == "\\":
                i += 2
                continue
            if c == '"':
                mode = None
            i += 1
        elif mode == "line":
            if c == "\n":
                mode = None
            i += 1
        else:
            if c == "*" and i + 1 < n and s[i + 1] == "/":
                mode = None
                i += 1
            i += 1
    stack = []
    ok = True
    pairs = {"}": "{", ")": "(", "]": "["}
    for ch in out:
        if ch in "{([":
            stack.append(ch)
        else:
            if not stack or stack.pop() != pairs[ch]:
                ok = False
                break
    print(f, "OK" if ok and not stack else "MISMATCH", len(stack))
