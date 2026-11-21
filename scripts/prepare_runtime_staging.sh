#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNTIME_SOURCE_DIR="${REPO_ROOT}/runtime"
SOURCE_VENV="${DJ_RUNTIME_SOURCE_VENV:-${REPO_ROOT}/.venv}"
SOURCE_PYTHON="${DJ_RUNTIME_SOURCE_PYTHON:-${SOURCE_VENV}/bin/python}"
SOURCE_PYTHON_FRAMEWORK="${DJ_RUNTIME_SOURCE_PYTHON_FRAMEWORK:-}"
SOURCE_NODE_BIN="${DJ_RUNTIME_SOURCE_NODE_BIN:-}"
SOURCE_FFMPEG="${DJ_RUNTIME_SOURCE_FFMPEG:-${REPO_ROOT}/ff/ffmpeg}"
SOURCE_FFPROBE="${DJ_RUNTIME_SOURCE_FFPROBE:-${REPO_ROOT}/ff/ffprobe}"
TARGET_ARCH="${DJ_RUNTIME_TARGET_ARCH:-x86_64}"
TARGET_MACOS_MIN_VERSION="${DJ_RUNTIME_TARGET_MACOS_MIN_VERSION:-${MACOSX_DEPLOYMENT_TARGET:-10.15}}"
STAGING_ROOT="${REPO_ROOT}/runtime_staging/macos"
TARGET_DIR="${STAGING_ROOT}/${TARGET_ARCH}"
TMP_DIR=""

find_first_match() {
  local search_root="$1"
  local expression="$2"
  find "${search_root}" -path "${expression}" -print -quit 2>/dev/null || true
}

assert_file_exists() {
  local file_path="$1"
  local label="$2"
  if [ ! -e "${file_path}" ]; then
    echo "Missing required asset (${label}): ${file_path}" >&2
    exit 1
  fi
}

assert_match_exists() {
  local search_root="$1"
  local expression="$2"
  local label="$3"
  local match_path
  match_path="$(find_first_match "${search_root}" "${expression}")"
  if [ -z "${match_path}" ]; then
    echo "Missing required asset (${label}) under ${search_root}: ${expression}" >&2
    exit 1
  fi
}

assert_no_external_deps() {
  local binary_path="$1"
  if [ ! -f "${binary_path}" ]; then
    return
  fi
  otool -L "${binary_path}" | while IFS= read -r dep_line; do
    local dep_path
    dep_path="$(printf '%s' "${dep_line}" | sed 's/^[[:space:]]*//' | cut -d' ' -f1)"
    dep_path="${dep_path%:}"
    if [ -z "${dep_path}" ] || [ "${dep_path}" = "${binary_path}" ]; then
      continue
    fi
    case "${dep_path}" in
      /Users/*|/opt/homebrew/*|/usr/local/*|*/target/*|/private/var/folders/*)
        echo "External dependency detected in ${binary_path}" >&2
        otool -L "${binary_path}" >&2
        exit 1
        ;;
    esac
  done
}

validate_binary_architecture() {
  local binary_path="$1"
  local expected_arch="$2"
  if [ ! -f "${binary_path}" ]; then
    return
  fi
  local file_description
  file_description="$(file -b "${binary_path}" 2>/dev/null || true)"
  case "${file_description}" in
    *Mach-O*)
      local actual_archs normalized_archs
      actual_archs="$(lipo -archs "${binary_path}" 2>/dev/null || true)"
      normalized_archs="$(printf '%s' "${actual_archs}" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
      if [ "${normalized_archs}" != "${expected_arch}" ]; then
        echo "Unexpected architecture for ${binary_path}: ${actual_archs} (expected ${expected_arch})" >&2
        exit 1
      fi
      ;;
  esac
}

binary_has_architecture() {
  local binary_path="$1"
  local expected_arch="$2"
  local actual_archs
  actual_archs="$(lipo -archs "${binary_path}" 2>/dev/null || true)"
  printf '%s\n' "${actual_archs}" | tr ' ' '\n' | grep -Fx "${expected_arch}" >/dev/null 2>&1
}

thin_binary_to_architecture() {
  local binary_path="$1"
  local expected_arch="$2"
  if [ ! -f "${binary_path}" ]; then
    return
  fi
  local file_description actual_archs normalized_archs tmp_output mode_value
  file_description="$(file -b "${binary_path}" 2>/dev/null || true)"
  case "${file_description}" in
    *Mach-O*) ;;
    *) return ;;
  esac
  actual_archs="$(lipo -archs "${binary_path}" 2>/dev/null || true)"
  normalized_archs="$(printf '%s' "${actual_archs}" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ "${normalized_archs}" = "${expected_arch}" ]; then
    return
  fi
  if ! binary_has_architecture "${binary_path}" "${expected_arch}"; then
    echo "Binary ${binary_path} does not contain required architecture ${expected_arch}: ${actual_archs}" >&2
    exit 1
  fi
  mode_value="$(stat -f '%Lp' "${binary_path}")"
  tmp_output="${binary_path}.thin-${expected_arch}"
  rm -f "${tmp_output}"
  lipo -thin "${expected_arch}" "${binary_path}" -output "${tmp_output}"
  chmod "${mode_value}" "${tmp_output}"
  mv "${tmp_output}" "${binary_path}"
}

thin_runtime_tree_to_architecture() {
  local runtime_dir="$1"
  local expected_arch="$2"
  if [ ! -d "${runtime_dir}" ]; then
    return
  fi
  find "${runtime_dir}" \( -perm -111 -o -name '*.dylib' -o -name '*.so' -o -name '*.node' \) -type f | while IFS= read -r binary_path; do
    thin_binary_to_architecture "${binary_path}" "${expected_arch}"
  done
}

extract_binary_macos_min_version() {
  local binary_path="$1"
  python3 - "${binary_path}" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

path = Path(sys.argv[1])


def run(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True)
    except Exception:
        return ""
    return result.stdout


for command in (("xcrun", "vtool", "-show-build", str(path)), ("otool", "-l", str(path))):
    output = run(command)
    if not output:
        continue
    match = re.search(r"\bminos\s+([0-9]+(?:\.[0-9]+){0,2})", output)
    if match:
        print(match.group(1))
        raise SystemExit(0)
    lines = output.splitlines()
    for index, line in enumerate(lines):
        if "LC_VERSION_MIN_MACOSX" not in line:
            continue
        for follow in lines[index + 1:index + 5]:
            version_match = re.search(r"\bversion\s+([0-9]+(?:\.[0-9]+){0,2})", follow)
            if version_match:
                print(version_match.group(1))
                raise SystemExit(0)
print("")
PY
}

version_greater_than() {
  local left_version="$1"
  local right_version="$2"
  python3 - "${left_version}" "${right_version}" <<'PY'
import sys


def parse(value: str) -> tuple[int, ...]:
    parts = [int(part) for part in value.split('.') if part]
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts[:3])


raise SystemExit(0 if parse(sys.argv[1]) > parse(sys.argv[2]) else 1)
PY
}

assert_binary_macos_min_version_not_newer_than() {
  local binary_path="$1"
  local max_version="$2"
  if [ ! -f "${binary_path}" ]; then
    return
  fi
  local file_description
  file_description="$(file -b "${binary_path}" 2>/dev/null || true)"
  case "${file_description}" in
    *Mach-O*) ;;
    *) return ;;
  esac
  local min_version
  min_version="$(extract_binary_macos_min_version "${binary_path}")"
  if [ -z "${min_version}" ]; then
    echo "Unable to resolve minimum macOS version for ${binary_path}" >&2
    exit 1
  fi
  if version_greater_than "${min_version}" "${max_version}"; then
    echo "Binary requires macOS ${min_version}, newer than allowed ${max_version}: ${binary_path}" >&2
    exit 1
  fi
}

validate_runtime_tree_architecture() {
  local runtime_dir="$1"
  local expected_arch="$2"
  if [ ! -d "${runtime_dir}" ]; then
    return
  fi
  find "${runtime_dir}" \( -perm -111 -o -name '*.dylib' -o -name '*.so' -o -name '*.node' \) -type f | while IFS= read -r binary_path; do
    validate_binary_architecture "${binary_path}" "${expected_arch}"
  done
}

validate_runtime_tree_macos_min_version() {
  local runtime_dir="$1"
  local max_version="$2"
  if [ ! -d "${runtime_dir}" ]; then
    return
  fi
  find "${runtime_dir}" \( -perm -111 -o -name '*.dylib' -o -name '*.so' -o -name '*.node' \) -type f | while IFS= read -r binary_path; do
    assert_binary_macos_min_version_not_newer_than "${binary_path}" "${max_version}"
  done
}

collect_runtime_tree_macos_min_version_failures() {
  local runtime_dir="$1"
  local max_version="$2"
  if [ ! -d "${runtime_dir}" ]; then
    return
  fi
  find "${runtime_dir}" \( -perm -111 -o -name '*.dylib' -o -name '*.so' -o -name '*.node' \) -type f | while IFS= read -r binary_path; do
    local file_description min_version
    file_description="$(file -b "${binary_path}" 2>/dev/null || true)"
    case "${file_description}" in
      *Mach-O*) ;;
      *) continue ;;
    esac
    min_version="$(extract_binary_macos_min_version "${binary_path}")"
    if [ -z "${min_version}" ]; then
      printf 'unknown\t%s\n' "${binary_path}"
      continue
    fi
    if version_greater_than "${min_version}" "${max_version}"; then
      printf '%s\t%s\n' "${min_version}" "${binary_path}"
    fi
  done
}

report_macos_min_version_failures() {
  local runtime_dir="$1"
  local max_version="$2"
  local label="$3"
  local failures
  failures="$(collect_runtime_tree_macos_min_version_failures "${runtime_dir}" "${max_version}")"
  if [ -z "${failures}" ]; then
    return
  fi
  echo "${label} contains binaries newer than macOS ${max_version}:" >&2
  printf '%s\n' "${failures}" >&2
  exit 1
}

relative_path() {
  local target_path="$1"
  local start_path="$2"
  python3 - "${target_path}" "${start_path}" <<'PY'
import os
import sys
print(os.path.relpath(sys.argv[1], sys.argv[2]))
PY
}

detect_site_packages() {
  local root="$1"
  for candidate in "${root}"/lib/python*/site-packages; do
    if [ -d "${candidate}" ]; then
      printf '%s\n' "${candidate}"
      return
    fi
  done
  printf '\n'
}

resolve_python_framework_source() {
  if [ -n "${SOURCE_PYTHON_FRAMEWORK}" ]; then
    printf '%s\n' "${SOURCE_PYTHON_FRAMEWORK}"
    return
  fi
  "${SOURCE_PYTHON}" - <<'PY'
import sysconfig
print(f"{sysconfig.get_config_var('PYTHONFRAMEWORKPREFIX')}/{sysconfig.get_config_var('PYTHONFRAMEWORKDIR')}")
PY
}

cleanup_tmp() {
  if [ -n "${TMP_DIR}" ] && [ -d "${TMP_DIR}" ]; then
    rm -rf "${TMP_DIR}"
  fi
}

trap cleanup_tmp EXIT

mkdir -p "${STAGING_ROOT}"
TMP_DIR="$(mktemp -d "${STAGING_ROOT}/.tmp.${TARGET_ARCH}.XXXXXX")"
TMP_ARCH_DIR="${TMP_DIR}/${TARGET_ARCH}"
STAGED_RUNTIME_DIR="${TMP_ARCH_DIR}/dj_runtime_py"
STAGED_UNLOCK_WORKER_DIR="${TMP_ARCH_DIR}/unlock_music_node"
STAGED_PYTHON_DIR="${TMP_ARCH_DIR}/python"
STAGED_PYTHON_FRAMEWORK_DEST="${STAGED_PYTHON_DIR}/Python.framework"
STAGED_FF_DIR="${TMP_ARCH_DIR}/ff"

assert_file_exists "${RUNTIME_SOURCE_DIR}/dj_runtime_py/dj_runtime_py/__main__.py" "runtime source"
assert_file_exists "${SOURCE_PYTHON}" "source python"
assert_file_exists "${RUNTIME_SOURCE_DIR}/unlock_music_node/src/main.js" "unlock music worker"
assert_file_exists "${SOURCE_FFMPEG}" "source ffmpeg"
assert_file_exists "${SOURCE_FFPROBE}" "source ffprobe"

SOURCE_SITE_PACKAGES="$(detect_site_packages "${SOURCE_VENV}")"
if [ -z "${SOURCE_SITE_PACKAGES}" ]; then
  echo "Unable to resolve source site-packages under ${SOURCE_VENV}" >&2
  exit 1
fi

PYTHON_FRAMEWORK_SOURCE="$(resolve_python_framework_source)"
assert_file_exists "${PYTHON_FRAMEWORK_SOURCE}/Versions/3.11/bin/python3.11" "python framework source"
if [ "${PYTHON_FRAMEWORK_SOURCE}" = "/usr/local/opt/python@3.11/Frameworks/Python.framework" ]; then
  echo "Source Python.framework is Homebrew python@3.11 under /usr/local and is likely too new for macOS ${TARGET_MACOS_MIN_VERSION}. Provide DJ_RUNTIME_SOURCE_PYTHON_FRAMEWORK and DJ_RUNTIME_SOURCE_VENV built for the release target." >&2
fi
if [ -z "${SOURCE_NODE_BIN}" ]; then
  SOURCE_NODE_BIN="$(find_first_match "${SOURCE_SITE_PACKAGES}" '*/nodejs_wheel/bin/node')"
fi
assert_file_exists "${SOURCE_NODE_BIN}" "source node binary"
assert_binary_macos_min_version_not_newer_than "${SOURCE_NODE_BIN}" "${TARGET_MACOS_MIN_VERSION}"
assert_binary_macos_min_version_not_newer_than "${SOURCE_FFMPEG}" "${TARGET_MACOS_MIN_VERSION}"
assert_binary_macos_min_version_not_newer_than "${SOURCE_FFPROBE}" "${TARGET_MACOS_MIN_VERSION}"
assert_binary_macos_min_version_not_newer_than "${PYTHON_FRAMEWORK_SOURCE}/Versions/3.11/bin/python3.11" "${TARGET_MACOS_MIN_VERSION}"
assert_binary_macos_min_version_not_newer_than "${PYTHON_FRAMEWORK_SOURCE}/Versions/3.11/Python" "${TARGET_MACOS_MIN_VERSION}"
for dylib_name in pyexpat _ssl _hashlib _sqlite3 _lzma _decimal; do
  dylib_candidate="$(find_first_match "${PYTHON_FRAMEWORK_SOURCE}/Versions/3.11/lib/python3.11/lib-dynload" "*${dylib_name}*.so")"
  if [ -n "${dylib_candidate}" ]; then
    assert_binary_macos_min_version_not_newer_than "${dylib_candidate}" "${TARGET_MACOS_MIN_VERSION}"
  fi
done

mkdir -p "${TMP_ARCH_DIR}"
rsync -a --delete --exclude '.pytest_cache' --exclude '__pycache__' --exclude '.DS_Store' "${RUNTIME_SOURCE_DIR}/dj_runtime_py" "${TMP_ARCH_DIR}/"
mkdir -p "${STAGED_RUNTIME_DIR}/.venv"
rsync -a --delete --exclude '*.pyc' "${SOURCE_VENV}/" "${STAGED_RUNTIME_DIR}/.venv/"
rsync -a --delete --exclude '.DS_Store' "${RUNTIME_SOURCE_DIR}/unlock_music_node" "${TMP_ARCH_DIR}/"
mkdir -p "${STAGED_FF_DIR}"
cp -f "${SOURCE_FFMPEG}" "${STAGED_FF_DIR}/ffmpeg"
cp -f "${SOURCE_FFPROBE}" "${STAGED_FF_DIR}/ffprobe"
chmod 755 "${STAGED_FF_DIR}/ffmpeg" "${STAGED_FF_DIR}/ffprobe"
FF_ZLIB_SOURCE=""
for ff_binary in "${STAGED_FF_DIR}/ffmpeg" "${STAGED_FF_DIR}/ffprobe"; do
  if [ ! -f "${ff_binary}" ]; then
    continue
  fi
  if [ -z "${FF_ZLIB_SOURCE}" ]; then
    FF_ZLIB_SOURCE="$(otool -L "${ff_binary}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "libz." in value and value.startswith("/"):
        print(value)
        break' || true)"
    if [ -n "${FF_ZLIB_SOURCE}" ]; then
      cp -fL "${FF_ZLIB_SOURCE}" "${STAGED_FF_DIR}/libz.1.dylib"
      chmod 755 "${STAGED_FF_DIR}/libz.1.dylib"
      install_name_tool -id "@loader_path/libz.1.dylib" "${STAGED_FF_DIR}/libz.1.dylib"
    fi
  fi
  if [ -n "${FF_ZLIB_SOURCE}" ]; then
    install_name_tool -change "${FF_ZLIB_SOURCE}" "@loader_path/libz.1.dylib" "${ff_binary}"
  fi
done
rm -f "${STAGED_RUNTIME_DIR}"/test_*.py
rm -rf "${STAGED_RUNTIME_DIR}/dj_runtime_py.egg-info"
rm -rf "${STAGED_RUNTIME_DIR}/.venv/share/man"
rm -rf "${STAGED_RUNTIME_DIR}/.venv/lib/python"*/site-packages/pip "${STAGED_RUNTIME_DIR}/.venv/lib/python"*/site-packages/pip-*.dist-info
rm -rf "${STAGED_RUNTIME_DIR}/.venv/lib/python"*/site-packages/_pytest "${STAGED_RUNTIME_DIR}/.venv/lib/python"*/site-packages/pytest-*.dist-info
rm -rf "${STAGED_RUNTIME_DIR}/.venv/lib/python"*/site-packages/av "${STAGED_RUNTIME_DIR}/.venv/lib/python"*/site-packages/av-*.dist-info
rm -rf "${STAGED_RUNTIME_DIR}/.venv/lib/python"*/site-packages/nodejs_wheel/include "${STAGED_RUNTIME_DIR}/.venv/lib/python"*/site-packages/nodejs_wheel/share
rm -f "${STAGED_RUNTIME_DIR}/.venv/bin/pip" "${STAGED_RUNTIME_DIR}/.venv/bin/pip3" "${STAGED_RUNTIME_DIR}/.venv/bin/pip3.11" "${STAGED_RUNTIME_DIR}/.venv/bin/py.test" "${STAGED_RUNTIME_DIR}/.venv/bin/pytest"

STAGED_SITE_PACKAGES="$(detect_site_packages "${STAGED_RUNTIME_DIR}/.venv")"
if [ -z "${STAGED_SITE_PACKAGES}" ]; then
  echo "Unable to resolve staged site-packages under ${STAGED_RUNTIME_DIR}/.venv" >&2
  exit 1
fi

for package in dj_transcode_core dj_scan_core dj_usb_backup_core pypinyin; do
  if [ ! -e "${SOURCE_SITE_PACKAGES}/${package}" ]; then
    echo "Required package missing from source venv: ${package}" >&2
    exit 1
  fi
  rsync -a --delete "${SOURCE_SITE_PACKAGES}/${package}" "${STAGED_SITE_PACKAGES}/"
done

find "${STAGED_SITE_PACKAGES}" -type d -name '*.dSYM' -prune -exec rm -rf {} +
for candidate in "${STAGED_SITE_PACKAGES}"/__editable__*.pth "${STAGED_SITE_PACKAGES}"/*.dist-info/direct_url.json; do
  if [ -e "${candidate}" ]; then
    rm -f "${candidate}"
  fi
done
rm -f "${STAGED_RUNTIME_DIR}/.venv/pyvenv.cfg"
rm -f "${STAGED_RUNTIME_DIR}/.venv/bin/python" "${STAGED_RUNTIME_DIR}/.venv/bin/python3" "${STAGED_RUNTIME_DIR}/.venv/bin/python3.11"
PY_STDLIB_DIR="${STAGED_RUNTIME_DIR}/.venv/lib/python3.11"
if [ -d "${PY_STDLIB_DIR}" ]; then
  rm -rf "${PY_STDLIB_DIR}/test" "${PY_STDLIB_DIR}/idlelib" "${PY_STDLIB_DIR}/tkinter" "${PY_STDLIB_DIR}/ensurepip" "${PY_STDLIB_DIR}/pydoc_data" "${PY_STDLIB_DIR}/distutils" "${PY_STDLIB_DIR}/unittest" "${PY_STDLIB_DIR}/__pycache__"
  find "${PY_STDLIB_DIR}" -type d -name '__pycache__' -prune -exec rm -rf {} +
fi
rm -rf "${STAGED_SITE_PACKAGES}"/setuptools "${STAGED_SITE_PACKAGES}"/setuptools-*.dist-info
rm -rf "${STAGED_SITE_PACKAGES}"/Cryptodome/SelfTest "${STAGED_SITE_PACKAGES}"/Crypto/SelfTest
rm -f "${STAGED_SITE_PACKAGES}"/google/_upb/_message*.so
rmdir "${STAGED_SITE_PACKAGES}"/google/_upb 2>/dev/null || true
rm -f "${STAGED_SITE_PACKAGES}"/charset_normalizer/*__mypyc*.so
find "${STAGED_SITE_PACKAGES}" -type d -name '__pycache__' -prune -exec rm -rf {} +
assert_match_exists "${STAGED_RUNTIME_DIR}" "*/site-packages/prompt_toolkit-*.dist-info/METADATA" "staged prompt_toolkit metadata"
rm -f "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/corepack" "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/npm" "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/npx"
rm -rf "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/lib"
if [ -f "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/node" ]; then
  cp -f "${SOURCE_NODE_BIN}" "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/node"
fi
chmod 755 "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/node"
STAGED_NODE_BIN="${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/node"
if [ -f "${STAGED_NODE_BIN}" ]; then
  NODE_ZLIB_SOURCE="$(otool -L "${STAGED_NODE_BIN}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "libz." in value and value.startswith("/"):
        print(value)
        break' || true)"
  if [ -n "${NODE_ZLIB_SOURCE}" ]; then
    cp -fL "${NODE_ZLIB_SOURCE}" "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/libz.1.dylib"
    chmod 755 "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/libz.1.dylib"
    install_name_tool -id "@loader_path/libz.1.dylib" "${STAGED_RUNTIME_DIR}/.venv/lib/python3.11/site-packages/nodejs_wheel/bin/libz.1.dylib"
    install_name_tool -change "${NODE_ZLIB_SOURCE}" "@loader_path/libz.1.dylib" "${STAGED_NODE_BIN}"
  fi
fi
for abi3_so in "${STAGED_SITE_PACKAGES}"/dj_*/dj_*.abi3.so; do
  if [ -f "${abi3_so}" ]; then
    so_basename="$(basename "${abi3_so}")"
    install_name_tool -id "@loader_path/${so_basename}" "${abi3_so}"
    otool -L "${abi3_so}" | while IFS= read -r dep_line; do
      dep_pattern="$(printf '%s' "${dep_line}" | sed 's/^[[:space:]]*//' | cut -d' ' -f1)"
      case "${dep_pattern}" in
        /Users/*|/opt/homebrew/*|/usr/local/*|*/target/*)
          dep_basename="$(basename "${dep_pattern}")"
          if [ "${dep_basename}" != "${so_basename}" ]; then
            install_name_tool -change "${dep_pattern}" "@loader_path/${dep_basename}" "${abi3_so}"
          fi
          ;;
      esac
    done
    strip -x "${abi3_so}"
  fi
done

mkdir -p "${STAGED_PYTHON_DIR}"
rsync -a --delete --exclude 'Headers' --exclude 'share' "${PYTHON_FRAMEWORK_SOURCE}/" "${STAGED_PYTHON_FRAMEWORK_DEST}/"
PY_FW_LIB="${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/3.11/lib/python3.11"
rm -rf "${PY_FW_LIB}/test" "${PY_FW_LIB}/idlelib" "${PY_FW_LIB}/tkinter" "${PY_FW_LIB}/ensurepip" "${PY_FW_LIB}/pydoc_data" "${PY_FW_LIB}/distutils" "${PY_FW_LIB}/unittest"
rm -rf "${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/3.11/include"
find "${PY_FW_LIB}" -type d -name '__pycache__' -prune -exec rm -rf {} +
PY_FW_SITE_PACKAGES_LINK="${PY_FW_LIB}/site-packages"
rm -rf "${PY_FW_SITE_PACKAGES_LINK}"
SITE_PACKAGES_RELATIVE_TARGET="$(relative_path "${STAGED_SITE_PACKAGES}" "${PY_FW_LIB}")"
ln -sfn "${SITE_PACKAGES_RELATIVE_TARGET}" "${PY_FW_SITE_PACKAGES_LINK}"
ln -sfn 3.11 "${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/Current"
PYTHON_DYLIB_DEST="${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/3.11/Python"
PYTHON_BIN_DEST="${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/3.11/bin/python3.11"
PYTHON_APP_DIR_DEST="${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/3.11/Resources/Python_app"
PYTHON_APP_BIN_DEST="${PYTHON_APP_DIR_DEST}/Contents/MacOS/Python"
install_name_tool -id "@loader_path/Python" "${PYTHON_DYLIB_DEST}"
PYTHON_DYLIB_SOURCE="$(otool -L "${PYTHON_BIN_DEST}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if value.endswith("/Python") and "Python.framework" in value:
        print(value)
        break')"
if [ -z "${PYTHON_DYLIB_SOURCE}" ]; then
  echo "Unable to resolve Python dylib source for staging" >&2
  exit 1
fi
mv "${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/3.11/Resources/Python.app" "${PYTHON_APP_DIR_DEST}"
python3 - "${PYTHON_BIN_DEST}" <<'PY'
from pathlib import Path
import sys
binary_path = Path(sys.argv[1])
data = binary_path.read_bytes()
old = b'Resources/Python.app/Contents/MacOS/Python\x00'
new = b'Resources/Python_app/Contents/MacOS/Python\x00'
if old not in data:
    raise SystemExit('python3.11 stub path not found for patching')
binary_path.write_bytes(data.replace(old, new))
PY
install_name_tool -change "${PYTHON_DYLIB_SOURCE}" "@executable_path/../Python" "${PYTHON_BIN_DEST}"
install_name_tool -change "${PYTHON_DYLIB_SOURCE}" "@executable_path/../../../../Python" "${PYTHON_APP_BIN_DEST}"
PY_LIB_DYNLOAD_DIR="${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/3.11/lib/python3.11/lib-dynload"
SSL_MODULE=""
HASHLIB_MODULE=""
for candidate in "${PY_LIB_DYNLOAD_DIR}"/_ssl*.so; do
  if [ -f "${candidate}" ]; then
    SSL_MODULE="${candidate}"
    break
  fi
done
for candidate in "${PY_LIB_DYNLOAD_DIR}"/_hashlib*.so; do
  if [ -f "${candidate}" ]; then
    HASHLIB_MODULE="${candidate}"
    break
  fi
done
OPENSSL_LIBSSL_SOURCE=""
OPENSSL_LIBCRYPTO_SOURCE=""
if [ -n "${SSL_MODULE}" ]; then
  OPENSSL_LIBSSL_SOURCE="$(otool -L "${SSL_MODULE}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "libssl." in value:
        print(value)
        break')"
  OPENSSL_LIBCRYPTO_SOURCE="$(otool -L "${SSL_MODULE}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "libcrypto." in value:
        print(value)
        break')"
fi
if [ -z "${OPENSSL_LIBCRYPTO_SOURCE}" ] && [ -n "${HASHLIB_MODULE}" ]; then
  OPENSSL_LIBCRYPTO_SOURCE="$(otool -L "${HASHLIB_MODULE}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "libcrypto." in value:
        print(value)
        break')"
fi
if [ -z "${SSL_MODULE}" ]; then
  echo "Python _ssl module not found in staged framework" >&2
  exit 1
fi
if [ -n "${OPENSSL_LIBSSL_SOURCE}" ] && [ -n "${OPENSSL_LIBCRYPTO_SOURCE}" ]; then
  cp -fL "${OPENSSL_LIBSSL_SOURCE}" "${PY_LIB_DYNLOAD_DIR}/libssl.3.dylib"
  cp -fL "${OPENSSL_LIBCRYPTO_SOURCE}" "${PY_LIB_DYNLOAD_DIR}/libcrypto.3.dylib"
  chmod 755 "${PY_LIB_DYNLOAD_DIR}/libssl.3.dylib" "${PY_LIB_DYNLOAD_DIR}/libcrypto.3.dylib"
  install_name_tool -id "@loader_path/libssl.3.dylib" "${PY_LIB_DYNLOAD_DIR}/libssl.3.dylib"
  install_name_tool -id "@loader_path/libcrypto.3.dylib" "${PY_LIB_DYNLOAD_DIR}/libcrypto.3.dylib"
  install_name_tool -change "${OPENSSL_LIBSSL_SOURCE}" "@loader_path/libssl.3.dylib" "${SSL_MODULE}"
  install_name_tool -change "${OPENSSL_LIBCRYPTO_SOURCE}" "@loader_path/libcrypto.3.dylib" "${SSL_MODULE}"
  if [ -n "${HASHLIB_MODULE}" ]; then
    install_name_tool -change "${OPENSSL_LIBCRYPTO_SOURCE}" "@loader_path/libcrypto.3.dylib" "${HASHLIB_MODULE}"
  fi
  install_name_tool -change "${OPENSSL_LIBCRYPTO_SOURCE}" "@loader_path/libcrypto.3.dylib" "${PY_LIB_DYNLOAD_DIR}/libssl.3.dylib"
  LIBSSL_LIBCRYPTO_REF="$(otool -L "${PY_LIB_DYNLOAD_DIR}/libssl.3.dylib" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "libcrypto" in value and value.startswith("/"):
        print(value)
        break' || true)"
  if [ -n "${LIBSSL_LIBCRYPTO_REF}" ] && [ "${LIBSSL_LIBCRYPTO_REF}" != "@loader_path/libcrypto.3.dylib" ]; then
    install_name_tool -change "${LIBSSL_LIBCRYPTO_REF}" "@loader_path/libcrypto.3.dylib" "${PY_LIB_DYNLOAD_DIR}/libssl.3.dylib"
  fi
fi
SQLITE3_MODULE=""
for candidate in "${PY_LIB_DYNLOAD_DIR}"/_sqlite3*.so; do
  if [ -f "${candidate}" ]; then
    SQLITE3_MODULE="${candidate}"
    break
  fi
done
if [ -n "${SQLITE3_MODULE}" ]; then
  SQLITE3_DYLIB_SOURCE="$(otool -L "${SQLITE3_MODULE}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "libsqlite3" in value:
        print(value)
        break')"
  if [ -n "${SQLITE3_DYLIB_SOURCE}" ]; then
    cp -fL "${SQLITE3_DYLIB_SOURCE}" "${PY_LIB_DYNLOAD_DIR}/libsqlite3.dylib"
    chmod 755 "${PY_LIB_DYNLOAD_DIR}/libsqlite3.dylib"
    install_name_tool -id "@loader_path/libsqlite3.dylib" "${PY_LIB_DYNLOAD_DIR}/libsqlite3.dylib"
    install_name_tool -change "${SQLITE3_DYLIB_SOURCE}" "@loader_path/libsqlite3.dylib" "${SQLITE3_MODULE}"
  fi
fi
LZMA_MODULE=""
for candidate in "${PY_LIB_DYNLOAD_DIR}"/_lzma*.so; do
  if [ -f "${candidate}" ]; then
    LZMA_MODULE="${candidate}"
    break
  fi
done
if [ -n "${LZMA_MODULE}" ]; then
  LZMA_DYLIB_SOURCE="$(otool -L "${LZMA_MODULE}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "liblzma" in value:
        print(value)
        break')"
  if [ -n "${LZMA_DYLIB_SOURCE}" ]; then
    cp -fL "${LZMA_DYLIB_SOURCE}" "${PY_LIB_DYNLOAD_DIR}/liblzma.5.dylib"
    chmod 755 "${PY_LIB_DYNLOAD_DIR}/liblzma.5.dylib"
    install_name_tool -id "@loader_path/liblzma.5.dylib" "${PY_LIB_DYNLOAD_DIR}/liblzma.5.dylib"
    install_name_tool -change "${LZMA_DYLIB_SOURCE}" "@loader_path/liblzma.5.dylib" "${LZMA_MODULE}"
  fi
fi
ZLIB_DYLIB_SOURCE=""
for zlib_module in "${PY_LIB_DYNLOAD_DIR}"/binascii*.so "${PY_LIB_DYNLOAD_DIR}"/zlib*.so; do
  if [ ! -f "${zlib_module}" ]; then
    continue
  fi
  if [ -z "${ZLIB_DYLIB_SOURCE}" ]; then
    ZLIB_DYLIB_SOURCE="$(otool -L "${zlib_module}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "libz." in value and value.startswith("/"):
        print(value)
        break' || true)"
    if [ -n "${ZLIB_DYLIB_SOURCE}" ]; then
      cp -fL "${ZLIB_DYLIB_SOURCE}" "${PY_LIB_DYNLOAD_DIR}/libz.1.dylib"
      chmod 755 "${PY_LIB_DYNLOAD_DIR}/libz.1.dylib"
      install_name_tool -id "@loader_path/libz.1.dylib" "${PY_LIB_DYNLOAD_DIR}/libz.1.dylib"
    fi
  fi
  if [ -n "${ZLIB_DYLIB_SOURCE}" ]; then
    install_name_tool -change "${ZLIB_DYLIB_SOURCE}" "@loader_path/libz.1.dylib" "${zlib_module}"
  fi
done
DECIMAL_MODULE=""
for candidate in "${PY_LIB_DYNLOAD_DIR}"/_decimal*.so; do
  if [ -f "${candidate}" ]; then
    DECIMAL_MODULE="${candidate}"
    break
  fi
done
if [ -n "${DECIMAL_MODULE}" ]; then
  MPDEC_DYLIB_SOURCE="$(otool -L "${DECIMAL_MODULE}" | python3 -c 'import sys
for line in sys.stdin:
    value = line.strip().split(" ", 1)[0]
    if "libmpdec" in value:
        print(value)
        break')"
  if [ -n "${MPDEC_DYLIB_SOURCE}" ]; then
    cp -fL "${MPDEC_DYLIB_SOURCE}" "${PY_LIB_DYNLOAD_DIR}/libmpdec.4.dylib"
    chmod 755 "${PY_LIB_DYNLOAD_DIR}/libmpdec.4.dylib"
    install_name_tool -id "@loader_path/libmpdec.4.dylib" "${PY_LIB_DYNLOAD_DIR}/libmpdec.4.dylib"
    install_name_tool -change "${MPDEC_DYLIB_SOURCE}" "@loader_path/libmpdec.4.dylib" "${DECIMAL_MODULE}"
  fi
fi

chmod 755 "${PYTHON_BIN_DEST}" "${PYTHON_DYLIB_DEST}" "${PYTHON_APP_BIN_DEST}"
assert_file_exists "${STAGED_RUNTIME_DIR}/dj_runtime_py/__main__.py" "staged dj_runtime_py"
assert_file_exists "${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/3.11/bin/python3.11" "staged python executable"
assert_file_exists "${STAGED_PYTHON_FRAMEWORK_DEST}/Versions/3.11/Python" "staged python dylib"
assert_match_exists "${STAGED_PYTHON_FRAMEWORK_DEST}" '*/pyexpat*.so' 'staged pyexpat'
assert_match_exists "${STAGED_SITE_PACKAGES}" '*/nodejs_wheel/bin/node' 'staged node executable'
assert_file_exists "${STAGED_FF_DIR}/ffmpeg" 'staged ffmpeg'
assert_file_exists "${STAGED_FF_DIR}/ffprobe" 'staged ffprobe'
assert_match_exists "${STAGED_SITE_PACKAGES}" '*/dj_scan_core/dj_scan_core.abi3.so' 'staged dj_scan_core'
assert_match_exists "${STAGED_SITE_PACKAGES}" '*/dj_transcode_core/dj_transcode_core.abi3.so' 'staged dj_transcode_core'
assert_match_exists "${STAGED_SITE_PACKAGES}" '*/dj_usb_backup_core/dj_usb_backup_core.abi3.so' 'staged dj_usb_backup_core'

thin_runtime_tree_to_architecture "${STAGED_RUNTIME_DIR}" "${TARGET_ARCH}"
thin_runtime_tree_to_architecture "${STAGED_PYTHON_FRAMEWORK_DEST}" "${TARGET_ARCH}"
thin_runtime_tree_to_architecture "${STAGED_FF_DIR}" "${TARGET_ARCH}"
validate_runtime_tree_architecture "${STAGED_RUNTIME_DIR}" "${TARGET_ARCH}"
validate_runtime_tree_architecture "${STAGED_PYTHON_FRAMEWORK_DEST}" "${TARGET_ARCH}"
validate_runtime_tree_architecture "${STAGED_FF_DIR}" "${TARGET_ARCH}"
report_macos_min_version_failures "${STAGED_RUNTIME_DIR}" "${TARGET_MACOS_MIN_VERSION}" "Staged runtime"
report_macos_min_version_failures "${STAGED_PYTHON_FRAMEWORK_DEST}" "${TARGET_MACOS_MIN_VERSION}" "Staged Python.framework"
report_macos_min_version_failures "${STAGED_FF_DIR}" "${TARGET_MACOS_MIN_VERSION}" "Staged ff tools"
validate_runtime_tree_macos_min_version "${STAGED_RUNTIME_DIR}" "${TARGET_MACOS_MIN_VERSION}"
validate_runtime_tree_macos_min_version "${STAGED_PYTHON_FRAMEWORK_DEST}" "${TARGET_MACOS_MIN_VERSION}"
validate_runtime_tree_macos_min_version "${STAGED_FF_DIR}" "${TARGET_MACOS_MIN_VERSION}"

find "${STAGED_RUNTIME_DIR}" \( -perm -111 -o -name '*.dylib' -o -name '*.so' -o -name '*.node' \) -type f | while IFS= read -r binary_path; do
  assert_no_external_deps "${binary_path}"
done
find "${STAGED_PYTHON_FRAMEWORK_DEST}" \( -perm -111 -o -name '*.dylib' -o -name '*.so' -o -name '*.node' \) -type f | while IFS= read -r binary_path; do
  assert_no_external_deps "${binary_path}"
done
find "${STAGED_FF_DIR}" \( -perm -111 -o -name '*.dylib' -o -name '*.so' -o -name '*.node' \) -type f | while IFS= read -r binary_path; do
  assert_no_external_deps "${binary_path}"
done

rm -rf "${TARGET_DIR}"
mv "${TMP_ARCH_DIR}" "${TARGET_DIR}"
rmdir "${TMP_DIR}" 2>/dev/null || true
TMP_DIR=""

echo "Prepared runtime staging at ${TARGET_DIR}"
echo "arch=${TARGET_ARCH} min_macos=${TARGET_MACOS_MIN_VERSION} python=${SOURCE_PYTHON} node=${SOURCE_NODE_BIN} ffmpeg=${SOURCE_FFMPEG} ffprobe=${SOURCE_FFPROBE}"
