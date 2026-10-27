# 连续 PrintWindow 截帧拼 GIF：python gifshot.py <标题关键词> <输出.gif> <秒数> [帧间隔ms]
import sys, ctypes, time
from ctypes import wintypes
from PIL import Image

title_key = sys.argv[1] if len(sys.argv) > 1 else 'wanji'
out = sys.argv[2] if len(sys.argv) > 2 else 'demo.gif'
secs = float(sys.argv[3]) if len(sys.argv) > 3 else 12
interval = float(sys.argv[4]) if len(sys.argv) > 4 else 300

u32 = ctypes.windll.user32
g32 = ctypes.windll.gdi32

def find_hwnd(key):
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
    return found[0] if found else None

class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [('biSize', wintypes.DWORD), ('biWidth', wintypes.LONG),
        ('biHeight', wintypes.LONG), ('biPlanes', wintypes.WORD),
        ('biBitCount', wintypes.WORD), ('biCompression', wintypes.DWORD),
        ('biSizeImage', wintypes.DWORD), ('biXPelsPerMeter', wintypes.LONG),
        ('biYPelsPerMeter', wintypes.LONG), ('biClrUsed', wintypes.DWORD),
        ('biClrImportant', wintypes.DWORD)]

def grab(hwnd):
    r = wintypes.RECT()
    u32.GetWindowRect(hwnd, ctypes.byref(r))
    w, h = r.right - r.left, r.bottom - r.top
    hwndDC = u32.GetWindowDC(hwnd)
    mfcDC = g32.CreateCompatibleDC(hwndDC)
    bmp = g32.CreateCompatibleBitmap(hwndDC, w, h)
    g32.SelectObject(mfcDC, bmp)
    u32.PrintWindow(hwnd, mfcDC, 2)
    bi = BITMAPINFOHEADER()
    bi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
    bi.biWidth, bi.biHeight, bi.biPlanes, bi.biBitCount, bi.biCompression = w, h, 1, 32, 0
    buf = ctypes.create_string_buffer(w * h * 4)
    g32.GetDIBits(mfcDC, bmp, 0, h, buf, ctypes.byref(bi), 0)
    g32.DeleteObject(bmp)
    g32.DeleteDC(mfcDC)
    u32.ReleaseDC(hwnd, hwndDC)
    return Image.frombuffer('RGBA', (w, h), buf, 'raw', 'BGRA', 0, 1).transpose(Image.FLIP_TOP_BOTTOM).convert('RGB')

hwnd = find_hwnd(title_key)
if not hwnd:
    print('NO_WINDOW'); sys.exit(1)

frames = []
end = time.time() + secs
while time.time() < end:
    frames.append(grab(hwnd))
    time.sleep(interval / 1000)

# 统一尺寸 + 量化拼 gif
w, h = frames[0].size
q = [f.resize((w, h)).quantize(colors=256, method=Image.MEDIANCUT) for f in frames]
q[0].save(out, save_all=True, append_images=q[1:], duration=int(interval), loop=0, optimize=True)
print('saved', out, len(q), 'frames', f'{w}x{h}')
