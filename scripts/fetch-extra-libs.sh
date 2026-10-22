#!/usr/bin/env bash
# 从 Debian 镜像取 4 个在 Fedora 上缺失的 soname。
#
# 这些库属于 Debian 自由软件，构建时下载，不在本仓库中分发。
# 版本号不写死：直接读发行版的 Packages 索引，避免 binNMU 后 404。
set -euo pipefail

DEST=${1:-}
if [[ -z $DEST ]]; then
    echo "用法: $0 <目标目录>" >&2
    exit 1
fi
mkdir -p "$DEST"

# 可覆盖：国内访问 deb.debian.org 较慢，默认用清华镜像
MIRROR=${DEBIAN_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/debian}
DIST=${DEBIAN_DIST:-bullseye}          # bullseye 才有 libldap-2.4 / libsasl2.so.2
ARCH=${DEBIAN_ARCH:-amd64}

LIBS=(
    librtmp.so.1
    liblber-2.4.so.2
    libldap_r-2.4.so.2
    libsasl2.so.2
)
PKGS=(librtmp1 libldap-2.4-2 libsasl2-2)

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "    读取索引 $MIRROR (dists/$DIST/main/binary-$ARCH)"
curl -fsSL --retry 2 -m 300 \
    "$MIRROR/dists/$DIST/main/binary-$ARCH/Packages.gz" \
    | gzip -dc > "$TMP/Packages"

filename_of() {
    awk -v pkg="$1" '
        BEGIN { RS = ""; FS = "\n" }
        $1 == "Package: " pkg {
            for (i = 1; i <= NF; i++)
                if ($i ~ /^Filename: /) { print substr($i, 11); exit }
        }' "$TMP/Packages"
}

for pkg in "${PKGS[@]}"; do
    fn=$(filename_of "$pkg")
    if [[ -z $fn ]]; then
        echo "索引中找不到 $pkg（$DIST/$ARCH）" >&2
        exit 1
    fi
    echo "    下载 $pkg <- ${fn##*/}"
    curl -fsSL --retry 2 -m 300 -o "$TMP/$pkg.deb" "$MIRROR/$fn"
    mkdir -p "$TMP/$pkg"
    ( cd "$TMP/$pkg" && ar x "$TMP/$pkg.deb" && tar -xf data.tar.* )
done

missing=0
for lib in "${LIBS[@]}"; do
    # Debian 里 soname 常是软链（如 liblber-2.4.so.2 -> .2.11.5），
    # 必须连同链接一起找，并用 cp -L 取实体内容。
    src=$(find "$TMP" \( -type f -o -type l \) -name "$lib" | head -1)
    if [[ -n $src ]]; then
        cp -Lf "$src" "$DEST/$lib"
        echo "    -> extra/$lib"
    else
        echo "    警告: 未找到 $lib" >&2
        missing=1
    fi
done

if [[ $missing -ne 0 ]]; then
    echo "有库缺失，程序可能无法启动（见 docs/troubleshooting.md）" >&2
    exit 1
fi
