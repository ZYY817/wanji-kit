# QA 辅助：按 FLUTTER_RUNNER 类名找主窗口（不混淆同名 Chrome），支持 shot/click/pwheel/size/crop
import sys, ctypes, time
from ctypes import wintypes
u32=ctypes.windll.user32; g32=ctypes.windll.gdi32

def pick():
    res=[]
    def cb(h,_):
        if not u32.IsWindowVisible(h): return True
        c=ctypes.create_unicode_buffer(64); u32.GetClassNameW(h,c,64)
        if 'FLUTTER_RUNNER' not in c.value: return True
        res.append(h)
        return True
    u32.EnumWindows(ctypes.WINFUNCTYPE(ctypes.c_bool,wintypes.HWND,wintypes.LPARAM)(cb),0)
    if not res: return None
    # 取非最小化中面积最大者
    best=None; area=-1
    for h in res:
        r=wintypes.RECT(); u32.GetWindowRect(h,ctypes.byref(r))
        a=(r.right-r.left)*(r.bottom-r.top)
        if not u32.IsIconic(h) and a>area: area,best=a,h
    if best is None:
        u32.ShowWindow(res[0],9); time.sleep(0.6); best=res[0]
    return best

def child(h):
    c=[]
    def cb2(x,_):
        n=ctypes.create_unicode_buffer(256); u32.GetClassNameW(x,n,256)
        if 'FLUTTER' in n.value.upper() and 'RUNNER' not in n.value.upper(): c.append(x)
        return True
    u32.EnumChildWindows(h,ctypes.WINFUNCTYPE(ctypes.c_bool,wintypes.HWND,wintypes.LPARAM)(cb2),0)
    return c[0] if c else h

def grab(h):
    from PIL import Image
    r=wintypes.RECT(); u32.GetWindowRect(h,ctypes.byref(r))
    w,hh=r.right-r.left,r.bottom-r.top
    hdc=u32.GetWindowDC(h); mfc=g32.CreateCompatibleDC(hdc)
    bmp=g32.CreateCompatibleBitmap(hdc,w,hh); g32.SelectObject(mfc,bmp)
    u32.PrintWindow(h,mfc,2)
    class BI(ctypes.Structure):
        _fields_=[('s',wintypes.DWORD),('w',wintypes.LONG),('hh',wintypes.LONG),
            ('pl',wintypes.WORD),('bc',wintypes.WORD),('cmp',wintypes.DWORD),
            ('si',wintypes.DWORD),('x',wintypes.LONG),('y',wintypes.LONG),
            ('cu',wintypes.DWORD),('ci',wintypes.DWORD)]
    bi=BI(); bi.s=ctypes.sizeof(BI); bi.w=w; bi.hh=hh; bi.pl=1; bi.bc=32; bi.cmp=0
    buf=ctypes.create_string_buffer(w*hh*4)
    g32.GetDIBits(mfc,bmp,0,hh,buf,ctypes.byref(bi),0)
    g32.DeleteObject(bmp); g32.DeleteDC(mfc); u32.ReleaseDC(h,hdc)
    return Image.frombuffer('RGBA',(w,hh),buf,'raw','BGRA',0,1).transpose(Image.FLIP_TOP_BOTTOM)

cmd=sys.argv[1]
h=pick()
if h is None: print('NO_WINDOW'); sys.exit(1)

if cmd=='shot':
    grab(h).save(sys.argv[2]); print('saved',sys.argv[2])
elif cmd=='crop':
    im=grab(h); x1,y1,x2,y2,sc=[float(v) for v in sys.argv[3].split(',')]
    im.crop((int(x1),int(y1),int(x2),int(y2))).resize(
        (int((x2-x1)*sc),int((y2-y1)*sc))).save(sys.argv[2])
    print('cropped',sys.argv[2])
elif cmd=='click':
    x,y=int(sys.argv[2]),int(sys.argv[3]); t=child(h)
    lp=(y<<16)|(x&0xFFFF)
    u32.PostMessageW(t,0x0200,0,lp); time.sleep(0.05)
    u32.PostMessageW(t,0x0201,1,lp); time.sleep(0.08)
    u32.PostMessageW(t,0x0202,0,lp); print('clicked',x,y)
elif cmd=='pwheel':
    x,y,d=int(sys.argv[2]),int(sys.argv[3]),int(sys.argv[4])
    t=child(h)
    pt=wintypes.POINT(x,y); u32.ClientToScreen(h,ctypes.byref(pt))
    lp_cl=((y&0xFFFF)<<16)|(x&0xFFFF)
    lp_scr=((pt.y&0xFFFF)<<16)|(pt.x&0xFFFF)
    u32.PostMessageW(t,0x0200,0,lp_cl); time.sleep(0.15)
    for _ in range(abs(d)):
        delta=-120 if d>0 else 120
        wp=ctypes.c_ulonglong((delta&0xFFFF)<<16).value
        u32.PostMessageW(t,0x020A,wp,lp_scr)
        time.sleep(0.07)
    print('pwheeled',d)
elif cmd=='size':
    tw,th=int(sys.argv[2]),int(sys.argv[3])
    wr,cr=wintypes.RECT(),wintypes.RECT()
    u32.GetWindowRect(h,ctypes.byref(wr)); u32.GetClientRect(h,ctypes.byref(cr))
    u32.MoveWindow(h,wr.left,wr.top,
        tw+(wr.right-wr.left)-(cr.right-cr.left),
        th+(wr.bottom-wr.top)-(cr.bottom-cr.top),True)
    print('sized')
elif cmd=='esc':
    t=child(h)
    u32.PostMessageW(t,0x0100,0x1B,0); time.sleep(0.05)
    u32.PostMessageW(t,0x0101,0x1B,0); print('esc')
