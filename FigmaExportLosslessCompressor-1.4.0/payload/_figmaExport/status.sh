#!/bin/bash
# Created by Ray
# 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray
# 主要解决问题：查看 auto_compress 原地压缩任务、去重缓存、PNG 数量和最近处理日志。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/config.env"
LABEL="com.ray.figma-export-lossless"
DOMAIN="gui/$(/usr/bin/id -u)"

# shellcheck source=/dev/null
source "${CONFIG_PATH}"

cache_count=0
seen_count=0
failed_count=0
png_count=0

if [[ -d "${STATE_DIR}/cache" ]]; then
    cache_count="$(/usr/bin/find "${STATE_DIR}/cache" -type f 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
fi

if [[ -d "${STATE_DIR}/seen" ]]; then
    seen_count="$(/usr/bin/find "${STATE_DIR}/seen" -type f 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
fi

if [[ -d "${STATE_DIR}/failed" ]]; then
    failed_count="$(/usr/bin/find "${STATE_DIR}/failed" -type f 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
fi

if [[ -d "${TARGET_DIR}" ]]; then
    png_count="$(/usr/bin/find "${TARGET_DIR}" -type f -iname '*.png' 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
fi

printf 'LaunchAgent：%s\n' "${LABEL}"
if /bin/launchctl print "${DOMAIN}/${LABEL}" >/dev/null 2>&1; then
    printf '运行状态：已加载\n'
else
    printf '运行状态：未加载\n'
fi

printf '脚本目录：%s\n' "${SCRIPT_DIR}"
printf '监听并原地压缩：%s\n' "${TARGET_DIR}"
printf '本地配置：%s\n' "${LOCAL_CONFIG_FILE}"
printf '压缩器：%s (%s)\n' "${COMPRESSOR_NAME}" "${COMPRESSOR_ID}"
printf '内容缓存：%s\n' "${cache_count}"
printf '已处理哈希：%s\n' "${seen_count}"
printf '失败记录：%s\n' "${failed_count}"
printf '目录内 PNG：%s\n' "${png_count}"

if [[ -f "${LOG_DIR}/worker.log" ]]; then
    printf '\n最近日志：\n'
    /usr/bin/tail -n 20 "${LOG_DIR}/worker.log"
else
    printf '\n最近日志：暂无\n'
fi
