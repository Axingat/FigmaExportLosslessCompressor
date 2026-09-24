#!/bin/bash
# Created by Ray
# 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray
# 主要解决问题：提供 Finder 双击卸载入口，默认保留导出资源、缓存和日志。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="${SCRIPT_DIR}"
exit_code=0

if [[ -d "${SCRIPT_DIR}/payload/_figmaExport" ]]; then
    TARGET_ROOT="${HOME}/script/_figmaExport"
fi

if [[ ! -x "${TARGET_ROOT}/uninstall.sh" ]]; then
    printf '未找到卸载器。\n' >&2
    exit_code=1
elif ! "${TARGET_ROOT}/uninstall.sh"; then
    exit_code=1
fi

printf '\n'
read -n 1 -s -r -p "按任意键关闭..."
printf '\n'
exit "${exit_code}"
