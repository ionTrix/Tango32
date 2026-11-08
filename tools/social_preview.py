# Tango32 social preview — 2026-11-07 20:45 ET
# Renders docs/banner.html into docs/social-preview.png (1280x640, GitHub repo social preview).
# The 1200x400 banner is scaled to 1280 wide and centered; its glow + grid are extended to the full canvas.
# Needs: pip install playwright (Chromium or Chrome) and the banner fonts in docs/fonts (see banner.html).
# Run from the repo root: python3 tools/social_preview.py
import pathlib
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "banner.html"
OUT = ROOT / "docs" / "social-preview.png"
W, H, BW, BH = 1280, 640, 1200, 400
K = W / BW                    # 1.0667
DY = (H - BH * K) / 2         # vertical offset of the scaled banner

def g(rx, ry, cx, cy, rgba):  # banner radial gradient, mapped to canvas coords
    return f"radial-gradient({rx*K:.0f}px {ry*K:.0f}px at {cx*K:.0f}px {cy*K+DY:.0f}px,{rgba},transparent 70%)"

BG = ",".join([
    g(560, 380, 1010, 200, "rgba(255,64,170,.20)"),
    g(520, 360, 900, 230, "rgba(0,229,255,.16)"),
    g(500, 300, 600, 210, "rgba(120,80,255,.16)"),
]) + ",#0a0918"

JS = f"""() => {{
  const b = document.getElementById('b');
  const wrap = document.createElement('div');
  wrap.id = 'sp';
  wrap.style.cssText = 'position:relative;width:{W}px;height:{H}px;overflow:hidden;background:{BG}';
  const grid = document.createElement('div');
  grid.style.cssText = 'position:absolute;inset:0;background-image:linear-gradient(rgba(255,255,255,.035) 1px,transparent 1px),linear-gradient(90deg,rgba(255,255,255,.035) 1px,transparent 1px);background-size:{20*K:.4f}px {20*K:.4f}px;background-position:0 {DY % (20*K):.4f}px';
  wrap.appendChild(grid);
  b.parentNode.insertBefore(wrap, b);
  wrap.appendChild(b);
  b.style.background = 'transparent';
  b.style.position = 'absolute';
  b.style.left = '0';
  b.style.top = '{DY:.4f}px';
  b.style.transformOrigin = '0 0';
  b.style.transform = 'scale({K:.6f})';
  document.getElementById('grid').style.display = 'none';
}}"""

with sync_playwright() as p:
    try:
        br = p.chromium.launch()
    except Exception:
        br = p.chromium.launch(channel="chrome")
    pg = br.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
    pg.goto(SRC.as_uri())
    pg.wait_for_load_state("networkidle")
    pg.evaluate("document.fonts.ready")
    pg.evaluate(JS)
    pg.locator("#sp").screenshot(path=str(OUT))
    br.close()
print(f"wrote {OUT} ({W}x{H})")
