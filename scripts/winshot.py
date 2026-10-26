# 按标题找窗口，PrintWindow 直接渲窗口内容（无视 z-order 遮挡）
import sys, ctypes, time
from ctypes import wintypes
from PIL import Image

title_key = sys.argv[1] if len(sys.argv) > 1 else 'wanji'
out = sys.argv[2] if len(sys.argv) > 2 else 'shot.png'

u32 = ctypes.windll.user32
g32 = ctypes.windll.gdi32

hwnd_found = []
def cb(hwnd, _):
    if not u32.IsWindowVisible(hwnd):
        return True
    buf = ctypes.create_unicode_buffer(256)
    u32.GetWindowTextW(hwnd, buf, 256)
    if title_key in buf.value:
        hwnd_found.append(hwnd)
    return True
u32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)(cb), 0)
if not hwnd_found:
    print('NO_WINDOW'); sys.exit(1)

hwnd = hwnd_found[0]
r = wintypes.RECT()
u32.GetWindowRect(hwnd, ctypes.byref(r))
w, h = r.right - r.left, r.bottom - r.top

hwndDC = u32.GetWindowDC(hwnd)
mfcDC = g32.CreateCompatibleDC(hwndDC)
bmp = g32.CreateCompatibleBitmap(hwndDC, w, h)
g32.SelectObject(mfcDC, bmp)
u32.PrintWindow(hwnd, mfcDC, 2)  # PW_RENDERFULLCONTENT

# bmp → PIL
class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [('biSize', wintypes.DWORD), ('biWidth', wintypes.LONG),
        ('biHeight', wintypes.LONG), ('biPlanes', wintypes.WORD),
        ('biBitCount', wintypes.WORD), ('biCompression', wintypes.DWORD),
        ('biSizeImage', wintypes.DWORD), ('biXPelsPerMeter', wintypes.LONG),
        ('biYPelsPerMeter', wintypes.LONG), ('biClrUsed', wintypes.DWORD),
        ('biClrImportant', wintypes.DWORD)]
bi = BITMAPINFOHEADER()
bi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
bi.biWidth, bi.biHeight, bi.biPlanes, bi.biBitCount, bi.biCompression = w, h, 1, 32, 0
buf = ctypes.create_string_buffer(w * h * 4)
g32.GetDIBits(mfcDC, bmp, 0, h, buf, ctypes.byref(bi), 0)
img = Image.frombuffer('RGBA', (w, h), buf, 'raw', 'BGRA', 0, 1).transpose(Image.FLIP_TOP_BOTTOM)
img.save(out)

g32.DeleteObject(bmp)
g32.DeleteDC(mfcDC)
u32.ReleaseDC(hwnd, hwndDC)
print('saved', out, f'{w}x{h}')
