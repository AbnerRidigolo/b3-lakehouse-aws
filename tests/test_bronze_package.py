import zipfile
from scripts.build_bronze import build


def test_same_package_for_windows_and_linux_source(tmp_path):
    linux = tmp_path / "linux.py"
    windows = tmp_path / "windows.py"
    linux.write_bytes(b'def handler():\n    return "ok"\n')
    windows.write_bytes(b'def handler():\r\n    return "ok"\r\n')
    a, b = tmp_path / "a.zip", tmp_path / "b.zip"
    build(linux, a)
    build(windows, b)
    assert a.read_bytes() == b.read_bytes()
    with zipfile.ZipFile(a) as archive:
        assert archive.namelist() == ["handler.py"]
        assert archive.read("handler.py") == linux.read_bytes()
        assert archive.getinfo("handler.py").create_system == 3
