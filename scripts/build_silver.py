"""Build a portable, fixed-entry dependency ZIP for the Glue driver and workers."""
from pathlib import Path
import zipfile


def build(root, output):
    sources = {"bronze_lib.py": root / "src/bronze/handler.py",
               "silver_lib.py": root / "src/silver/transform.py"}
    output.parent.mkdir(parents=True, exist_ok=True)
    (output.parent / "silver-job.py").write_bytes((root / "src/silver/job.py").read_bytes().replace(b"\r\n", b"\n"))
    with zipfile.ZipFile(output, "w") as archive:
        for name, path in sorted(sources.items()):
            entry = zipfile.ZipInfo(name, (2020, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o644 << 16
            archive.writestr(entry, path.read_bytes().replace(b"\r\n", b"\n"))


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    build(root, root / "artifacts/silver-libs.zip")
    print("Glue dependency package built in ignored artifacts/silver-libs.zip")
