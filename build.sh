#!/usr/bin/env bash
# 把官方 .deb 重打成本地 RPM。
# 仓库本身不含任何厂商二进制：所有内容在构建时从你提供的 .deb 里解出。
set -euo pipefail

DEB=${1:-}
if [[ -z $DEB || ! -f $DEB ]]; then
    cat >&2 <<'EOF'
用法: ./build.sh /path/to/signed_com.hzt.xc_x.y.z_amd64.deb

说明: 安装包需自行从官方渠道获取，本仓库不提供、不分发。
EOF
    exit 1
fi

ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD=$ROOT/build
STAGE=$BUILD/stage
APPDIR=/opt/apps/com.hzt.xc

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少工具: $1" >&2; exit 1; }; }
for t in ar tar rpmbuild gcc python3 curl; do need "$t"; done

rm -rf "$BUILD"
mkdir -p "$BUILD/deb" "$STAGE"

# ---------------------------------------------------------------- 1. 解包
echo "==> [1/6] 解包 $(basename "$DEB")"
( cd "$BUILD/deb" && ar x "$DEB" && tar -xf data.tar.* )

if [[ ! -d "$BUILD/deb$APPDIR" ]]; then
    echo "错误: deb 结构与预期不符（找不到 $APPDIR）" >&2
    echo "      请确认下载的是 UOS / 麒麟 x86_64 版。" >&2
    exit 1
fi

# ---------------------------------------------------------------- 2. 复制
echo "==> [2/6] 复制到打包目录"
mkdir -p "$STAGE$(dirname "$APPDIR")"
cp -a "$BUILD/deb$APPDIR" "$STAGE$APPDIR"

VER=$(cat "$STAGE$APPDIR/files/version")
FILES=$STAGE$APPDIR/files/$VER
echo "    上游版本: $VER"

# RPM 的 Version 字段不能含 '-'，把 "3.14.0-Release.2" 拆成 3.14.0 / 2
RPMVER=${VER%%-*}
SUFFIX=${VER#*-}
RPMREL=$(printf '%s' "$SUFFIX" | tr -dc '0-9')
[[ -n $RPMREL ]] || RPMREL=1

# ------------------------------------------------- 3. 官方 postinst 的库清理
echo "==> [3/6] 按官方 postinst 规则移除自带旧库（glibc > 2.28）"
( cd "$FILES" && rm -f \
    libm.so.6 \
    libgdk-x11-2.0.so.0 \
    libgtk-x11-2.0.so.0 \
    libpangoft2-1.0.so.0 \
    libGLdispatch.so.* \
    libGLX.so.* 2>/dev/null || true )

# ------------------------------------------------------- 4. 清除可执行栈标记
echo "==> [4/6] 修正 application_gov.so 的 GNU_STACK"
for so in "$FILES"/application_gov.so; do
    [[ -f $so ]] && python3 "$ROOT/overlay/gnu-stack-rw.py" "$so"
done

# ------------------------------------------- 5. 依赖库 + shim + 浅色配置模板
echo "==> [5/6] 补齐 Debian 侧依赖库并编译 NSS shim"
mkdir -p "$FILES/extra" "$FILES/shims" "$FILES/xdg-light/gtk-3.0"
"$ROOT/scripts/fetch-extra-libs.sh" "$FILES/extra"
gcc -shared -fPIC -O2 -o "$FILES/shims/libhzt_nss_nodb.so" \
    "$ROOT/overlay/nss_nodb_shim.c" -ldl
cp -f "$ROOT/overlay/gtk-3.0-settings.ini" "$FILES/xdg-light/gtk-3.0/settings.ini"

# ---------------------------------------------------------------- 6. 打包
echo "==> [6/6] rpmbuild"
mkdir -p "$BUILD"/{SPECS,SOURCES,BUILD,RPMS,SRPMS}
rpmbuild -bb \
    --define "_topdir $BUILD" \
    --define "_sourcedir $ROOT/overlay" \
    --define "stage $STAGE" \
    --define "rpmver $RPMVER" \
    --define "rpmrel $RPMREL" \
    "$ROOT/rpm/hzt-xc.spec"

echo
echo "构建完成："
find "$BUILD/RPMS" -name '*.rpm' -printf '  %p\n'
echo
echo "安装： sudo dnf install $(find "$BUILD/RPMS" -name '*.rpm' | head -1)"
