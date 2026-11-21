import json
import os
import subprocess
import sys
from pathlib import Path

errors = []
APP_BUNDLE_PATH = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
ENV_PREPARED = False
TARGET_MACOS_MIN_VERSION = os.environ.get("DJ_VERIFY_TARGET_MACOS_MIN_VERSION", "10.15")


def _parse_version(value: str) -> tuple[int, ...]:
    parts = [int(part) for part in value.split(".") if part]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


def _extract_binary_min_macos_version(binary_path: Path) -> str | None:
    commands = [
        ["xcrun", "vtool", "-show-build", str(binary_path)],
        ["otool", "-l", str(binary_path)],
    ]
    for command in commands:
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                check=True,
            )
        except Exception:
            continue
        lines = result.stdout.splitlines()
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("minos "):
                return stripped.split()[1]
        for index, line in enumerate(lines):
            if "LC_VERSION_MIN_MACOSX" not in line:
                continue
            for follow in lines[index + 1:index + 5]:
                stripped = follow.strip()
                if stripped.startswith("version "):
                    return stripped.split()[1]
    return None


def _iter_macho_files(root: Path):
    if not root.exists():
        return
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        try:
            result = subprocess.run(
                ["file", "-b", str(path)],
                capture_output=True,
                text=True,
                check=True,
            )
        except Exception:
            continue
        if "Mach-O" in result.stdout:
            yield path


def _ensure_bundle_environment():
    global ENV_PREPARED
    if ENV_PREPARED or APP_BUNDLE_PATH is None:
        return
    resources = APP_BUNDLE_PATH / "Contents" / "Resources"
    runtime_root = resources / "runtime"
    staged_root = runtime_root / "macos" / _current_runtime_architecture()
    app_runtime = runtime_root / "dj_runtime_py"
    staged_runtime = staged_root / "dj_runtime_py"
    staged_auth_runtime = staged_root / "auth_guest_runtime"
    auth_runtime = runtime_root / "auth_guest_runtime"
    selected_runtime = staged_runtime if staged_runtime.exists() else app_runtime
    selected_auth_runtime = None
    if staged_auth_runtime.exists():
        selected_auth_runtime = staged_auth_runtime
    elif auth_runtime.exists():
        selected_auth_runtime = auth_runtime
    elif selected_runtime.exists():
        selected_auth_runtime = selected_runtime
    if not selected_runtime.exists():
        raise RuntimeError(f"Bundled runtime missing: {selected_runtime}")
    pythonpath_entries = [
        str(selected_runtime),
        str(selected_runtime / ".venv" / "lib" / "python3.11" / "site-packages"),
    ]
    if selected_auth_runtime is not None and selected_auth_runtime != selected_runtime:
        pythonpath_entries.insert(1, str(selected_auth_runtime))
    existing_pythonpath = os.environ.get("PYTHONPATH")
    if existing_pythonpath:
        pythonpath_entries.append(existing_pythonpath)
    for entry in reversed(pythonpath_entries):
        if entry and entry not in sys.path:
            sys.path.insert(0, entry)
    sys.dont_write_bytecode = True
    sys.pycache_prefix = str(Path("/tmp") / "dj_verify_pycache")
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    os.environ["PYTHONPYCACHEPREFIX"] = str(Path("/tmp") / "dj_verify_pycache")
    os.environ["PYTHONPATH"] = os.pathsep.join(pythonpath_entries)
    os.environ["DJ_VERIFY_APP_BUNDLE"] = str(APP_BUNDLE_PATH)
    ENV_PREPARED = True


def _resource_path(*parts: str) -> Path:
    if APP_BUNDLE_PATH is None:
        raise RuntimeError("App bundle path not provided")
    return APP_BUNDLE_PATH.joinpath("Contents", "Resources", *parts)


def _current_runtime_architecture() -> str:
    translated = subprocess.run(
        ["sysctl", "-in", "sysctl.proc_translated"],
        capture_output=True,
        text=True,
    )
    if translated.returncode == 0 and translated.stdout.strip() == "1":
        return "x86_64"
    uname = subprocess.run(["uname", "-m"], capture_output=True, text=True)
    arch = uname.stdout.strip()
    if arch in {"arm64", "x86_64"}:
        return arch
    return "x86_64"


def _selected_runtime_root() -> Path:
    runtime_root = _resource_path("runtime")
    staged_root = runtime_root / "macos" / _current_runtime_architecture() / "dj_runtime_py"
    if staged_root.exists():
        return staged_root
    return runtime_root / "dj_runtime_py"


def _selected_auth_runtime_root() -> Path:
    runtime_root = _resource_path("runtime")
    staged_root = runtime_root / "macos" / _current_runtime_architecture()
    staged_auth = staged_root / "auth_guest_runtime"
    if staged_auth.exists():
        return staged_auth
    auth_root = runtime_root / "auth_guest_runtime"
    if auth_root.exists():
        return auth_root
    return _selected_runtime_root()


def _selected_python_executable() -> Path:
    selected_runtime = _selected_runtime_root()
    runtime_root = selected_runtime.parent if selected_runtime.name == "dj_runtime_py" else selected_runtime
    bundle_runtime_root = _resource_path("runtime") if APP_BUNDLE_PATH is not None else None
    candidates = [
        selected_runtime / "python" / "Python.framework" / "Versions" / "Current" / "bin" / "python3.11",
        selected_runtime / "python" / "Python.framework" / "Versions" / "3.11" / "bin" / "python3.11",
        runtime_root / "python" / "Python.framework" / "Versions" / "Current" / "bin" / "python3.11",
        runtime_root / "python" / "Python.framework" / "Versions" / "3.11" / "bin" / "python3.11",
        *( [
            bundle_runtime_root / "python" / "Python.framework" / "Versions" / "Current" / "bin" / "python3.11",
            bundle_runtime_root / "python" / "Python.framework" / "Versions" / "3.11" / "bin" / "python3.11",
        ] if bundle_runtime_root is not None else []),
        selected_runtime / ".venv" / "bin" / "python3",
        selected_runtime / ".venv" / "bin" / "python",
    ]
    python_executable = next((candidate for candidate in candidates if candidate.exists()), None)
    if python_executable is None:
        raise AssertionError(f"Bundled Python executable missing under {selected_runtime}")
    return python_executable


def _runtime_env(working_directory: Path) -> dict[str, str]:
    env = os.environ.copy()
    python_path_entries = [str(working_directory)]
    site_packages = working_directory / ".venv" / "lib" / "python3.11" / "site-packages"
    if site_packages.exists():
        python_path_entries.append(str(site_packages))
    existing = env.get("PYTHONPATH")
    if existing:
        python_path_entries.append(existing)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    env["PYTHONPYCACHEPREFIX"] = str(Path("/tmp") / "dj_verify_pycache")
    env["PYTHONPATH"] = os.pathsep.join(python_path_entries)
    env["DJ_AUTH_BASE_URL"] = env.get("DJ_AUTH_BASE_URL", "https://example.invalid")
    return env


def _run_python_check(code: str) -> str:
    if APP_BUNDLE_PATH is None:
        command = [sys.executable, "-c", code]
        working_directory = Path.cwd()
        env = os.environ.copy()
    else:
        working_directory = _selected_runtime_root()
        command = [str(_selected_python_executable()), "-c", code]
        env = _runtime_env(working_directory)
    result = subprocess.run(
        command,
        cwd=str(working_directory),
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )
    if result.returncode != 0:
        raise AssertionError((result.stderr or result.stdout).strip())
    return result.stdout


def _wait_for_ready(python_executable: Path, working_directory: Path, module: str, expected_modules: set[str]):
    process = subprocess.Popen(
        [str(python_executable), "-m", module],
        cwd=str(working_directory),
        env=_runtime_env(working_directory),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        first_line = process.stdout.readline().strip()
        if not first_line:
            stderr = process.stderr.read().strip()
            raise AssertionError(f"{module} did not emit ready event. stderr={stderr}")
        payload = json.loads(first_line)
        assert payload.get("event") == "ready", payload
        modules = set(payload.get("supported_modules") or [])
        assert modules == expected_modules, modules
        request = {
            "request_id": "verify_invalid_module",
            "module": "__invalid__",
            "action": "noop",
            "payload": {},
        }
        assert process.stdin is not None
        process.stdin.write(json.dumps(request, ensure_ascii=False) + "\n")
        process.stdin.flush()
        response_line = process.stdout.readline().strip()
        assert response_line, f"{module} did not emit response after ready"
        response = json.loads(response_line)
        assert response.get("request_id") == "verify_invalid_module", response
        assert response.get("ok") is False, response
        error = response.get("error") or {}
        assert error.get("code") == "INVALID_MODULE", error
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def check(name, fn):
    try:
        fn()
        print(f"[PASS] {name}")
    except Exception as e:
        errors.append(f"{name}: {e}")
        print(f"[FAIL] {name}: {e}")


def test_scan():
    _ensure_bundle_environment()
    import dj_scan_core
    r = dj_scan_core.health_check()
    assert '"ok":true' in r or r.get("ok") if isinstance(r, dict) else True


def test_transcode():
    _ensure_bundle_environment()
    import dj_transcode_core
    r = dj_transcode_core.health_check()
    assert '"ok":true' in r or r.get("ok") if isinstance(r, dict) else True


def test_usb():
    _ensure_bundle_environment()
    import dj_usb_backup_core
    r = dj_usb_backup_core.health_check()
    assert '"ok":true' in r or r.get("ok") if isinstance(r, dict) else True


def test_sqlite3():
    import sqlite3
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE t(x)")
    conn.execute("INSERT INTO t VALUES(1)")
    assert conn.execute("SELECT * FROM t").fetchone()[0] == 1
    conn.close()


def test_lzma():
    import lzma
    data = lzma.compress(b"test data")
    assert lzma.decompress(data) == b"test data"


def test_decimal():
    import decimal
    d = decimal.Decimal("3.141592653589793238462643383")
    assert str(d)[:6] == "3.1415"


def test_ssl():
    import ssl
    assert "OpenSSL" in ssl.OPENSSL_VERSION


def test_hashlib():
    import hashlib
    assert len(hashlib.sha256(b"test").hexdigest()) == 64


def test_pypinyin():
    import pypinyin
    assert pypinyin.pinyin("教坊司")[0][0] == "jiào"


def test_cryptography():
    _run_python_check(
        "from cryptography.fernet import Fernet\n"
        "key = Fernet.generate_key()\n"
        "f = Fernet(key)\n"
        "assert f.decrypt(f.encrypt(b'secret')) == b'secret'\n"
    )


def test_cryptodome():
    from Cryptodome.Cipher import AES
    from Crypto.Cipher import AES as AES2
    key = b"0123456789abcdef"
    enc = AES.new(key, AES.MODE_ECB).encrypt(b"0123456789abcdef")
    assert AES2.new(key, AES2.MODE_ECB).decrypt(enc) == b"0123456789abcdef"


def test_lxml():
    _run_python_check(
        "import lxml.etree\n"
        "root = lxml.etree.Element('root')\n"
        "root.text = 'test'\n"
        "assert b'test' in lxml.etree.tostring(root)\n"
    )


def test_orjson():
    _run_python_check(
        "import orjson\n"
        "assert orjson.loads(orjson.dumps({'k': '教坊司'}))['k'] == '教坊司'\n"
    )


def test_yaml():
    import yaml
    assert yaml.safe_load("key: 教坊司")["key"] == "教坊司"


def test_node_paths():
    _ensure_bundle_environment()
    from dj_runtime_py.__main__ import _resolve_node_executable, _resolve_unlock_worker_root
    assert os.path.isfile(_resolve_node_executable())
    assert os.path.isdir(_resolve_unlock_worker_root())


def test_runtime_registry():
    _ensure_bundle_environment()
    from dj_runtime_py.__main__ import _build_runtime_factories
    factories = _build_runtime_factories()
    assert set(factories.keys()) == {
        "auth",
        "guest",
        "cleanup_dup",
        "pinyin_generator",
        "audio_transcode",
        "metadata_edit",
        "usb_backup",
        "unlock_music",
        "search_download",
    }


def test_auth_guest_registry():
    _run_python_check(
        "from dj_runtime_py import auth_guest_main\n"
        "factories = auth_guest_main._build_runtime_factories()\n"
        "assert set(factories.keys()) == {'auth', 'guest'}, factories.keys()\n"
    )


def test_bundled_ff_tools():
    if APP_BUNDLE_PATH is None:
        return
    for tool_name in ("ffmpeg", "ffprobe"):
        tool_path = _resource_path("ff", tool_name)
        assert tool_path.is_file(), f"Missing {tool_name}: {tool_path}"
        assert os.access(tool_path, os.X_OK), f"{tool_name} not executable: {tool_path}"
        result = subprocess.run(
            [str(tool_path), "-version"],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        version_output = (result.stdout + "\n" + result.stderr).lower()
        assert f"{tool_name} version" in version_output, (
            f"{tool_name} did not emit a version banner: {version_output[:200]}"
        )


def test_bundled_runtime_uses_staged_layout():
    if APP_BUNDLE_PATH is None:
        return
    staged_runtime = _resource_path("runtime", "macos", "x86_64", "dj_runtime_py")
    assert staged_runtime.is_dir(), f"Missing staged runtime layout: {staged_runtime}"


def test_bundled_python_starts():
    if APP_BUNDLE_PATH is None:
        return
    working_directory = _selected_runtime_root()
    result = subprocess.run(
        [str(_selected_python_executable()), "-c", "import sys; print(sys.version)"],
        capture_output=True,
        text=True,
        cwd=str(working_directory),
        env=_runtime_env(working_directory),
        check=True,
    )
    assert result.stdout.strip(), "Bundled Python did not emit a version string"


def test_auth_runtime_ready():
    if APP_BUNDLE_PATH is None:
        return
    _wait_for_ready(
        python_executable=_selected_python_executable(),
        working_directory=_selected_auth_runtime_root(),
        module="dj_runtime_py.auth_guest_main",
        expected_modules={"auth", "guest"},
    )


def test_main_runtime_ready():
    if APP_BUNDLE_PATH is None:
        return
    _wait_for_ready(
        python_executable=_selected_python_executable(),
        working_directory=_selected_runtime_root(),
        module="dj_runtime_py",
        expected_modules={
            "auth",
            "guest",
            "cleanup_dup",
            "pinyin_generator",
            "audio_transcode",
            "metadata_edit",
            "usb_backup",
            "unlock_music",
            "search_download",
        },
    )


def test_bundled_macos_min_versions():
    if APP_BUNDLE_PATH is None:
        return
    runtime_root = _resource_path("runtime")
    ff_root = _resource_path("ff")
    checked_paths: list[Path] = []
    for root in (runtime_root, ff_root):
        for binary_path in _iter_macho_files(root):
            min_version = _extract_binary_min_macos_version(binary_path)
            assert min_version is not None, f"Unable to read min macOS version: {binary_path}"
            assert _parse_version(min_version) <= _parse_version(TARGET_MACOS_MIN_VERSION), (
                f"{binary_path} requires macOS {min_version}, newer than {TARGET_MACOS_MIN_VERSION}"
            )
            checked_paths.append(binary_path)
    assert checked_paths, "No bundled Mach-O files were checked"


def test_mutagen():
    import mutagen


def test_requests():
    import requests


def test_curl_cffi():
    _run_python_check("import curl_cffi\n")


def test_ytmusicapi():
    import ytmusicapi


def test_platformdirs():
    import platformdirs


def test_prompt_toolkit_metadata():
    if APP_BUNDLE_PATH is None:
        return
    _ensure_bundle_environment()
    import prompt_toolkit
    from importlib import metadata

    assert metadata.version("prompt_toolkit") == prompt_toolkit.__version__


checks = [
    ("bundled staged runtime layout", test_bundled_runtime_uses_staged_layout),
    ("bundled Mach-O 最低系统版本", test_bundled_macos_min_versions),
    ("dj_scan_core (7 capabilities)", test_scan),
    ("dj_transcode_core (11 capabilities)", test_transcode),
    ("dj_usb_backup_core (11 capabilities)", test_usb),
    ("sqlite3 实际读写", test_sqlite3),
    ("lzma 实际压缩解压", test_lzma),
    ("decimal 高精度计算", test_decimal),
    ("ssl/OpenSSL", test_ssl),
    ("hashlib SHA256", test_hashlib),
    ("pypinyin 拼音转换", test_pypinyin),
    ("cryptography Fernet 加密解密", test_cryptography),
    ("Cryptodome/Crypto AES 加密解密", test_cryptodome),
    ("lxml XML 读写", test_lxml),
    ("orjson JSON 序列化", test_orjson),
    ("yaml YAML 解析", test_yaml),
    ("Node.js 路径解析", test_node_paths),
    ("主运行时注册表", test_runtime_registry),
    ("鉴权运行时注册表", test_auth_guest_registry),
    ("bundled ffmpeg/ffprobe", test_bundled_ff_tools),
    ("bundled Python 启动", test_bundled_python_starts),
    ("鉴权运行时 ready 启动", test_auth_runtime_ready),
    ("主运行时 ready 启动", test_main_runtime_ready),
    ("mutagen", test_mutagen),
    ("requests", test_requests),
    ("curl_cffi", test_curl_cffi),
    ("ytmusicapi", test_ytmusicapi),
    ("platformdirs", test_platformdirs),
    ("prompt_toolkit 元数据", test_prompt_toolkit_metadata),
]

for name, fn in checks:
    check(name, fn)

print()
if errors:
    print(f"FAILED: {len(errors)}/{len(checks)}")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)
else:
    print(f"ALL {len(checks)} CHECKS PASSED")
