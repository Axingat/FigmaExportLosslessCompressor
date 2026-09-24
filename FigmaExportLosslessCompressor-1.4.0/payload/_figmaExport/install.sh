#!/bin/bash
# Created by Ray
# 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray
# 主要解决问题：交互输入 Figma 导出目录，自动安装 oxipng，并注册监听该目录的原地压缩 LaunchAgent。

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/config.env"
WORKER_PATH="${SCRIPT_DIR}/bin/compress-figma-exports.sh"
COMPRESSOR_DIR="${SCRIPT_DIR}/compressors"
PLIST_TEMPLATE="${SCRIPT_DIR}/launchd/com.ray.figma-export-lossless.plist.template"
LABEL="com.ray.figma-export-lossless"
AGENT_DIR="${HOME}/Library/LaunchAgents"
AGENT_PATH="${AGENT_DIR}/${LABEL}.plist"
DOMAIN="gui/$(/usr/bin/id -u)"
LEGACY_APP_DIR="${HOME}/Library/Application Support/FigmaExportLosslessCompressor"
LEGACY_RUNTIME_DIR="${LEGACY_APP_DIR}/runtime"
LEGACY_STATE_DIR="${LEGACY_APP_DIR}/state"
LEGACY_DATA_DIR="${LEGACY_APP_DIR}/data"
LEGACY_LOG_DIR="${HOME}/Library/Logs/FigmaExportLosslessCompressor"

SELECTED_TARGET_DIR=""
SELECTED_OXIPNG_BIN=""

if [[ ! -f "${CONFIG_PATH}" || ! -f "${WORKER_PATH}" || ! -f "${PLIST_TEMPLATE}" || ! -d "${COMPRESSOR_DIR}" ]]; then
    printf '安装文件不完整，请检查脚本目录。\n' >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_PATH}"

die() {
    printf '%s\n' "$1" >&2
    exit 1
}

validate_absolute_path() {
    local path_value="$1"
    local path_name="$2"

    case "${path_value}" in
        /*) ;;
        *) die "${path_name} 必须是绝对路径：${path_value}" ;;
    esac

    if [[ "${path_value}" == "/" ]]; then
        die "${path_name} 不允许使用根目录。"
    fi
}

validate_managed_path() {
    local path_value="$1"
    local path_name="$2"

    case "${path_value}" in
        "${BASE_DIR}/"*) ;;
        *) die "${path_name} 必须位于 ${BASE_DIR} 下：${path_value}" ;;
    esac
}

is_tcc_protected_path() {
    local canonical_path="$1"

    case "${canonical_path}" in
        "${HOME}/Desktop"|"${HOME}/Desktop/"*|"${HOME}/Documents"|"${HOME}/Documents/"*|"${HOME}/Downloads"|"${HOME}/Downloads/"*)
            return 0
            ;;
    esac

    return 1
}

resolve_export_directory() {
    local default_path="${TARGET_DIR:-${BASE_DIR}/auto_compress}"
    local input_path="${FIGMA_EXPORT_DIR:-}"
    local use_environment_input=0
    local canonical_path=""
    local probe_path=""

    if [[ -n "${input_path}" ]]; then
        use_environment_input=1
    fi

    while true; do
        if [[ -z "${input_path}" ]]; then
            printf '\n请输入 Figma 导出文件夹的绝对路径。\n'
            printf '压缩会在该目录内直接替换原 PNG。\n'
            printf '默认目录：%s\n' "${default_path}"
            if ! read -r -p "导出目录： " input_path; then
                die "未能读取导出目录。"
            fi
        fi

        if [[ -z "${input_path}" ]]; then
            input_path="${default_path}"
        fi

        case "${input_path}" in
            "~") input_path="${HOME}" ;;
            "~/"*) input_path="${HOME}/${input_path#~/}" ;;
        esac

        while [[ "${input_path}" != "/" && "${input_path}" == */ ]]; do
            input_path="${input_path%/}"
        done

        if [[ "${input_path}" == *$'\n'* || "${input_path}" != /* ]]; then
            if (( use_environment_input == 1 )); then
                die "FIGMA_EXPORT_DIR 必须是单行绝对路径。"
            fi
            printf '路径无效，请输入绝对路径。\n'
            input_path=""
            continue
        fi

        if [[ "${input_path}" == "/" || "${input_path}" == "${HOME}" ]]; then
            if (( use_environment_input == 1 )); then
                die "导出目录不能是根目录或用户主目录。"
            fi
            printf '导出目录不能是根目录或用户主目录，请重新输入。\n'
            input_path=""
            continue
        fi

        if ! /bin/mkdir -p "${input_path}" 2>/dev/null; then
            if (( use_environment_input == 1 )); then
                die "无法创建导出目录：${input_path}"
            fi
            printf '无法创建该目录，请重新输入。\n'
            input_path=""
            continue
        fi

        if ! canonical_path="$(cd "${input_path}" 2>/dev/null && /bin/pwd -P)"; then
            if (( use_environment_input == 1 )); then
                die "无法解析导出目录：${input_path}"
            fi
            printf '无法解析该目录，请重新输入。\n'
            input_path=""
            continue
        fi

        if is_tcc_protected_path "${canonical_path}"; then
            if (( use_environment_input == 1 )); then
                die "macOS TCC 会阻止 LaunchAgent 访问 Desktop、Documents 和 Downloads。"
            fi
            printf '该目录位于 macOS 隐私保护区，后台任务会被拒绝访问，请重新输入。\n'
            input_path=""
            continue
        fi

        probe_path="${canonical_path}/.figma-export-write-test.$$"
        if ! /usr/bin/touch "${probe_path}" 2>/dev/null; then
            if (( use_environment_input == 1 )); then
                die "导出目录不可写：${canonical_path}"
            fi
            printf '该目录不可写，请重新输入。\n'
            input_path=""
            continue
        fi
        /bin/rm -f "${probe_path}"

        SELECTED_TARGET_DIR="${canonical_path}"
        return 0
    done
}

find_brew_path() {
    local candidate=""

    if candidate="$(command -v brew 2>/dev/null)"; then
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    fi

    for candidate in "/opt/homebrew/bin/brew" "/usr/local/bin/brew"; do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    return 1
}

find_oxipng_path() {
    local brew_path=""
    local brew_prefix=""
    local candidate=""

    if [[ -n "${OXIPNG_BIN}" && -x "${OXIPNG_BIN}" ]]; then
        printf '%s\n' "${OXIPNG_BIN}"
        return 0
    fi

    if candidate="$(command -v oxipng 2>/dev/null)"; then
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    fi

    for candidate in "/opt/homebrew/bin/oxipng" "/usr/local/bin/oxipng"; do
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done

    if brew_path="$(find_brew_path)" && brew_prefix="$("${brew_path}" --prefix 2>/dev/null)"; then
        candidate="${brew_prefix}/bin/oxipng"
        if [[ -x "${candidate}" ]]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    fi

    return 1
}

install_homebrew() {
    local installer_path=""
    local answer=""

    printf '\n未检测到 Homebrew。\n'
    printf '自动安装 oxipng 需要先安装 Homebrew。\n'
    if ! read -r -p "是否现在安装 Homebrew？[y/N] " answer; then
        return 1
    fi

    case "${answer}" in
        y|Y|yes|YES) ;;
        *) return 1 ;;
    esac

    installer_path="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/homebrew-installer.XXXXXX")" || return 1
    if ! /usr/bin/curl -fsSL "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" -o "${installer_path}"; then
        /bin/rm -f "${installer_path}"
        printf 'Homebrew 安装脚本下载失败。\n' >&2
        return 1
    fi

    if ! /bin/bash "${installer_path}"; then
        /bin/rm -f "${installer_path}"
        printf 'Homebrew 安装失败。\n' >&2
        return 1
    fi

    /bin/rm -f "${installer_path}"
    return 0
}

ensure_oxipng() {
    local brew_path=""
    local brew_prefix=""
    local candidate=""

    if candidate="$(find_oxipng_path)"; then
        SELECTED_OXIPNG_BIN="${candidate}"
        return 0
    fi

    printf '\n未检测到 oxipng，准备通过 Homebrew 自动安装。\n'
    if ! brew_path="$(find_brew_path)"; then
        if ! install_homebrew; then
            die "未安装 Homebrew，无法自动安装 oxipng。"
        fi
        brew_path="$(find_brew_path)" || die "Homebrew 安装完成后仍未找到 brew。"
    fi

    if ! "${brew_path}" install oxipng; then
        die "Homebrew 安装 oxipng 失败。"
    fi

    if candidate="$(find_oxipng_path)"; then
        SELECTED_OXIPNG_BIN="${candidate}"
        return 0
    fi

    brew_prefix="$("${brew_path}" --prefix 2>/dev/null || true)"
    candidate="${brew_prefix}/bin/oxipng"
    if [[ -x "${candidate}" ]]; then
        SELECTED_OXIPNG_BIN="${candidate}"
        return 0
    fi

    die "oxipng 安装完成，但未找到可执行文件。"
}

materialize_directory() {
    local directory_path="$1"
    local parent_dir=""
    local temp_dir=""

    parent_dir="$(/usr/bin/dirname "${directory_path}")"
    /bin/mkdir -p "${parent_dir}"

    if [[ -L "${directory_path}" ]]; then
        if [[ -d "${directory_path}" ]]; then
            temp_dir="$(/usr/bin/mktemp -d "${parent_dir}/.materialize.XXXXXX")"
            if ! /usr/bin/ditto "${directory_path}/" "${temp_dir}/"; then
                /bin/rm -rf "${temp_dir}"
                die "迁移链接目录失败：${directory_path}"
            fi
            /bin/rm -f "${directory_path}"
            /bin/mv "${temp_dir}" "${directory_path}"
        else
            /bin/rm -f "${directory_path}"
            /bin/mkdir -p "${directory_path}"
        fi
    elif [[ -e "${directory_path}" && ! -d "${directory_path}" ]]; then
        die "目标路径不是目录：${directory_path}"
    else
        /bin/mkdir -p "${directory_path}"
    fi

    if [[ -L "${directory_path}" || ! -d "${directory_path}" ]]; then
        die "目标目录仍不是真实目录：${directory_path}"
    fi
}

write_local_config() {
    local temp_config=""

    /bin/mkdir -p "${BASE_DIR}"
    temp_config="$(/usr/bin/mktemp "${BASE_DIR}/.config.local.XXXXXX")"

    {
        printf '# Created by Ray\n'
        printf '# 版本：1.4.0  /  build：5  /  2026-09-24  /  Ray\n'
        printf '# 主要解决问题：保存用户选择的 Figma 导出目录和自动检测到的 oxipng 路径。\n'
        printf 'TARGET_DIR=%q\n' "${SELECTED_TARGET_DIR}"
        printf 'OXIPNG_BIN=%q\n' "${SELECTED_OXIPNG_BIN}"
    } > "${temp_config}"

    /bin/chmod 600 "${temp_config}"
    /bin/mv -f "${temp_config}" "${LOCAL_CONFIG_FILE}"
}

migrate_legacy_state_and_logs() {
    if [[ ! -e "${STATE_DIR}" && -d "${LEGACY_STATE_DIR}" ]]; then
        /usr/bin/ditto "${LEGACY_STATE_DIR}/" "${STATE_DIR}/"
    fi

    if [[ ! -e "${LOG_DIR}" && -d "${LEGACY_LOG_DIR}" ]]; then
        /usr/bin/ditto "${LEGACY_LOG_DIR}/" "${LOG_DIR}/"
    fi
}

cleanup_legacy_storage() {
    local legacy_path=""

    for legacy_path in "${LEGACY_RUNTIME_DIR}" "${LEGACY_STATE_DIR}" "${LEGACY_DATA_DIR}" "${LEGACY_LOG_DIR}"; do
        if [[ -n "${legacy_path}" && "${legacy_path}" == "${HOME}/Library/"* && -e "${legacy_path}" ]]; then
            /bin/rm -rf "${legacy_path}"
        fi
    done

    if [[ -d "${LEGACY_APP_DIR}" && -z "$(/usr/bin/find "${LEGACY_APP_DIR}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        /bin/rmdir "${LEGACY_APP_DIR}"
    fi
}

cleanup_obsolete_raw_export() {
    local raw_export_path="${BASE_DIR}/raw_export"

    if [[ -L "${raw_export_path}" ]]; then
        /bin/rm -f "${raw_export_path}"
    elif [[ -d "${raw_export_path}" && -z "$(/usr/bin/find "${raw_export_path}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
        /bin/rmdir "${raw_export_path}"
    fi
}

validate_absolute_path "${BASE_DIR}" "BASE_DIR"
validate_managed_path "${STATE_DIR}" "STATE_DIR"
validate_managed_path "${LOG_DIR}" "LOG_DIR"

if [[ ! -f "${COMPRESSOR_DIR}/${COMPRESSOR_NAME}.sh" ]]; then
    die "当前压缩器模块不存在：${COMPRESSOR_DIR}/${COMPRESSOR_NAME}.sh"
fi

resolve_export_directory
ensure_oxipng
write_local_config

# 先停止旧挂载点，避免替换文件时仍有旧任务写入。
/bin/launchctl bootout "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true

/bin/mkdir -p "${AGENT_DIR}" "${BASE_DIR}"
materialize_directory "${SELECTED_TARGET_DIR}"
migrate_legacy_state_and_logs
cleanup_legacy_storage
cleanup_obsolete_raw_export
/bin/mkdir -p "${STATE_DIR}" "${LOG_DIR}"

/bin/chmod 700 "${BASE_DIR}" "${STATE_DIR}" "${LOG_DIR}" "${SELECTED_TARGET_DIR}"
/bin/chmod 700 "${WORKER_PATH}" "${COMPRESSOR_DIR}/"*.sh "${SCRIPT_DIR}/install.sh" "${SCRIPT_DIR}/uninstall.sh" "${SCRIPT_DIR}/status.sh" 2>/dev/null || true
/bin/chmod 600 "${CONFIG_PATH}" "${LOCAL_CONFIG_FILE}" 2>/dev/null || true

TEMP_PLIST="$(/usr/bin/mktemp "${AGENT_DIR}/.${LABEL}.XXXXXX")"
/bin/cp "${PLIST_TEMPLATE}" "${TEMP_PLIST}"

/usr/libexec/PlistBuddy -c "Set :ProgramArguments:1 ${WORKER_PATH}" "${TEMP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:2 ${CONFIG_PATH}" "${TEMP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :WatchPaths:0 ${SELECTED_TARGET_DIR}" "${TEMP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :WorkingDirectory ${SCRIPT_DIR}" "${TEMP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :EnvironmentVariables:HOME ${HOME}" "${TEMP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :StandardOutPath ${LOG_DIR}/launchd.out.log" "${TEMP_PLIST}"
/usr/libexec/PlistBuddy -c "Set :StandardErrorPath ${LOG_DIR}/launchd.err.log" "${TEMP_PLIST}"

if ! /usr/bin/plutil -lint "${TEMP_PLIST}" >/dev/null; then
    die "生成的 LaunchAgent 配置无效。"
fi

/bin/chmod 600 "${TEMP_PLIST}"
/bin/mv -f "${TEMP_PLIST}" "${AGENT_PATH}"

if ! /bin/launchctl bootstrap "${DOMAIN}" "${AGENT_PATH}"; then
    die "LaunchAgent 加载失败：${AGENT_PATH}"
fi

/bin/launchctl enable "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true
/bin/launchctl kickstart -k "${DOMAIN}/${LABEL}" >/dev/null 2>&1 || true

printf '\n安装完成。\n'
printf 'Figma 导出目录：%s\n' "${SELECTED_TARGET_DIR}"
printf '压缩方式：在原文件位置原子替换\n'
printf 'oxipng：%s\n' "${SELECTED_OXIPNG_BIN}"
printf '状态目录：%s\n' "${STATE_DIR}"
printf '日志目录：%s\n' "${LOG_DIR}"
