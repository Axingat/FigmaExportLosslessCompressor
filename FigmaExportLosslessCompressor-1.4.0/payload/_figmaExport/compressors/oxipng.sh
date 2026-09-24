#!/bin/bash
# Created by Ray
# 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray
# 主要解决问题：以独立模块实现 oxipng 视觉无损压缩，使主监听流程无需修改即可替换压缩算法。

compressor_validate() {
    [[ -x "${OXIPNG_BIN}" ]] || return 1
    "${OXIPNG_BIN}" --version >/dev/null 2>&1
}

compressor_description() {
    printf 'oxipng max + alpha + strip safe\n'
}

compress_image() {
    local input_path="$1"
    local output_path="$2"
    local log_file="$3"
    local output_parent=""
    local candidate_path=""
    local input_size=0
    local candidate_size=0

    output_parent="$(/usr/bin/dirname "${output_path}")"
    /bin/mkdir -p "${output_parent}"
    candidate_path="$(/usr/bin/mktemp "${output_parent}/.oxipng-candidate.XXXXXX")" || return 1
    /bin/rm -f "${candidate_path}"

    if ! "${OXIPNG_BIN}" \
        --opt "${OXIPNG_OPT_LEVEL}" \
        --alpha \
        --strip safe \
        --preserve \
        --interlace keep \
        --threads "${OXIPNG_THREADS}" \
        --timeout "${OXIPNG_TIMEOUT_SECONDS}" \
        --force \
        --quiet \
        --out "${candidate_path}" \
        "${input_path}" >> "${log_file}" 2>&1; then
        /bin/rm -f "${candidate_path}"
        return 1
    fi

    if [[ ! -f "${candidate_path}" ]]; then
        /bin/rm -f "${candidate_path}"
        return 1
    fi

    input_size="$(/usr/bin/stat -f '%z' "${input_path}" 2>/dev/null || printf '0')"
    candidate_size="$(/usr/bin/stat -f '%z' "${candidate_path}" 2>/dev/null || printf '0')"

    if (( candidate_size > 0 && input_size > 0 && candidate_size < input_size )); then
        /bin/mv -f "${candidate_path}" "${output_path}"
    else
        # 若优化结果没有变小，输出原文件，既保留资源又避免让文件变大。
        /bin/rm -f "${candidate_path}"
        /bin/cp -p "${input_path}" "${output_path}"
    fi
}
