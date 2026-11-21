#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARCH="${DJ_RELEASE_ARCH:-x86_64}"
case "${ARCH}" in
  x86_64|arm64) ;;
  *) echo "Unsupported DJ_RELEASE_ARCH: ${ARCH}" >&2; exit 2 ;;
esac
OUTPUT_ROOT="${DJ_RELEASE_INPUTS_ROOT:-${REPO_ROOT}/runtime_staging_sources/macos/${ARCH}}"
if [ "${ARCH}" = "arm64" ]; then CARGO_ARCH=aarch64; else CARGO_ARCH=x86_64; fi
BUILD_ROOT="${DJ_RELEASE_BUILD_ROOT:-${REPO_ROOT}/runtime_staging_sources/.build-${ARCH}}"
TARGET_MACOS_MIN_VERSION="${DJ_RUNTIME_TARGET_MACOS_MIN_VERSION:-10.15}"
PYTHON_VERSION="${DJ_RELEASE_PYTHON_VERSION:-3.11.15}"
NODE_VERSION="${DJ_RELEASE_NODE_VERSION:-20.19.0}"
FFMPEG_VERSION="${DJ_RELEASE_FFMPEG_VERSION:-8.0}"
OPENSSL_VERSION="${DJ_RELEASE_OPENSSL_VERSION:-3.0.18}"
XZ_VERSION="${DJ_RELEASE_XZ_VERSION:-5.8.1}"
SQLITE_VERSION="${DJ_RELEASE_SQLITE_VERSION:-3460100}"
LIBFFI_VERSION="${DJ_RELEASE_LIBFFI_VERSION:-3.4.8}"
ZLIB_VERSION="${DJ_RELEASE_ZLIB_VERSION:-1.3.1}"
LAME_VERSION="${DJ_RELEASE_LAME_VERSION:-3.100}"
BZIP2_VERSION="${DJ_RELEASE_BZIP2_VERSION:-1.0.8}"
READLINE_VERSION="${DJ_RELEASE_READLINE_VERSION:-8.2}"
TCL_VERSION="${DJ_RELEASE_TCL_VERSION:-8.6.15}"
TK_VERSION="${DJ_RELEASE_TK_VERSION:-8.6.15}"
NASM_BIN="${DJ_RELEASE_NASM_BIN:-$(command -v nasm || true)}"
JOBS="${DJ_RELEASE_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 8)}"

SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
CC="${CC:-$(xcrun --find clang)}"
CXX="${CXX:-$(xcrun --find clang++)}"
AR="${AR:-$(xcrun --find ar)}"
RANLIB="${RANLIB:-$(xcrun --find ranlib)}"
STRIP_BIN="${STRIP_BIN:-$(xcrun --find strip)}"
MACOS_CFLAGS="-arch ${ARCH} -mmacosx-version-min=${TARGET_MACOS_MIN_VERSION} -isysroot ${SDKROOT}"
MACOS_CXXFLAGS="${MACOS_CFLAGS}"
MACOS_LDFLAGS="-arch ${ARCH} -mmacosx-version-min=${TARGET_MACOS_MIN_VERSION} -isysroot ${SDKROOT}"

PREFIX="${OUTPUT_ROOT}/prefix"
PYTHON_PREFIX="${OUTPUT_ROOT}/python-prefix"
PYTHON_FRAMEWORK_DIR="${OUTPUT_ROOT}/Python.framework"
VENV_DIR="${OUTPUT_ROOT}/venv"
NODE_BIN="${OUTPUT_ROOT}/node/bin/node"
FF_DIR="${OUTPUT_ROOT}/ff"
STAMP_DIR="${BUILD_ROOT}/stamps"
SRC_DIR="${BUILD_ROOT}/src"
WORK_DIR="${BUILD_ROOT}/work"
ASCII_PKGCONFIG_ROOT="/tmp/dj_release_pkgconfig"
ASCII_ZLIB_PREFIX="${ASCII_PKGCONFIG_ROOT}/zlib-prefix"
ASCII_ZLIB_PKGCONFIG_DIR="${ASCII_ZLIB_PREFIX}/lib/pkgconfig"

mkdir -p "${OUTPUT_ROOT}" "${BUILD_ROOT}" "${STAMP_DIR}" "${SRC_DIR}" "${WORK_DIR}" "${PREFIX}" "${FF_DIR}"

LOCAL_ARCHIVE_DIRS=(
  "${REPO_ROOT}/tmp_ffmpeg_universal_builder/.source-cache"
  "${REPO_ROOT}/tmp_ffmpeg_universal_builder/build"
)

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }
}

need curl
need tar
need make
need perl
need pkg-config
need python3
need git
need xcrun
need clang
need cargo
need rustc
need install_name_tool
need otool
need lipo
need patch

if [ -z "${NASM_BIN}" ]; then
  echo "Missing nasm. Install it first so ffmpeg can be built." >&2
  exit 1
fi

export SDKROOT CC CXX AR RANLIB
export MACOSX_DEPLOYMENT_TARGET="${TARGET_MACOS_MIN_VERSION}"
export CFLAGS="${MACOS_CFLAGS}"
export CXXFLAGS="${MACOS_CXXFLAGS}"
export LDFLAGS="${MACOS_LDFLAGS}"
export CPPFLAGS="-I${PREFIX}/include"
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="${PREFIX}/lib/pkgconfig"
export PATH="${PREFIX}/bin:${HOME}/.cargo/bin:${PATH}"

copy_local_archive_if_available() {
  local archive_name="$1"
  local dest="$2"
  local archive_dir candidate
  for archive_dir in "${LOCAL_ARCHIVE_DIRS[@]}"; do
    candidate="${archive_dir}/${archive_name}"
    if [ -f "${candidate}" ]; then
      cp -f "${candidate}" "${dest}"
      return 0
    fi
  done
  return 1
}

prepare_ascii_zlib_pkgconfig() {
  local src_pc="${PREFIX}/lib/pkgconfig/zlib.pc"
  [ -f "${src_pc}" ] || return 1
  rm -rf "${ASCII_ZLIB_PREFIX}"
  mkdir -p "${ASCII_ZLIB_PREFIX}/include" "${ASCII_ZLIB_PREFIX}/lib" "${ASCII_ZLIB_PKGCONFIG_DIR}"
  cp -f "${PREFIX}/include/zlib.h" "${ASCII_ZLIB_PREFIX}/include/zlib.h"
  cp -f "${PREFIX}/include/zconf.h" "${ASCII_ZLIB_PREFIX}/include/zconf.h"
  cp -f "${PREFIX}/lib/libz.a" "${ASCII_ZLIB_PREFIX}/lib/libz.a"
  if [ -f "${PREFIX}/lib/libz.dylib" ]; then
    cp -f "${PREFIX}/lib/libz.dylib" "${ASCII_ZLIB_PREFIX}/lib/libz.dylib"
  fi
  python3 - "$src_pc" "${ASCII_ZLIB_PKGCONFIG_DIR}/zlib.pc" "${ASCII_ZLIB_PREFIX}" <<'PY'
from pathlib import Path
import re
import sys
src = Path(sys.argv[1]).read_text()
dst = Path(sys.argv[2])
prefix = sys.argv[3]
version = re.search(r'^Version:\s*(.+)$', src, re.M)
libs = re.search(r'^Libs:\s*(.+)$', src, re.M)
cflags = re.search(r'^Cflags:\s*(.+)$', src, re.M)
dst.write_text(
    f"prefix={prefix}\n"
    "exec_prefix=${prefix}\n"
    "libdir=${exec_prefix}/lib\n"
    "sharedlibdir=${libdir}\n"
    "includedir=${prefix}/include\n\n"
    "Name: zlib\n"
    "Description: zlib compression library\n"
    f"Version: {version.group(1) if version else '1.0'}\n"
    "Requires:\n"
    f"Libs: {libs.group(1) if libs else '-L${{libdir}} -lz'}\n"
    f"Cflags: {cflags.group(1) if cflags else '-I${{includedir}}'}\n"
)
PY
}

patch_node_v8_zlib() {
  local node_src="$1"
  local zutil_header="${node_src}/deps/v8/third_party/zlib/zutil.h"
  [ -f "${zutil_header}" ] || return 1
  python3 - "$zutil_header" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
old = """#if defined(MACOS) || defined(TARGET_OS_MAC)\n#  define OS_CODE  7\n#  ifndef Z_SOLO\n#    if defined(__MWERKS__) && __dest_os != __be_os && __dest_os != __win32_os\n#      include <unix.h> /* for fdopen */\n#    else\n#      ifndef fdopen\n#        define fdopen(fd,mode) NULL /* No fdopen() */\n#      endif\n#    endif\n#  endif\n#endif\n"""
new = """#if defined(MACOS)\n#  define OS_CODE  7\n#  ifndef Z_SOLO\n#    if defined(__MWERKS__) && __dest_os != __be_os && __dest_os != __win32_os\n#      include <unix.h> /* for fdopen */\n#    else\n#      ifndef fdopen\n#        define fdopen(fd,mode) NULL /* No fdopen() */\n#      endif\n#    endif\n#  endif\n#endif\n"""
if old not in text:
    raise SystemExit(f"expected zutil.h block not found in {path}")
path.write_text(text.replace(old, new, 1))
PY
}

fetch() {
  local url="$1"
  local dest="$2"
  local archive_name
  archive_name="$(basename "${dest}")"
  if [ -f "${dest}" ]; then
    return
  fi
  if copy_local_archive_if_available "${archive_name}" "${dest}"; then
    return
  fi
  curl --http1.1 -L --fail --retry 3 --retry-all-errors --connect-timeout 20 --max-time 1800 -o "${dest}" "${url}"
}

extract_tar() {
  local archive="$1"
  local dest_dir="$2"
  rm -rf "${dest_dir}"
  mkdir -p "${dest_dir}"
  tar -xf "${archive}" -C "${dest_dir}" --strip-components=1
}

assert_minos() {
  local binary="$1"
  local max_version="$2"
  python3 - "$binary" "$max_version" <<'PY'
import re, subprocess, sys
from pathlib import Path
binary = Path(sys.argv[1])
max_version = tuple(int(x) for x in (sys.argv[2].split('.') + ['0','0'])[:3])

def parse(v):
    return tuple(int(x) for x in (v.split('.') + ['0','0'])[:3])

def read_minos(path: Path):
    for cmd in (("xcrun","vtool","-show-build",str(path)), ("otool","-l",str(path))):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, check=True).stdout
        except Exception:
            continue
        m = re.search(r"\bminos\s+([0-9]+(?:\.[0-9]+){0,2})", out)
        if m:
            return m.group(1)
        lines = out.splitlines()
        for i, line in enumerate(lines):
            if "LC_VERSION_MIN_MACOSX" not in line:
                continue
            for follow in lines[i+1:i+5]:
                vm = re.search(r"\bversion\s+([0-9]+(?:\.[0-9]+){0,2})", follow)
                if vm:
                    return vm.group(1)
    raise SystemExit(f"Unable to determine min macOS version for {path}")

minos = read_minos(binary)
if parse(minos) > max_version:
    raise SystemExit(f"{binary} requires macOS {minos}, newer than {sys.argv[2]}")
print(f"verified {binary} minos={minos}")
PY
}

build_zlib() {
  local stamp="${STAMP_DIR}/zlib"
  [ -f "${stamp}" ] && return
  local archive="${SRC_DIR}/zlib-${ZLIB_VERSION}.tar.gz"
  local src="${WORK_DIR}/zlib"
  fetch "https://zlib.net/fossils/zlib-${ZLIB_VERSION}.tar.gz" "${archive}"
  extract_tar "${archive}" "${src}"
  (cd "${src}" && ./configure --prefix="${PREFIX}" && make -j"${JOBS}" && make install)
  touch "${stamp}"
}

build_lame() {
  local stamp="${STAMP_DIR}/lame"
  [ -f "${stamp}" ] && return
  local archive="${SRC_DIR}/lame-${LAME_VERSION}.tar.gz"
  local src="${WORK_DIR}/lame"
  fetch "https://downloads.sourceforge.net/project/lame/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz" "${archive}"
  extract_tar "${archive}" "${src}"
  if [ "${ARCH}" = "arm64" ]; then host_arch=aarch64; else host_arch=x86_64; fi
  (cd "${src}" && \
    ./configure \
      --prefix="${PREFIX}" \
      --host=${host_arch}-apple-darwin \
      --disable-shared \
      --enable-static \
      --disable-frontend \
      --disable-decoder \
      --disable-dependency-tracking && \
    make -j"${JOBS}" && make install)
  touch "${stamp}"
}

build_bzip2() {
  local stamp="${STAMP_DIR}/bzip2"
  [ -f "${stamp}" ] && return
  local archive="${SRC_DIR}/bzip2-${BZIP2_VERSION}.tar.gz"
  local src="${WORK_DIR}/bzip2"
  fetch "https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VERSION}.tar.gz" "${archive}"
  extract_tar "${archive}" "${src}"
  (cd "${src}" && make -j"${JOBS}" CC="${CC}" AR="${AR}" RANLIB="${RANLIB}" CFLAGS="${CFLAGS}" LDFLAGS="${LDFLAGS}" && make install PREFIX="${PREFIX}")
  touch "${stamp}"
}

build_xz() {
  local stamp="${STAMP_DIR}/xz"
  [ -f "${stamp}" ] && return
  local archive="${SRC_DIR}/xz-${XZ_VERSION}.tar.gz"
  local src="${WORK_DIR}/xz"
  fetch "https://github.com/tukaani-project/xz/releases/download/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.gz" "${archive}"
  extract_tar "${archive}" "${src}"
  (cd "${src}" && ./configure --prefix="${PREFIX}" --disable-shared --enable-static && make -j"${JOBS}" && make install)
  touch "${stamp}"
}

build_libffi() {
  local stamp="${STAMP_DIR}/libffi"
  [ -f "${stamp}" ] && return
  local archive="${SRC_DIR}/libffi-${LIBFFI_VERSION}.tar.gz"
  local src="${WORK_DIR}/libffi"
  fetch "https://github.com/libffi/libffi/releases/download/v${LIBFFI_VERSION}/libffi-${LIBFFI_VERSION}.tar.gz" "${archive}"
  extract_tar "${archive}" "${src}"
  (cd "${src}" && ./configure --prefix="${PREFIX}" --disable-shared --enable-static && make -j"${JOBS}" && make install)
  touch "${stamp}"
}

build_readline() {
  local stamp="${STAMP_DIR}/readline"
  [ -f "${stamp}" ] && return
  local archive="${SRC_DIR}/readline-${READLINE_VERSION}.tar.gz"
  local src="${WORK_DIR}/readline"
  fetch "https://ftp.gnu.org/gnu/readline/readline-${READLINE_VERSION}.tar.gz" "${archive}"
  extract_tar "${archive}" "${src}"
  (cd "${src}" && ./configure --prefix="${PREFIX}" --disable-shared --enable-static && make -j"${JOBS}" SHLIB_LIBS="" && make install)
  touch "${stamp}"
}

build_sqlite() {
  local stamp="${STAMP_DIR}/sqlite"
  [ -f "${stamp}" ] && return
  local archive="${SRC_DIR}/sqlite-autoconf-${SQLITE_VERSION}.tar.gz"
  local src="${WORK_DIR}/sqlite"
  fetch "https://www.sqlite.org/2024/sqlite-autoconf-${SQLITE_VERSION}.tar.gz" "${archive}"
  extract_tar "${archive}" "${src}"
  (cd "${src}" && ./configure --prefix="${PREFIX}" --disable-shared --enable-static && make -j"${JOBS}" && make install)
  touch "${stamp}"
}

build_openssl() {
  local stamp="${STAMP_DIR}/openssl"
  [ -f "${stamp}" ] && return
  local archive="${SRC_DIR}/openssl-${OPENSSL_VERSION}.tar.gz"
  local src="${WORK_DIR}/openssl"
  fetch "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" "${archive}"
  extract_tar "${archive}" "${src}"
  (cd "${src}" && if [ "${ARCH}" = "arm64" ]; then openssl_target=darwin64-arm64-cc; else openssl_target=darwin64-x86_64-cc; fi && perl ./Configure "${openssl_target}" no-shared no-tests --prefix="${PREFIX}" --openssldir="${PREFIX}/ssl" && make -j"${JOBS}" && make install_sw)
  touch "${stamp}"
}

build_tcl_tk() {
  local stamp="${STAMP_DIR}/tcltk"
  [ -f "${stamp}" ] && return
  local tcl_archive="${SRC_DIR}/tcl${TCL_VERSION}-src.tar.gz"
  local tk_archive="${SRC_DIR}/tk${TK_VERSION}-src.tar.gz"
  local tcl_src="${WORK_DIR}/tcl"
  local tk_src="${WORK_DIR}/tk"
  fetch "https://downloads.sourceforge.net/project/tcl/Tcl/${TCL_VERSION}/tcl${TCL_VERSION}-src.tar.gz" "${tcl_archive}"
  fetch "https://downloads.sourceforge.net/project/tcl/Tcl/${TK_VERSION}/tk${TK_VERSION}-src.tar.gz" "${tk_archive}"
  extract_tar "${tcl_archive}" "${tcl_src}"
  extract_tar "${tk_archive}" "${tk_src}"
  (cd "${tcl_src}/unix" && ./configure --prefix="${PREFIX}" --disable-shared && make -j"${JOBS}" && make install)
  (cd "${tk_src}/unix" && ./configure --prefix="${PREFIX}" --disable-shared --with-tcl="${PREFIX}/lib" && make -j"${JOBS}" && make install)
  touch "${stamp}"
}

build_python() {
  local stamp="${STAMP_DIR}/python"
  [ -f "${stamp}" ] && return
  build_zlib
  build_bzip2
  build_xz
  build_libffi
  build_readline
  build_sqlite
  build_openssl
  local archive="${SRC_DIR}/Python-${PYTHON_VERSION}.tar.xz"
  local src="${WORK_DIR}/python"
  fetch "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" "${archive}"
  extract_tar "${archive}" "${src}"
  rm -rf "${PYTHON_PREFIX}" "${PYTHON_FRAMEWORK_DIR}"
  mkdir -p "${PYTHON_PREFIX}"
  (cd "${src}" && \
    ./configure \
      --prefix="${PYTHON_PREFIX}" \
      --enable-framework="${PYTHON_PREFIX}" \
      --with-openssl="${PREFIX}" \
      --enable-ipv6 \
      ac_cv_prog_HAVE_GCC=no && \
    make -j"${JOBS}" && make install PYTHONAPPSDIR="${PYTHON_PREFIX}/Applications")
  cp -R "${PYTHON_PREFIX}/Python.framework" "${PYTHON_FRAMEWORK_DIR}"
  assert_minos "${PYTHON_FRAMEWORK_DIR}/Versions/3.11/bin/python3.11" "${TARGET_MACOS_MIN_VERSION}"
  assert_minos "${PYTHON_FRAMEWORK_DIR}/Versions/3.11/Python" "${TARGET_MACOS_MIN_VERSION}"
  touch "${stamp}"
}

build_node() {
  local stamp="${STAMP_DIR}/node"
  [ -f "${stamp}" ] && return
  local archive="${SRC_DIR}/node-v${NODE_VERSION}.tar.gz"
  local src="${WORK_DIR}/node"
  fetch "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}.tar.gz" "${archive}"
  extract_tar "${archive}" "${src}"
  patch_node_v8_zlib "${src}"
  prepare_ascii_zlib_pkgconfig
  rm -rf "${OUTPUT_ROOT}/node"
  mkdir -p "${OUTPUT_ROOT}/node"
  (cd "${src}" && \
    export CC_host="${CC}" CXX_host="${CXX}" AR_host="${AR}" && \
    export CC="${CC}" CXX="${CXX}" PYTHON="/usr/bin/python3" && \
    export CPPFLAGS="" CFLAGS="${MACOS_CFLAGS}" CXXFLAGS="${MACOS_CXXFLAGS}" LDFLAGS="${MACOS_LDFLAGS}" && \
    export PKG_CONFIG_PATH="${ASCII_ZLIB_PKGCONFIG_DIR}" PKG_CONFIG_LIBDIR="${ASCII_ZLIB_PKGCONFIG_DIR}" && \
    export GYP_DEFINES="mac_deployment_target=${TARGET_MACOS_MIN_VERSION} node_shared_zlib=true" && \
    if [ "${ARCH}" = "arm64" ]; then node_cpu=arm64; else node_cpu=x64; fi && 
    ./configure --dest-cpu="${node_cpu}" --dest-os=mac --without-npm --shared-zlib --shared-zlib-includes="${ASCII_ZLIB_PREFIX}/include" --shared-zlib-libpath="${ASCII_ZLIB_PREFIX}/lib" && \
    make -j"${JOBS}" V= && \
    mkdir -p "${OUTPUT_ROOT}/node/bin" && cp -f out/Release/node "${NODE_BIN}")
  assert_minos "${NODE_BIN}" "${TARGET_MACOS_MIN_VERSION}"
  touch "${stamp}"
}

build_ffmpeg() {
  local stamp="${STAMP_DIR}/ffmpeg"
  [ -f "${stamp}" ] && return
  build_zlib
  build_lame
  local archive="${SRC_DIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz"
  local src="${WORK_DIR}/ffmpeg"
  fetch "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" "${archive}"
  extract_tar "${archive}" "${src}"
  rm -f "${FF_DIR}/ffmpeg" "${FF_DIR}/ffprobe"
  (cd "${src}" && \
    ./configure \
      --prefix="${WORK_DIR}/ffmpeg-install" \
      --arch=${ARCH} \
      --target-os=darwin \
      --cc="${CC}" \
      --cxx="${CXX}" \
      --ar="${AR}" \
      --ranlib="${RANLIB}" \
      --strip="${STRIP_BIN}" \
      --extra-cflags="${CFLAGS} -I${PREFIX}/include" \
      --extra-ldflags="${LDFLAGS} -L${PREFIX}/lib" \
      --pkg-config-flags="--static" \
      --enable-static \
      --disable-shared \
      --disable-debug \
      --disable-doc \
      --disable-autodetect \
      --disable-network \
      --enable-ffmpeg \
      --enable-ffprobe \
      --disable-avdevice \
      --disable-videotoolbox \
      --disable-audiotoolbox \
      --disable-sdl2 \
      --disable-iconv \
      --enable-zlib \
      --enable-libmp3lame && \
    make -j"${JOBS}" && cp -f ffmpeg ffprobe "${FF_DIR}/")
  chmod 755 "${FF_DIR}/ffmpeg" "${FF_DIR}/ffprobe"
  assert_minos "${FF_DIR}/ffmpeg" "${TARGET_MACOS_MIN_VERSION}"
  assert_minos "${FF_DIR}/ffprobe" "${TARGET_MACOS_MIN_VERSION}"
  touch "${stamp}"
}

build_runtime_venv() {
  local stamp="${STAMP_DIR}/venv"
  [ -f "${stamp}" ] && return
  build_python
  build_node
  rm -rf "${VENV_DIR}"
  "${PYTHON_FRAMEWORK_DIR}/Versions/3.11/bin/python3.11" -m venv "${VENV_DIR}"
  local vpy="${VENV_DIR}/bin/python3.11"
  "${vpy}" -m pip install --upgrade pip setuptools wheel maturin certifi
  local certifi_bundle
  certifi_bundle="$(${vpy} - <<'PY'
import certifi
print(certifi.where())
PY
)"
  export SSL_CERT_FILE="${certifi_bundle}"
  export REQUESTS_CA_BUNDLE="${certifi_bundle}"
  export CURL_CA_BUNDLE="${certifi_bundle}"
  export PIP_CERT="${certifi_bundle}"
  CARGO_BUILD_TARGET="${CARGO_ARCH}-apple-darwin" \
  PYO3_PYTHON="${vpy}" \
  MACOSX_DEPLOYMENT_TARGET="${TARGET_MACOS_MIN_VERSION}" \
  CFLAGS="${MACOS_CFLAGS}" \
  CXXFLAGS="${MACOS_CXXFLAGS}" \
  LDFLAGS="${MACOS_LDFLAGS}" \
  "${vpy}" -m pip install --no-binary=cryptography,orjson,lxml,brotli,PyYAML,curl-cffi \
    "${REPO_ROOT}/runtime/dj_runtime_py"
  CARGO_BUILD_TARGET="${CARGO_ARCH}-apple-darwin" \
  VIRTUAL_ENV="${VENV_DIR}" \
  PATH="${VENV_DIR}/bin:${PATH}" \
  PYO3_PYTHON="${vpy}" \
  MACOSX_DEPLOYMENT_TARGET="${TARGET_MACOS_MIN_VERSION}" \
  CFLAGS="${MACOS_CFLAGS}" \
  CXXFLAGS="${MACOS_CXXFLAGS}" \
  LDFLAGS="${MACOS_LDFLAGS}" \
  "${vpy}" -m maturin develop --pip-path "${VENV_DIR}/bin/pip" -m "${REPO_ROOT}/crates/dj_scan_core/Cargo.toml" --features python-extension
  CARGO_BUILD_TARGET="${CARGO_ARCH}-apple-darwin" \
  VIRTUAL_ENV="${VENV_DIR}" \
  PATH="${VENV_DIR}/bin:${PATH}" \
  PYO3_PYTHON="${vpy}" \
  MACOSX_DEPLOYMENT_TARGET="${TARGET_MACOS_MIN_VERSION}" \
  CFLAGS="${MACOS_CFLAGS}" \
  CXXFLAGS="${MACOS_CXXFLAGS}" \
  LDFLAGS="${MACOS_LDFLAGS}" \
  "${vpy}" -m maturin develop --pip-path "${VENV_DIR}/bin/pip" -m "${REPO_ROOT}/crates/dj_transcode_core/Cargo.toml" --features python-extension
  CARGO_BUILD_TARGET="${CARGO_ARCH}-apple-darwin" \
  VIRTUAL_ENV="${VENV_DIR}" \
  PATH="${VENV_DIR}/bin:${PATH}" \
  PYO3_PYTHON="${vpy}" \
  MACOSX_DEPLOYMENT_TARGET="${TARGET_MACOS_MIN_VERSION}" \
  CFLAGS="${MACOS_CFLAGS}" \
  CXXFLAGS="${MACOS_CXXFLAGS}" \
  LDFLAGS="${MACOS_LDFLAGS}" \
  "${vpy}" -m maturin develop --pip-path "${VENV_DIR}/bin/pip" -m "${REPO_ROOT}/crates/dj_usb_backup_core/Cargo.toml" --features python-extension
  local site_packages
  site_packages="$(${vpy} - <<'PY'
import site
for path in site.getsitepackages():
    if path.endswith('site-packages'):
        print(path)
        break
PY
)"
  if [ -x "${NODE_BIN}" ] && [ -d "${site_packages}/nodejs_wheel/bin" ]; then
    cp -f "${NODE_BIN}" "${site_packages}/nodejs_wheel/bin/node"
    chmod 755 "${site_packages}/nodejs_wheel/bin/node"
  fi
  touch "${stamp}"
}

build_zlib
build_bzip2
build_xz
build_libffi
build_readline
build_sqlite
build_openssl
build_python
build_node
build_ffmpeg
build_runtime_venv

cat <<EOF
Built release inputs:
  Python.framework: ${PYTHON_FRAMEWORK_DIR}
  Venv: ${VENV_DIR}
  Node: ${NODE_BIN}
  FFmpeg: ${FF_DIR}/ffmpeg
  FFprobe: ${FF_DIR}/ffprobe
Prepare staged runtime with:
  DJ_RUNTIME_SOURCE_PYTHON_FRAMEWORK="${PYTHON_FRAMEWORK_DIR}" \
  DJ_RUNTIME_SOURCE_VENV="${VENV_DIR}" \
  DJ_RUNTIME_SOURCE_NODE_BIN="${NODE_BIN}" \
  DJ_RUNTIME_SOURCE_FFMPEG="${FF_DIR}/ffmpeg" \
  DJ_RUNTIME_SOURCE_FFPROBE="${FF_DIR}/ffprobe" \
  DJ_RUNTIME_TARGET_ARCH="${ARCH}" \
  DJ_RUNTIME_SOURCE_PYTHON_FRAMEWORK="${PYTHON_FRAMEWORK_DIR}" \
  DJ_RUNTIME_SOURCE_VENV="${VENV_DIR}" \
  DJ_RUNTIME_SOURCE_NODE_BIN="${NODE_BIN}" \
  DJ_RUNTIME_SOURCE_FFMPEG="${FF_DIR}/ffmpeg" \
  DJ_RUNTIME_SOURCE_FFPROBE="${FF_DIR}/ffprobe" \
  "${REPO_ROOT}/scripts/prepare_runtime_staging.sh"
EOF
