#!/bin/bash
# Created by Ray
# 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray
# 主要解决问题：提供 Finder 双击状态入口，显示当前 LaunchAgent、导出目录、缓存和处理日志。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="${SCRIPT_DIR}"
exit_code=0

if [[ -d "${SCRIPT_DIR}/payload/_figmaExport" ]]; then
    TARGET_ROOT="${HOME}/script/_figmaExport"
fi

if [[ ! -x "${TARGET_ROOT}/status.sh" ]]; then
    printf '尚未安装。请先运行“安装.command”。\n' >&2
    exit_code=1
elif ! "${TARGET_ROOT}/status.sh"; then
    exit_code=1
fi

printf '\n'
read -n 1 -s -r -p "按任意键关闭..."
printf '\n'
exit "${exit_code}"
