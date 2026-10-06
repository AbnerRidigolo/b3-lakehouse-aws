"""Deterministic Lambda ZIP, containing only reviewed source code."""
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
output = root / "artifacts" / "bronze.zip"
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    entry = zipfile.ZipInfo("handler.py", (2020, 1, 1, 0, 0, 0))
    entry.compress_type = zipfile.ZIP_DEFLATED
    entry.external_attr = 0o644 << 16
    archive.writestr(entry, (root / "src" / "bronze" / "handler.py").read_bytes())
print("Lambda package built in ignored artifacts/bronze.zip")
