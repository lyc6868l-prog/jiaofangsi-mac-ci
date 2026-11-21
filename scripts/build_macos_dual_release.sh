#!/usr/bin/env bash
set -euo pipefail

# Build one or both macOS architectures. Run on macOS after copying this tree
# from the FAT32 USB disk to a local APFS disk.
#
# Usage:
#   ./scripts/build_macos_dual_release.sh both
#   ./scripts/build_macos_dual_release.sh x86_64
#   ./scripts/build_macos_dual_release.sh arm64
#
# Optional:
#   SKIP_RUNTIME_INPUTS=1    reuse existing runtime_staging_sources/macos/<arch>
#   SKIP_DMG=1               keep only the .app
#   SKIP_FLUTTER_PUB_GET=1   skip flutter pub get

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_ROOT="${REPO_ROOT}/apps/dj_flutter"
VERSION="$(awk '/^version:/ {print $2}' "${APP_ROOT}/pubspec.yaml" | cut -d+ -f1)"
DIST_DIR="${REPO_ROOT}/dist"
APP_BASENAME="教坊司DJ便捷工具"

if [ -z "${VERSION}" ]; then
  echo "Unable to read version from pubspec.yaml" >&2
  exit 1
fi

TARGET="${1:-both}"
case "${TARGET}" in
  both) ARCHS=(x86_64 arm64) ;;
  x86_64|arm64) ARCHS=("${TARGET}") ;;
  *) echo "Usage: $0 [both|x86_64|arm64]" >&2; exit 2 ;;
esac

mkdir -p "${DIST_DIR}"

for ARCH in "${ARCHS[@]}"; do
  echo
  echo "================================================================"
  echo "Building ${ARCH}"
  echo "================================================================"

  OUTPUT_ROOT="${REPO_ROOT}/runtime_staging_sources/macos/${ARCH}"
  export DJ_RELEASE_ARCH="${ARCH}"
  export DJ_RELEASE_INPUTS_ROOT="${OUTPUT_ROOT}"

  if [ "${ARCH}" = "arm64" ]; then
    export DJ_RUNTIME_TARGET_MACOS_MIN_VERSION="${DJ_RUNTIME_TARGET_MACOS_MIN_VERSION:-11.0}"
  else
    export DJ_RUNTIME_TARGET_MACOS_MIN_VERSION="${DJ_RUNTIME_TARGET_MACOS_MIN_VERSION:-10.15}"
  fi

  if [ "${SKIP_RUNTIME_INPUTS:-0}" != "1" ]; then
    "${REPO_ROOT}/scripts/build_macos_release_inputs.sh"
  fi

  PYTHON_FRAMEWORK_DIR="${OUTPUT_ROOT}/Python.framework"
  VENV_DIR="${OUTPUT_ROOT}/venv"
  NODE_BIN="${OUTPUT_ROOT}/node/bin/node"
  FF_DIR="${OUTPUT_ROOT}/ff"

  test -d "${PYTHON_FRAMEWORK_DIR}" || { echo "Missing ${PYTHON_FRAMEWORK_DIR}" >&2; exit 1; }
  test -x "${VENV_DIR}/bin/python3.11" || { echo "Missing venv Python" >&2; exit 1; }
  test -x "${NODE_BIN}" || { echo "Missing Node: ${NODE_BIN}" >&2; exit 1; }
  test -x "${FF_DIR}/ffmpeg" || { echo "Missing ffmpeg" >&2; exit 1; }

  export DJ_RUNTIME_TARGET_ARCH="${ARCH}"
  export DJ_RUNTIME_SOURCE_PYTHON_FRAMEWORK="${PYTHON_FRAMEWORK_DIR}"
  export DJ_RUNTIME_SOURCE_VENV="${VENV_DIR}"
  export DJ_RUNTIME_SOURCE_NODE_BIN="${NODE_BIN}"
  export DJ_RUNTIME_SOURCE_FFMPEG="${FF_DIR}/ffmpeg"
  export DJ_RUNTIME_SOURCE_FFPROBE="${FF_DIR}/ffprobe"

  "${REPO_ROOT}/scripts/prepare_runtime_staging.sh"

  pushd "${APP_ROOT}" >/dev/null
  if [ "${SKIP_FLUTTER_PUB_GET:-0}" != "1" ]; then
    flutter pub get
  fi
  # Flutter passes FLUTTER_XCODE_* variables as xcodebuild settings.
  # The runtime bundle phase sees DJ_RUNTIME_TARGET_ARCH and packages only
  # the matching thin runtime.
  if [ "${ARCH}" = "x86_64" ]; then
    EXCLUDED_ARCH="arm64"
  else
    EXCLUDED_ARCH="x86_64"
  fi
  FLUTTER_XCODE_ARCHS="${ARCH}" \
    FLUTTER_XCODE_ONLY_ACTIVE_ARCH=NO \
    FLUTTER_XCODE_EXCLUDED_ARCHS="${EXCLUDED_ARCH}" \
    FLUTTER_XCODE_MACOSX_DEPLOYMENT_TARGET="${DJ_RUNTIME_TARGET_MACOS_MIN_VERSION}" \
    DJ_RUNTIME_TARGET_ARCH="${ARCH}" \
    flutter build macos --release
  popd >/dev/null

  APP_PATH="${APP_ROOT}/build/macos/Build/Products/Release/${APP_BASENAME}.app"
  test -d "${APP_PATH}" || { echo "App not found: ${APP_PATH}" >&2; exit 1; }

  LABEL="Intel"
  [ "${ARCH}" = "arm64" ] && LABEL="AppleSilicon"
  APP_OUT="${DIST_DIR}/${APP_BASENAME}_v${VERSION}_${LABEL}.app"
  DMG_OUT="${DIST_DIR}/${APP_BASENAME}_v${VERSION}_${LABEL}.dmg"

  rm -rf "${APP_OUT}"
  ditto "${APP_PATH}" "${APP_OUT}"

  if [ "${SKIP_DMG:-0}" != "1" ]; then
    rm -f "${DMG_OUT}"
    hdiutil create \
      -volname "${APP_BASENAME}" \
      -srcfolder "${APP_OUT}" \
      -ov -format UDZO \
      "${DMG_OUT}"
    echo "DMG: ${DMG_OUT}"
  fi
done

echo
echo "Done. Outputs in: ${DIST_DIR}"
