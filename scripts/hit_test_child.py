# 验证 FlutterView 子窗口 WM_NCHITTEST 子类化：
#   子窗口在拖拽条/缩放边返回 HTTRANSPARENT(-1)，控件区/正文返回 HTCLIENT(1)
#   父窗口同一屏幕点应返回真实 NC 码（HTCAPTION=2, HTLEFT=10 ...）
# 用法: python hit_test_child.py [title_key]
import sys, ctypes
from ctypes import wintypes

u32 = ctypes.windll.user32
key = sys.argv[1] if len(sys.argv) > 1 else 'wanji'

HT = {-2:'HTERROR',-1:'TRANSPARENT',0:'NOWHERE',1:'CLIENT',2:'CAPTION',
      3:'SYSMENU',5:'MENU',6:'HSCROLL',7:'VSCROLL',10:'LEFT',11:'RIGHT',
      12:'TOP',13:'TOPLEFT',14:'TOPRIGHT',15:'BOTTOM',16:'BOTTOMLEFT',
      17:'BOTTOMRIGHT',18:'BORDER'}

# ---- find top-level window ----
found = []
def cb(hwnd, _):
    if not u32.IsWindowVisible(hwnd): return True
    buf = ctypes.create_unicode_buffer(256)
    u32.GetWindowTextW(hwnd, buf, 256)
    if key in buf.value: found.append(hwnd)
    return True
u32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)(cb), 0)
if not found: print('NO_WINDOW'); sys.exit(1)
parent = found[0]

# ---- enumerate ALL descendants ----
desc = []
def ccb(hwnd, lp):
    cls = ctypes.create_unicode_buffer(128)
    u32.GetClassNameW(hwnd, cls, 128)
    r = wintypes.RECT(); u32.GetWindowRect(hwnd, ctypes.byref(r))
    desc.append((hwnd, cls.value, (r.left, r.top, r.right - r.left, r.bottom - r.top)))
    return True
CH = ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
u32.EnumChildWindows(parent, CH(ccb), 0)  # recursive: children + deeper
print(f'parent={parent} descendants={len(desc)}')
for h, c, r in desc: print(f'  child={h} class={c!r} rect={r}')

child = desc[0][0] if desc else None
print()

r = wintypes.RECT(); u32.GetWindowRect(parent, ctypes.byref(r))
wx, wy, w, h = r.left, r.top, r.right - r.left, r.bottom - r.top
dpi = u32.GetDpiForWindow(parent)
zoomed = bool(u32.IsZoomed(parent))
print(f'window=({wx},{wy},{w}x{h}) dpi={dpi} zoomed={zoomed}')

def nchit(hwnd, sx, sy):
    return u32.SendMessageW(hwnd, 0x0084, 0, ((sy & 0xFFFF) << 16) | (sx & 0xFFFF))

# WindowFromPoint: which window would the REAL mouse hit-test?
p = wintypes.POINT(int(wx + w//2), int(wy + 20))
wfp = u32.WindowFromPoint(p)
print(f'WindowFromPoint(strip center)={wfp}  child={child} parent={parent} '
      f'-> {"CHILD gets real NCHITTEST" if wfp == child else "OTHER: "+str(wfp)}')
print()

# test points in client coords (== window coords, borderless)
pts = [
    ('strip center   ', w//2, 20,   'TRANSPARENT', 'CAPTION'),
    ('strip brand    ', 60,   20,   'TRANSPARENT', 'CAPTION'),
    ('top edge       ', w//2, 3,    'TRANSPARENT', 'TOP'),
    ('top-left corner', 3,    3,    'TRANSPARENT', 'TOPLEFT'),
    ('top-right x-ctl', w-3,  3,    'CLIENT',      'CLIENT'),  # inside ctl zone
    ('right edge     ', w-3,  200,  'TRANSPARENT', 'RIGHT'),
    ('left edge      ', 3,    200,  'TRANSPARENT', 'LEFT'),
    ('bottom edge    ', w//2, h-3,  'TRANSPARENT', 'BOTTOM'),
    ('bot-right crn  ', w-3,  h-3,  'TRANSPARENT', 'BOTTOMRIGHT'),
    ('bot-left crn   ', 3,    h-3,  'TRANSPARENT', 'BOTTOMLEFT'),
    ('controls zone  ', w-100,20,   'CLIENT',      'CLIENT'),
    ('close btn zone ', w-20, 20,   'CLIENT',      'CLIENT'),
    ('body center    ', w//2, h//2, 'CLIENT',      'CLIENT'),
    ('body low       ', 60,   h-60, 'CLIENT',      'CLIENT'),
]
fails = 0
print(f'{"point":<17}{"(x,y)":<16}{"child":<13}{"parent":<13}{"expect c/p":<20}verdict')
for name, x, y, ec, ep in pts:
    if zoomed: ec = ep = 'CLIENT'   # maximized: whole window is client
    sx, sy = wx + x, wy + y
    c = nchit(child, sx, sy)
    p_ = nchit(parent, sx, sy)
    cn, pn = HT.get(c, str(c)), HT.get(p_, str(p_))
    ok = (cn == ec) and (pn == ep)
    if not ok: fails += 1
    print(f'{name:<17}({x},{y}){"":<8}{cn:<13}{pn:<13}{ec+"/"+ep:<20}{"OK" if ok else "** MISMATCH **"}')
print(f'\n{"ALL PASS" if fails == 0 else f"{fails} FAILURES"}')
