#!/bin/bash
# Created by Ray
# 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray
# 主要解决问题：卸载 auto_compress 原地压缩 LaunchAgent，默认保留资源与缓存，purge 时清理工具数据。

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/config.env"
LABEL="com.ray.figma-export-lossless"
AGENT_PATH="${HOME}/Library/LaunchAgents/${LABEL}.plist"
DOMAIN="gui/$(/usr/bin/id -u)"

if [[ -f "${CONFIG_PATH}" ]]; then
    # shellcheck source=/dev/null
    source "${CONFIG_PATH}"
fi

/bin/launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
/bin/rm -f "${AGENT_PATH}"

if [[ "${1:-}" == "--purge" ]]; then
    target_removed=0

    for path_value in "${STATE_DIR:-}" "${LOG_DIR:-}"; do
        case "${path_value}" in
            "${BASE_DIR}/"*)
                if [[ -e "${path_value}" ]]; then
                    /bin/rm -rf "${path_value}"
                fi
                ;;
        esac
    done

    case "${TARGET_DIR:-}" in
        "${BASE_DIR}/"*)
            if [[ -n "${TARGET_DIR:-}" && -e "${TARGET_DIR}" ]]; then
                /bin/rm -rf "${TARGET_DIR}"
                target_removed=1
            fi
            ;;
    esac

    if [[ -f "${LOCAL_CONFIG_FILE:-}" ]]; then
        /bin/rm -f "${LOCAL_CONFIG_FILE}"
    fi

    if (( target_removed == 1 )); then
        printf '监听器已卸载，状态、日志、本地配置和工具内压缩目录已清除。\n'
    else
        printf '监听器已卸载，状态、日志和本地配置已清除；自定义导出目录已保留。\n'
    fi
else
    printf '监听器已卸载，压缩资源、状态、日志和本地配置已保留。\n'
fi
