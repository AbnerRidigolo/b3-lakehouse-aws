from scripts.build_silver import build


def test_windows_and_linux_glue_packages_are_identical(tmp_path):
    outputs = []
    for label, ending in [('linux', b'\n'), ('windows', b'\r\n')]:
        root = tmp_path / label
        for filename in ['src/bronze/handler.py', 'src/silver/transform.py', 'src/silver/job.py']:
            path = root / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'value = 1' + ending)
        output = root / 'artifacts/silver-libs.zip'
        build(root, output)
        outputs.append((output.read_bytes(), (output.parent / 'silver-job.py').read_bytes()))
    assert outputs[0] == outputs[1]
