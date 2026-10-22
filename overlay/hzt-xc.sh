#!/bin/sh
# 启动器：/usr/bin/hzt-xc
# 只做「让上游程序在当前系统上跑起来」所需的环境修正，不改程序逻辑。
set -u

APP_ROOT=${HZT_APP_ROOT:-/opt/apps/com.hzt.xc}
VERSION=$(cat "$APP_ROOT/files/version" 2>/dev/null) || {
    echo "找不到 $APP_ROOT/files/version，安装可能不完整" >&2
    exit 1
}
APP_DIR="$APP_ROOT/files/$VERSION"

unset SESSION_MANAGER

# 上游按 X11 构建；Wayland 会话下走 XWayland
export QT_QPA_PLATFORM=${QT_QPA_PLATFORM:-xcb}
export QT_PLUGIN_PATH="$APP_DIR"

# Debian 侧 soname（由 build.sh 放进 extra/）
export LD_LIBRARY_PATH="$APP_DIR/extra${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# 绕过 NSS 证书库初始化，规避与系统 libsqlite3 的符号冲突（详见 docs）
if [ -f "$APP_DIR/shims/libhzt_nss_nodb.so" ]; then
    export LD_PRELOAD="$APP_DIR/shims/libhzt_nss_nodb.so${LD_PRELOAD:+ $LD_PRELOAD}"
fi

# 浅色配置档案：
# 聊天输入框是 Qt 原生控件，文字色取自 Qt 调色板。系统为深色主题时取到白色文字，
# 而输入框背景由程序自绘为浅色 → 白字白底。这里提供一个只覆盖调色板来源的配置目录。
XDG_LIGHT="${XDG_STATE_HOME:-$HOME/.local/state}/hzt-xc/xdg-light"
GTK_DIR="$XDG_LIGHT/gtk-3.0"
mkdir -p "$GTK_DIR"
[ -f "$GTK_DIR/settings.ini" ] || \
    cp -f "$APP_DIR/xdg-light/gtk-3.0/settings.ini" "$GTK_DIR/settings.ini" 2>/dev/null || :

for f in "$HOME/.config"/*; do
    b=$(basename "$f")
    case "$b" in
        # 关键：kdeglobals 声明 ColorScheme=BreezeDark，必须排除，否则调色板又变深色
        gtk-3.0|kdeglobals|kdeglobals.*) continue ;;
    esac
    [ -e "$XDG_LIGHT/$b" ] || [ -L "$XDG_LIGHT/$b" ] || \
        ln -sfn "$f" "$XDG_LIGHT/$b" 2>/dev/null
done
export XDG_CONFIG_HOME="$XDG_LIGHT"

cd "$APP_DIR" || exit 1
exec ./com.hzt.xc "$@"
