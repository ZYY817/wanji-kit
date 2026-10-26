# 雕塑抠图 v3：差分 alpha + 多边形区域遮罩（软边）+ 连通域过滤
from collections import deque
import numpy as np
from PIL import Image, ImageFilter, ImageDraw

def _components(mask):
    h, w = mask.shape
    lab = np.zeros((h, w), np.int32)
    comps = []
    cur = 0
    ys, xs = np.where(mask)
    for sy, sx in zip(ys.tolist(), xs.tolist()):
        if lab[sy, sx]:
            continue
        cur += 1
        qq = deque([(sy, sx)])
        lab[sy, sx] = cur
        pts = []
        while qq:
            y, x = qq.popleft()
            pts.append((y, x))
            for ny, nx in ((y-1,x),(y+1,x),(y,x-1),(y,x+1)):
                if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = cur
                    qq.append((ny, nx))
        comps.append(pts)
    return lab, comps

def extract(src, box, poly, out, blur=70, t0=5, t1=22, feather=1.4,
            lowcut=0.15, keep_near=60, poly_soft=26, cuts=None):
    """poly: 原图坐标多边形，圈定雕塑范围；cuts: 额外切除的多边形列表"""
    img = Image.open(src).convert('RGB').crop(box)
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]

    bg = np.asarray(img.filter(ImageFilter.GaussianBlur(blur))).astype(np.float32)
    for _ in range(3):
        diff = np.abs(a - bg).max(axis=2)
        est = a.copy()
        est[diff > t1] = bg[diff > t1]
        bg = np.asarray(Image.fromarray(est.astype(np.uint8))
                        .filter(ImageFilter.GaussianBlur(blur))).astype(np.float32)

    diff = np.abs(a - bg).max(axis=2)
    alpha = np.clip((diff - t0) / (t1 - t0), 0, 1)
    alpha[alpha < lowcut] = 0.0

    # 多边形遮罩（原图坐标 → 裁剪坐标），软边
    if poly:
        pm = Image.new('L', (w, h), 0)
        ImageDraw.Draw(pm).polygon([(x - box[0], y - box[1]) for x, y in poly],
                                   fill=255)
        pm = pm.filter(ImageFilter.GaussianBlur(poly_soft))
        alpha *= np.asarray(pm).astype(np.float32) / 255.0
    for cp in (cuts or []):
        cm = Image.new('L', (w, h), 0)
        ImageDraw.Draw(cm).polygon([(x - box[0], y - box[1]) for x, y in cp],
                                   fill=255)
        cm = cm.filter(ImageFilter.GaussianBlur(18))
        alpha *= 1.0 - np.asarray(cm).astype(np.float32) / 255.0

    # 连通域过滤：只留最大块 + 近邻
    solid = alpha > 0.4
    lab, comps = _components(solid)
    if comps:
        big = max(comps, key=len)
        bys = [p[0] for p in big]; bxs = [p[1] for p in big]
        bb = (min(bys), min(bxs), max(bys), max(bxs))
        keep = np.zeros((h, w), bool)
        for comp in comps:
            cys = [p[0] for p in comp]; cxs = [p[1] for p in comp]
            cb = (min(cys), min(cxs), max(cys), max(cxs))
            dy = max(0, max(bb[0]-cb[2], cb[0]-bb[2]))
            dx = max(0, max(bb[1]-cb[3], cb[1]-bb[3]))
            if (dx*dx+dy*dy) ** 0.5 < keep_near or comp is big:
                for (y, x) in comp:
                    keep[y, x] = True
        alpha[~keep & (alpha > 0)] = 0.0

    alpha[:4, :] = 0; alpha[-4:, :] = 0; alpha[:, :4] = 0; alpha[:, -4:] = 0
    alpha_img = Image.fromarray((alpha * 255).astype(np.uint8))
    alpha_img = alpha_img.filter(ImageFilter.GaussianBlur(feather))
    alpha = np.asarray(alpha_img).astype(np.float32) / 255.0
    alpha[alpha < 0.04] = 0.0

    rgba = np.dstack([a.astype(np.uint8), (alpha * 255).astype(np.uint8)])
    res = Image.fromarray(rgba, 'RGBA')
    ys, xs = np.where(alpha > 0.03)
    if len(ys):
        pad = 6
        res = res.crop((max(0, xs.min()-pad), max(0, ys.min()-pad),
                        min(w, xs.max()+pad), min(h, ys.max()+pad)))
    res.save(out)
    print('saved', out, res.size)

if __name__ == '__main__':
    # ref_A: 雕塑在原图 x~230-700 y~55-410；切除右上光束带与左下地面光斑
    extract('F:/wanji-kit/refs/ref_A.png', (210, 40, 720, 408),
            [(250, 55), (620, 55), (715, 120), (715, 395), (330, 405), (235, 320)],
            'F:/wanji-kit/app/assets/sculpt_a.png',
            cuts=[[(545, 40), (720, 40), (720, 130), (560, 150)],
                  [(210, 330), (400, 330), (400, 408), (210, 408)]])
    # ref_D: 雕塑 x~190-720 y~40-465；避开右侧按钮与左下地影
    extract('F:/wanji-kit/refs/ref_D.png', (150, 20, 740, 490),
            [(215, 50), (560, 45), (720, 130), (735, 400), (300, 470), (185, 350)],
            'F:/wanji-kit/app/assets/sculpt_d.png',
            cuts=[[(150, 330), (400, 330), (400, 490), (150, 490)],
                  [(560, 20), (740, 20), (740, 120), (600, 140)]])
