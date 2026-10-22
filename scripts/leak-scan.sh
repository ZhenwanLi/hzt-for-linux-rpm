#!/usr/bin/env bash
# 提交前自检：扫描仓库里是否残留个人 / 单位 / 内网信息，或误提交了二进制。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fail=0

scan() {
    local name=$1 pattern=$2 whitelist=${3:-}
    local hits
    hits=$(grep -rInE "$pattern" \
            --exclude-dir=.git --exclude-dir=build \
            --exclude='*.md.bak' . 2>/dev/null || true)
    if [[ -n $whitelist ]]; then
        hits=$(printf '%s\n' "$hits" | grep -vE "$whitelist" || true)
    fi
    if [[ -n $hits ]]; then
        echo "✗ $name"
        printf '%s\n' "$hits" | head -5 | sed 's/^/    /'
        fail=1
    else
        echo "✓ $name"
    fi
}

scan "手机号"        '1[3-9][0-9]{9}'
scan "身份证号"      '[0-9]{17}[0-9Xx]'
scan "邮箱"          '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
scan "家目录绝对路径" '/home/[a-z][a-z0-9_-]+' '/home/user'
scan "账号 ID"       '[0-9]{5,}@'
scan "内网域名"       'hainan|zwdingding' 'taurushainanxc'

echo
echo "--- 二进制 / 图片 ---"
bad=$(find . \( -path ./.git -o -path ./build \) -prune -o -type f \
        \( -iname '*.deb' -o -iname '*.rpm' -o -iname '*.so' -o -iname '*.so.*' \
           -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print 2>/dev/null)
if [[ -n $bad ]]; then
    echo "✗ 发现不应入库的文件"
    printf '%s\n' "$bad" | sed 's/^/    /'
    fail=1
else
    echo "✓ 无二进制 / 图片"
fi

echo
if [[ $fail -eq 0 ]]; then
    echo "扫描通过，可以提交。"
else
    echo "扫描未通过，请先处理上面标记的内容。"
fi
exit $fail
