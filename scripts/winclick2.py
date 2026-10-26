# 真实鼠标点击：winclick2.py <title_key> <client_x> <client_y>
import sys, ctypes, time
from ctypes import wintypes
u32 = ctypes.windll.user32
key, x, y = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
found=[]
def cb(hwnd,_):
    if not u32.IsWindowVisible(hwnd): return True
    buf=ctypes.create_unicode_buffer(256)
    u32.GetWindowTextW(hwnd,buf,256)
    if key in buf.value: found.append(hwnd)
    return True
u32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool,wintypes.HWND,wintypes.LPARAM)(cb),0)
hwnd=found[0]
pt = wintypes.POINT(x,y)
u32.ClientToScreen(hwnd, ctypes.byref(pt))
u32.SetForegroundWindow(hwnd); time.sleep(0.4)
u32.SetCursorPos(pt.x, pt.y); time.sleep(0.2)
u32.mouse_event(0x0002,0,0,0,0); time.sleep(0.06)
u32.mouse_event(0x0004,0,0,0,0)
print(f'clicked screen=({pt.x},{pt.y})')
