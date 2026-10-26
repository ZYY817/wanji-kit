# 直接 PostMessage 点击 Flutter 视图子窗口（不受遮挡/Z序影响）
# winclick3.py <title_key> <client_x> <client_y>
import sys, ctypes, time
from ctypes import wintypes
u32 = ctypes.windll.user32
key, x, y = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
found = []
def cb(hwnd, _):
    if not u32.IsWindowVisible(hwnd):
        return True
    buf = ctypes.create_unicode_buffer(256)
    u32.GetWindowTextW(hwnd, buf, 256)
    if key in buf.value:
        found.append(hwnd)
    return True
u32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)(cb), 0)
hwnd = found[0]
# Flutter 事件目标在 FLUTTERVIEW 子窗口上
child = []
def cb2(h, _):
    c = ctypes.create_unicode_buffer(256)
    u32.GetClassNameW(h, c, 256)
    if 'FLUTTER' in c.value.upper():
        child.append(h)
    return True
u32.EnumChildWindows(hwnd, ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)(cb2), 0)
target = child[0] if child else hwnd
lp = (y << 16) | (x & 0xFFFF)
u32.PostMessageW(target, 0x0200, 0, lp)          # WM_MOUSEMOVE
time.sleep(0.05)
u32.PostMessageW(target, 0x0201, 1, lp)          # WM_LBUTTONDOWN
time.sleep(0.08)
u32.PostMessageW(target, 0x0202, 0, lp)          # WM_LBUTTONUP
print(f'posted click client=({x},{y}) to child={target} (parent={hwnd})')
