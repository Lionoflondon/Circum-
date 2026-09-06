"""Capture browser rating states. Requires fonttools==4.59.0; no app build."""
import base64
from io import BytesIO
from pathlib import Path
import re
import shutil
import subprocess
from fontTools import subset

root = Path(__file__).resolve().parents[1]
flutter = Path(shutil.which("flutter")).resolve()
def encode(path, chars):
    font = subset.load_font(str(path), subset.Options())
    selection = subset.Subsetter()
    selection.populate(unicodes=chars)
    selection.subset(font)
    data = BytesIO()
    font.save(data)
    return base64.b64encode(data.getvalue()).decode()
fixture = root / "test/website_rating_fonts.dart"
original = fixture.read_bytes()
try:
    text = encode(root / "assets/fonts/OpenSans/OpenSans-Regular.ttf", list(range(32, 127)) + [163, 8211, 8217])
    icons = encode(flutter.parents[1] / "bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf", [0xe5f9, 0xe5fa, 0xe156])
    fixture.write_text(f"const ratingTextFont = '{text}';\nconst ratingIconFont = '{icons}';\n")
    result = subprocess.run([str(flutter), "test", "--no-pub", "--platform", "chrome", "test/website_ratings_visual_browser_test.dart"], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
finally:
    fixture.write_bytes(original)
output = root / "test-output/rating-visuals"
output.mkdir(parents=True, exist_ok=True)
for name, data in re.findall(r"VISUAL_CAPTURE:([\w-]+):([A-Za-z0-9+/=]+)", result.stdout):
    (output / f"{name}.png").write_bytes(base64.b64decode(data))
    print(f"Captured {name}")
for line in result.stdout.splitlines():
    if "VISUAL_CAPTURE:" not in line:
        print(line[:1500])
raise SystemExit(result.returncode)
