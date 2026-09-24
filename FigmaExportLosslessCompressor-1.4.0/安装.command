#!/bin/bash
# Created by Ray
# 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray
# 主要解决问题：提供 Finder 双击安装入口，并从发布包复制程序后执行交互式安装器。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT="${SCRIPT_DIR}"
PAYLOAD_DIR="${SCRIPT_DIR}/payload/_figmaExport"
INSTALLED_ROOT="${HOME}/script/_figmaExport"
exit_code=0

printf 'Figma 导出视觉无损压缩器安装程序\n\n'

if [[ -d "${PAYLOAD_DIR}" ]]; then
    /bin/mkdir -p "${INSTALLED_ROOT}"

    # 发布包只覆盖程序文件，不清空用户导出目录、状态和本地配置。
    if ! /usr/bin/ditto "${PAYLOAD_DIR}/" "${INSTALLED_ROOT}/"; then
        printf '复制程序文件失败。\n' >&2
        exit_code=1
    else
        INSTALL_ROOT="${INSTALLED_ROOT}"
    fi
fi

if (( exit_code == 0 )); then
    if [[ ! -x "${INSTALL_ROOT}/install.sh" ]]; then
        printf '未找到安装器：%s\n' "${INSTALL_ROOT}/install.sh" >&2
        exit_code=1
    elif ! "${INSTALL_ROOT}/install.sh"; then
        exit_code=1
    fi
fi

printf '\n'
if (( exit_code == 0 )); then
    printf '安装流程已结束。\n'
else
    printf '安装未完成，请查看上方错误信息。\n'
fi

read -n 1 -s -r -p "按任意键关闭..."
printf '\n'
exit "${exit_code}"
