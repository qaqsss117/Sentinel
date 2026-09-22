"""Build a local review gallery from real Flutter widget-test screenshots.

Run from any directory: python docs/ui-refresh/generate_gallery.py
Requires Pillow. Fonts are read locally and are never redistributed.
"""
from pathlib import Path
from html import escape
import hashlib
import json

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
AFTER = ROOT / "screenshots" / "after"
FONT_PATH = Path("C:/Windows/Fonts/msyh.ttc")


def font(size):
    return ImageFont.truetype(str(FONT_PATH), size) if FONT_PATH.exists() else ImageFont.load_default()


def paste_fit(canvas, path, rect):
    picture = Image.open(path).convert("RGB")
    picture.thumbnail((rect[2], rect[3]), Image.Resampling.LANCZOS)
    canvas.paste(picture, (rect[0] + (rect[2] - picture.width) // 2, rect[1]))


main = [("home", "首页"), ("plans", "套餐"), ("purchase", "购买"),
        ("gateway", "支付"), ("invite", "邀请"), ("support", "客服")]
overview = Image.new("RGB", (1620, 730), "#eeebf5")
draw = ImageDraw.Draw(overview)
draw.text((24, 18), "Sentinel · 哨兵客户端", font=font(26), fill="#251b39")
draw.text((24, 59), "深紫主题 · 真实页面 / 固定模拟数据 · 390 × 844", font=font(17), fill="#695e7b")
for index, (key, label) in enumerate(main):
    x = 24 + index * 265
    draw.text((x, 102), label, font=font(19), fill="#251b39")
    paste_fit(overview, AFTER / f"{key}-dark-390.png", (x, 138, 242, 563))
overview.save(ROOT / "overview.png", optimize=True)

comparison = Image.new("RGB", (1600, 1430), "#eeebf5")
draw = ImageDraw.Draw(comparison)
draw.text((24, 16), "历史界面参考 → 本次实现", font=font(28), fill="#251b39")
draw.text((24, 58), "上：仓库 images/ 中已有历史截图；下：本次固定数据截图。并非同一版本、数据或设备的基线。", font=font(18), fill="#695e7b")
for index, (old, new, label) in enumerate([
    ("homepage", "home", "首页"), ("plans", "plans", "套餐"),
    ("purchase", "purchase", "购买"), ("invitepage", "invite", "邀请"),
]):
    x = 24 + index * 394
    draw.text((x, 101), f"{label} · 历史参考", font=font(20), fill="#695e7b")
    paste_fit(comparison, REPO / "images" / f"{old}.jpg", (x, 138, 350, 560))
    draw.text((x, 736), f"{label} · 本次实现", font=font(20), fill="#251b39")
    paste_fit(comparison, AFTER / f"{new}-dark-390.png", (x, 777, 350, 622))
comparison.save(ROOT / "comparison.png", optimize=True)

cards = []
manifest = []
for path in sorted(AFTER.glob("*.png")):
    name = path.stem
    theme = "light" if "-light-" in name else "dark"
    src = path.relative_to(ROOT).as_posix()
    with Image.open(path) as picture:
        size = picture.size
    manifest.append({"file": src, "pixels": list(size), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    cards.append(f'<figure data-theme="{theme}"><a href="{src}"><img loading="lazy" src="{src}" alt="{escape(name)}"></a><figcaption>{escape(name)}</figcaption></figure>')

html = """<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Sentinel UI 验收图库</title><style>
body{font:16px/1.65 system-ui,"Microsoft YaHei",sans-serif;background:#f6f3fc;color:#251b39;margin:0;padding:32px;max-width:1500px;margin:auto}
h1{margin-bottom:4px}p{max-width:1000px;color:#695e7b}a{color:#6240b5}nav{display:flex;gap:12px;flex-wrap:wrap;margin:24px 0}
button{font:inherit;border:1px solid #c9b9e6;padding:8px 20px;border-radius:12px;background:white;cursor:pointer}
button[aria-pressed=true]{background:#311f52;color:white}.hero{width:100%;border-radius:20px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}
figure{margin:0;padding:16px;background:white;border:1px solid #e3dcec;border-radius:18px}figure img{display:block;width:100%;max-height:620px;object-fit:contain;object-position:top}figcaption{padding-top:12px;overflow-wrap:anywhere}[hidden]{display:none}
</style><h1>Sentinel · UI 验收图库</h1>
<p>真实 Flutter 页面，使用固定模拟数据。含深浅主题、移动端与桌面布局，以及空白、错误和支付状态。点击图片查看原图。</p>
<p><a href="README.md">实现与验证报告</a> · <a href="ASSETS.md">素材来源</a> · <a href="comparison.png">历史参考对比（非精确版本基线）</a></p>
<img class="hero" src="overview.png" alt="主要页面预览">
<nav><button aria-pressed="true" data-filter="all">全部</button><button aria-pressed="false" data-filter="dark">深色</button><button aria-pressed="false" data-filter="light">浅色</button></nav>
<div class="grid">""" + "\n".join(cards) + """</div><script>
document.querySelectorAll('[data-filter]').forEach(button=>button.onclick=()=>{
 document.querySelectorAll('[data-filter]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
 document.querySelectorAll('figure').forEach(f=>f.hidden=button.dataset.filter!=='all'&&f.dataset.theme!==button.dataset.filter);
});</script></html>"""
(ROOT / "index.html").write_text(html, encoding="utf-8")
(ROOT / "screenshots" / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Generated gallery for {len(cards)} screenshots.")
