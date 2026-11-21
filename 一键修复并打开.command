#!/bin/zsh
set -e

APP_NAME="教坊司DJ便捷工具.app"
DEFAULT_APP_PATH="/Applications/${APP_NAME}"

choose_app() {
  osascript <<'APPLESCRIPT'
set chosenApp to choose file with prompt "请选择 教坊司DJ便捷工具.app" of type {"app"}
POSIX path of chosenApp
APPLESCRIPT
}

APP_PATH="$DEFAULT_APP_PATH"
if [ ! -d "$APP_PATH" ]; then
  APP_PATH="$(choose_app)"
fi

if [ ! -d "$APP_PATH" ]; then
  osascript -e 'display dialog "未找到 教坊司DJ便捷工具.app，请先将应用拖入 Applications 文件夹。" buttons {"好"} default button "好" with icon caution'
  exit 1
fi

TEMP_LOG="$(mktemp)"
if /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" >"$TEMP_LOG" 2>&1; then
  /usr/bin/open "$APP_PATH"
  osascript -e 'display dialog "已完成修复并尝试打开 教坊司DJ便捷工具。" buttons {"好"} default button "好"'
  rm -f "$TEMP_LOG"
  exit 0
fi

if grep -q "No such file" "$TEMP_LOG"; then
  /usr/bin/find "$APP_PATH" -type l ! -exec test -e {} \; -delete
  if /usr/bin/xattr -dr com.apple.quarantine "$APP_PATH" >"$TEMP_LOG" 2>&1; then
    /usr/bin/open "$APP_PATH"
    osascript -e 'display dialog "已完成修复并尝试打开 教坊司DJ便捷工具。" buttons {"好"} default button "好"'
    rm -f "$TEMP_LOG"
    exit 0
  fi
fi

ERROR_MSG="$(cat "$TEMP_LOG")"
rm -f "$TEMP_LOG"
osascript <<APPLESCRIPT
set errText to quoted form of "$ERROR_MSG"
display dialog "修复或打开失败：" & (do shell script "printf %s " & errText) buttons {"好"} default button "好" with icon caution
APPLESCRIPT
exit 1
