# PostMessage 点击窗口客户区坐标：winclick.py <title_key> <x> <y>
import sys, ctypes, time
from ctypes import wintypes
u32 = ctypes.windll.user32
key, x, y = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
found = []
def cb(hwnd, _):
    if not u32.IsWindowVisible(hwnd): return True
    buf = ctypes.create_unicode_buffer(256)
    u32.GetWindowTextW(hwnd, buf, 256)
    if key in buf.value: found.append(hwnd)
    return True
u32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)(cb), 0)
if not found: print('NO_WINDOW'); sys.exit(1)
hwnd = found[0]
rc = wintypes.RECT(); u32.GetWindowRect(hwnd, ctypes.byref(rc))
cc = wintypes.RECT(); u32.GetClientRect(hwnd, ctypes.byref(cc))
print(f'win=({rc.left},{rc.top},{rc.right},{rc.bottom}) client={cc.right-cc.left}x{cc.bottom-cc.top}')
lp = (y << 16) | (x & 0xFFFF)
u32.PostMessageW(hwnd, 0x0200, 0, lp)  # WM_MOUSEMOVE
time.sleep(0.08)
u32.PostMessageW(hwnd, 0x0201, 1, lp)  # WM_LBUTTONDOWN
time.sleep(0.08)
u32.PostMessageW(hwnd, 0x0202, 0, lp)  # WM_LBUTTONUP
print(f'posted click client=({x},{y})')
