# 按标题找窗口并 MoveWindow 到指定宽高（含边框外尺寸）
import sys, ctypes, time
from ctypes import wintypes

title_key = sys.argv[1] if len(sys.argv) > 1 else 'wanji'
tw = int(sys.argv[2]) if len(sys.argv) > 2 else 1280
th = int(sys.argv[3]) if len(sys.argv) > 3 else 720

u32 = ctypes.windll.user32
found = []
def cb(hwnd, _):
    if not u32.IsWindowVisible(hwnd):
        return True
    buf = ctypes.create_unicode_buffer(256)
    u32.GetWindowTextW(hwnd, buf, 256)
    if title_key in buf.value:
        found.append(hwnd)
    return True
u32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)(cb), 0)
if not found:
    print('NO_WINDOW'); sys.exit(1)
hwnd = found[0]
# 目标外尺寸：按当前窗口的边框增量换算客户区→外框
wr, cr = wintypes.RECT(), wintypes.RECT()
u32.GetWindowRect(hwnd, ctypes.byref(wr))
u32.GetClientRect(hwnd, ctypes.byref(cr))
chrome_w = (wr.right - wr.left) - (cr.right - cr.left)
chrome_h = (wr.bottom - wr.top) - (cr.bottom - cr.top)
u32.MoveWindow(hwnd, wr.left, wr.top, tw + chrome_w, th + chrome_h, True)
time.sleep(0.4)
u32.GetWindowRect(hwnd, ctypes.byref(wr))
u32.GetClientRect(hwnd, ctypes.byref(cr))
print(f'outer={wr.right-wr.left}x{wr.bottom-wr.top} client={cr.right-cr.left}x{cr.bottom-cr.top}')
