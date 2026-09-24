#!/bin/bash
# Created by Ray
# 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray
# 主要解决问题：监听 auto_compress，按内容哈希只压缩一次，并在原路径原子替换视觉无损结果。

set -o pipefail
umask 077

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
CONFIG_PATH="${1:-$(cd "${SCRIPT_DIR}/.." && pwd)/config.env}"

if [[ ! -f "${CONFIG_PATH}" ]]; then
    printf '配置文件不存在：%s\n' "${CONFIG_PATH}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_PATH}"

if [[ -f "${SCRIPT_DIR}/compressors/${COMPRESSOR_NAME}.sh" ]]; then
    COMPRESSOR_PATH="${SCRIPT_DIR}/compressors/${COMPRESSOR_NAME}.sh"
else
    COMPRESSOR_PATH="${SCRIPT_DIR}/../compressors/${COMPRESSOR_NAME}.sh"
fi

if [[ ! -f "${COMPRESSOR_PATH}" ]]; then
    printf '压缩器模块不存在：%s\n' "${COMPRESSOR_PATH}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${COMPRESSOR_PATH}"

LOG_FILE="${LOG_DIR}/worker.log"
LOCK_DIR="${STATE_DIR}/.lock"
CACHE_DIR="${STATE_DIR}/cache/${COMPRESSOR_ID}"
SEEN_DIR="${STATE_DIR}/seen/${COMPRESSOR_ID}"
FAILED_DIR="${STATE_DIR}/failed/${COMPRESSOR_ID}"
TEMP_DIR="${STATE_DIR}/tmp"

compressed_count=0
reused_count=0
failed_count=0
skipped_count=0

log_message() {
    local message="$1"
    printf '%s %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S%z')" "${message}" >> "${LOG_FILE}"
}

rotate_log_if_needed() {
    # 日志超过 5 MB 时只保留一份历史文件，避免长期运行占满用户目录。
    if [[ -f "${LOG_FILE}" ]]; then
        local current_size
        current_size="$(/usr/bin/stat -f '%z' "${LOG_FILE}" 2>/dev/null || printf '0')"
        if (( current_size > 5242880 )); then
            /bin/mv -f "${LOG_FILE}" "${LOG_FILE}.1"
        fi
    fi
}

acquire_lock() {
    if /bin/mkdir "${LOCK_DIR}" 2>/dev/null; then
        printf '%s\n' "$$" > "${LOCK_DIR}/pid"
        return 0
    fi

    local previous_pid=""
    if [[ -f "${LOCK_DIR}/pid" ]]; then
        previous_pid="$(/bin/cat "${LOCK_DIR}/pid" 2>/dev/null || true)"
    fi

    if [[ -n "${previous_pid}" ]] && /bin/kill -0 "${previous_pid}" 2>/dev/null; then
        return 1
    fi

    # 仅清理本工具自己创建的锁，避免异常退出后长期阻塞后续导出。
    /bin/rm -f "${LOCK_DIR}/pid"
    /bin/rmdir "${LOCK_DIR}" 2>/dev/null || true

    if /bin/mkdir "${LOCK_DIR}" 2>/dev/null; then
        printf '%s\n' "$$" > "${LOCK_DIR}/pid"
        return 0
    fi

    return 1
}

release_lock() {
    /bin/rm -f "${LOCK_DIR}/pid"
    /bin/rmdir "${LOCK_DIR}" 2>/dev/null || true
}

file_signature() {
    /usr/bin/stat -f '%z:%m:%i' "$1" 2>/dev/null
}

wait_for_stable_file() {
    local file_path="$1"
    local previous_signature=""
    local current_signature=""
    local attempt=0

    # Figma 写文件时可能出现短暂的不完整状态，连续两次签名一致后才允许读取。
    while (( attempt < 40 )); do
        [[ -f "${file_path}" ]] || return 1
        current_signature="$(file_signature "${file_path}")" || return 1

        if [[ -n "${previous_signature}" && "${current_signature}" == "${previous_signature}" ]]; then
            return 0
        fi

        previous_signature="${current_signature}"
        /bin/sleep 0.25
        ((attempt += 1))
    done

    return 1
}

hash_file() {
    local file_path="$1"
    /usr/bin/shasum -a 256 -- "${file_path}" 2>/dev/null | /usr/bin/awk '{print $1}'
}

seen_marker_path() {
    local content_hash="$1"
    printf '%s/%s/%s\n' "${SEEN_DIR}" "${content_hash:0:2}" "${content_hash}"
}

is_seen_hash() {
    local content_hash="$1"
    [[ -f "$(seen_marker_path "${content_hash}")" ]]
}

mark_seen_hash() {
    local content_hash="$1"
    local marker_path=""
    marker_path="$(seen_marker_path "${content_hash}")"

    /bin/mkdir -p "$(/usr/bin/dirname "${marker_path}")"
    : > "${marker_path}"
}

failed_marker_path() {
    local content_hash="$1"
    printf '%s/%s/%s\n' "${FAILED_DIR}" "${content_hash:0:2}" "${content_hash}"
}

replace_with_temp_file() {
    local temp_path="$1"
    local target_path="$2"
    local original_mode="$3"

    /bin/chmod "${original_mode}" "${temp_path}" 2>/dev/null || true
    /bin/mv -f "${temp_path}" "${target_path}"
}

publish_cached_result() {
    local cache_path="$1"
    local target_path="$2"
    local original_mode="$3"
    local target_parent=""
    local temp_target=""

    target_parent="$(/usr/bin/dirname "${target_path}")"
    temp_target="$(/usr/bin/mktemp "${target_parent}/.figma-compress.XXXXXX")" || return 1

    if ! /bin/cp -p "${cache_path}" "${temp_target}"; then
        /bin/rm -f "${temp_target}"
        return 1
    fi

    replace_with_temp_file "${temp_target}" "${target_path}" "${original_mode}"
}

process_png() {
    local file_path="$1"
    local before_hash=""
    local after_hash=""
    local cache_path=""
    local failed_marker=""
    local temp_result=""
    local original_mode=""
    local before_size=0
    local after_size=0
    local saved_bytes=0

    if ! wait_for_stable_file "${file_path}"; then
        log_message "跳过：文件未稳定或已消失 ${file_path}"
        ((failed_count += 1))
        return 0
    fi

    before_hash="$(hash_file "${file_path}")"
    if [[ -z "${before_hash}" ]]; then
        log_message "失败：无法计算 SHA-256 ${file_path}"
        ((failed_count += 1))
        return 0
    fi

    failed_marker="$(failed_marker_path "${before_hash}")"
    if [[ -f "${failed_marker}" ]]; then
        ((skipped_count += 1))
        return 0
    fi

    # 已记录压缩结果哈希时直接跳过，因此压缩文件改名不会重复处理。
    if is_seen_hash "${before_hash}"; then
        ((skipped_count += 1))
        return 0
    fi

    cache_path="${CACHE_DIR}/${before_hash}.png"
    original_mode="$(/usr/bin/stat -f '%Lp' "${file_path}" 2>/dev/null || printf '600')"

    # 同内容文件换名后优先复用缓存，不再次调用压缩器，但会用压缩结果替换未压缩副本。
    if [[ -f "${cache_path}" ]]; then
        if publish_cached_result "${cache_path}" "${file_path}" "${original_mode}"; then
            after_hash="$(hash_file "${file_path}")"
            mark_seen_hash "${after_hash}"
            ((reused_count += 1))
            log_message "复用并替换：${file_path}，命中内容哈希 ${before_hash:0:12}"
        else
            ((failed_count += 1))
            log_message "失败：无法用缓存替换 ${file_path}"
        fi
        return 0
    fi

    temp_result="$(/usr/bin/mktemp "${TEMP_DIR}/.compressed.XXXXXX")" || {
        ((failed_count += 1))
        log_message "失败：无法创建临时文件 ${file_path}"
        return 0
    }
    /bin/rm -f "${temp_result}"

    before_size="$(/usr/bin/stat -f '%z' "${file_path}" 2>/dev/null || printf '0')"

    if ! compress_image "${file_path}" "${temp_result}" "${LOG_FILE}" || [[ ! -f "${temp_result}" ]]; then
        /bin/rm -f "${temp_result}"
        /bin/mkdir -p "$(/usr/bin/dirname "${failed_marker}")"
        : > "${failed_marker}"
        ((failed_count += 1))
        log_message "失败：${file_path}，压缩器 ${COMPRESSOR_NAME} 未生成结果"
        return 0
    fi

    after_hash="$(hash_file "${temp_result}")"
    after_size="$(/usr/bin/stat -f '%z' "${temp_result}" 2>/dev/null || printf '0')"
    /bin/mkdir -p "${CACHE_DIR}"
    /bin/cp -p "${temp_result}" "${cache_path}"

    if [[ "${after_hash}" == "${before_hash}" ]]; then
        # 未获得更小结果时记录为已处理，但保留磁盘中的原文件。
        /bin/rm -f "${temp_result}"
        mark_seen_hash "${before_hash}"
        ((compressed_count += 1))
        log_message "完成：${file_path}，未获得更小结果，保留原文件"
        return 0
    fi

    replace_with_temp_file "${temp_result}" "${file_path}" "${original_mode}"
    mark_seen_hash "${after_hash}"

    if (( before_size > after_size )); then
        saved_bytes=$((before_size - after_size))
    fi

    ((compressed_count += 1))
    log_message "完成并替换：${file_path}，${before_size} -> ${after_size} bytes，节省 ${saved_bytes} bytes，结果哈希 ${after_hash:0:12}"
}

validate_paths() {
    case "${TARGET_DIR}" in /*) ;; *) printf 'TARGET_DIR 必须是绝对路径\n' >&2; exit 1 ;; esac

    if [[ "${TARGET_DIR}" == "/" ]]; then
        printf '出于最小权限原则，不允许使用根目录。\n' >&2
        exit 1
    fi
}

main() {
    validate_paths
    /bin/mkdir -p "${STATE_DIR}" "${CACHE_DIR}" "${SEEN_DIR}" "${FAILED_DIR}" "${TEMP_DIR}" "${TARGET_DIR}" "${LOG_DIR}"
    /bin/chmod 700 "${STATE_DIR}" "${TEMP_DIR}" "${LOG_DIR}"
    rotate_log_if_needed

    if ! compressor_validate; then
        log_message "失败：压缩器 ${COMPRESSOR_NAME} 校验未通过"
        exit 1
    fi

    if ! /usr/bin/find "${TARGET_DIR}" -maxdepth 1 -type d -print >/dev/null 2>> "${LOG_FILE}"; then
        log_message "失败：无权访问目标目录 ${TARGET_DIR}"
        exit 1
    fi

    if ! acquire_lock; then
        exit 0
    fi

    trap release_lock EXIT

    while IFS= read -r -d '' file_path; do
        process_png "${file_path}"
    done < <(/usr/bin/find "${TARGET_DIR}" -type f -iname '*.png' -print0 2>> "${LOG_FILE}")

    if (( compressed_count > 0 || reused_count > 0 || failed_count > 0 )); then
        log_message "汇总：压缩 ${compressed_count}，复用 ${reused_count}，失败 ${failed_count}，跳过 ${skipped_count}"
    fi
}

main
