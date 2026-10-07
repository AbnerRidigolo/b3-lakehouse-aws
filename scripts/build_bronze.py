"""Deterministic Lambda ZIP, containing only reviewed source code."""
from pathlib import Path
import zipfile

def build(source: Path, output: Path):
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as archive:
        entry = zipfile.ZipInfo("handler.py", (2020, 1, 1, 0, 0, 0))
        entry.compress_type = zipfile.ZIP_STORED
        entry.create_system = 3
        entry.external_attr = 0o644 << 16
        archive.writestr(entry, source.read_bytes().replace(b"\r\n", b"\n"))


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    build(root / "src" / "bronze" / "handler.py", root / "artifacts" / "bronze.zip")
    print("Lambda package built in ignored artifacts/bronze.zip")
