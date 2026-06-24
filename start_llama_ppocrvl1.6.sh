#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ====================== 配置区（动态适配用户目录） ======================
OLLAMA_ROOT="/usr/local/lib/ollama"
LLAMA_SERVER_BIN="${OLLAMA_ROOT}/llama-server"

# 模型缓存路径 - modelscope默认存储路径（目录名中点号替换为下划线）
MODEL_DIR="${HOME}/.cache/modelscope/hub/models/PaddlePaddle/PaddleOCR-VL-1___6-GGUF"
MAIN_FILE="PaddleOCR-VL-1.6-GGUF.gguf"
MMPROJ_FILE="PaddleOCR-VL-1.6-GGUF-mmproj.gguf"
HASH_FILE="${MODEL_DIR}/model_hash.txt"
MODEL_ABS="${MODEL_DIR}/${MAIN_FILE}"
MMPROJ_ABS="${MODEL_DIR}/${MMPROJ_FILE}"

# ========== 新增：模型标准SHA256（从ModelScope模型文件页获取填入） ==========
STD_SHA256_MAIN="f3ae46ec885050acf4b3d31944431e1fd90d50664fb09126af4a3c050ba14ee8"
STD_SHA256_MMPROJ="204d757d7610d9b3faab10d506d69e5b244e32bf765e2bab2d0167e65e0a058a"
# ========================================================================

# 下载地址
URL_MAIN_MODEL="https://www.modelscope.cn/models/PaddlePaddle/PaddleOCR-VL-1.6-GGUF/resolve/master/${MAIN_FILE}"
URL_MM_PROJ="https://www.modelscope.cn/models/PaddlePaddle/PaddleOCR-VL-1.6-GGUF/resolve/master/${MMPROJ_FILE}"

# 服务固定参数
PORT=8118
HOST="0.0.0.0"
TEMP=0
CUDA_DEV=0
START_SCRIPT_NAME="llama.cpp_paddleocr_vl_1.6.sh"
# ========================================================================

error_exit() {
    echo -e "\033[31m[ERROR] $1\033[0m" >&2
    exit 1
}
info_log() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

# ========== 新增：计算文件SHA256工具函数 ==========
calc_sha256() {
    local file_path="$1"
    sha256sum "${file_path}" | awk '{print $1}'
}

# ========== 1. 检测GPU + 驱动版本，匹配固定CUDA后端 ==========
info_log "1. 检测NVIDIA GPU与驱动版本"
if ! command -v nvidia-smi &> /dev/null; then
    error_exit "未检测到NVIDIA显卡驱动，仅支持GPU模式，不支持CPU运行"
fi

DRIVER_MAJOR=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 | cut -d. -f1)
if [ -z "${DRIVER_MAJOR}" ]; then
    error_exit "无法读取NVIDIA驱动版本，请检查显卡驱动安装"
fi
info_log "NVIDIA驱动主版本：${DRIVER_MAJOR}"

# ========== 2. 检测Ollama程序，未安装则自动执行官方命令安装 ==========
info_log "2. 检测Ollama运行环境"
if [ ! -f "${LLAMA_SERVER_BIN}" ]; then
    info_log "未检测到Ollama，开始自动执行官方命令安装..."
    curl -fsSL https://ollama.com/install.sh | sh
    
    if [ ! -f "${LLAMA_SERVER_BIN}" ]; then
        error_exit "Ollama自动安装后仍未找到llama-server，请检查上方安装日志"
    fi
    info_log "Ollama安装完成"
fi
info_log "Ollama环境校验通过"

if [ "${DRIVER_MAJOR}" -ge 550 ] && [ -f "${OLLAMA_ROOT}/cuda_v13/libggml-cuda.so" ]; then
    CUDA_LIB_DIR="${OLLAMA_ROOT}/cuda_v13"
    info_log "驱动支持CUDA 13，匹配cuda_v13后端"
elif [ -f "${OLLAMA_ROOT}/cuda_v12/libggml-cuda.so" ]; then
    CUDA_LIB_DIR="${OLLAMA_ROOT}/cuda_v12"
    info_log "匹配cuda_v12后端"
else
    error_exit "Ollama目录无可用CUDA后端，请手动执行 curl -fsSL https://ollama.com/install.sh | sh 重装最新版"
fi

GGML_BACKEND_PATH="${CUDA_LIB_DIR}/libggml-cuda.so"
LD_LIB_PATH="${OLLAMA_ROOT}:${CUDA_LIB_DIR}"

# ========== 3. 模型目录初始化 ==========
info_log "3. 初始化模型缓存目录：${MODEL_DIR}"
mkdir -p "${MODEL_DIR}" || error_exit "创建模型目录失败"
cd "${MODEL_DIR}" || error_exit "进入模型目录失败"

# 下载函数：覆盖模式（先删除已有文件，不使用 -c 断点续传，避免文件损坏）
download_file() {
    local fname="$1" furl="$2"
    info_log "开始下载：${fname}"
    # 覆盖模式：先删除可能存在的残留/损坏文件，确保每次都是完整的全新下载
    rm -f "${fname}"
    if ! wget --tries=3 --timeout=30 --progress=bar "${furl}"; then
        error_exit "下载失败: ${fname}"
    fi
    info_log "下载完成: ${fname}"
}

# ========== 4. 文件校验逻辑（核心修改：无哈希文件时先算本地哈希） ==========
info_log "4. 校验模型文件"
NEED_DOWNLOAD_MAIN=0
NEED_DOWNLOAD_MM=0

if [ -f "${HASH_FILE}" ]; then
    # 原有逻辑完全保留：有标记文件仅检查存在性
    info_log "检测到哈希标记文件，仅校验模型文件是否存在（不检测内容）"
    if [ -f "${MAIN_FILE}" ] && [ -f "${MMPROJ_FILE}" ]; then
        info_log "模型文件齐全，跳过下载"
    else
        info_log "模型文件缺失，需要重新下载缺失文件"
        [ ! -f "${MAIN_FILE}" ] && NEED_DOWNLOAD_MAIN=1
        [ ! -f "${MMPROJ_FILE}" ] && NEED_DOWNLOAD_MM=1
    fi
else
    # 仅修改此处：无哈希文件时，先计算本地文件哈希做完整性校验
    info_log "无哈希标记文件，先计算本地模型文件哈希进行完整性校验"

    # 校验主模型文件
    if [ -f "${MAIN_FILE}" ] && [ -n "${STD_SHA256_MAIN}" ]; then
        local_sha_main=$(calc_sha256 "${MAIN_FILE}")
        if [ "${local_sha_main}" = "${STD_SHA256_MAIN}" ]; then
            info_log "主模型文件哈希校验通过，无需下载"
        else
            info_log "主模型文件哈希不匹配，文件损坏，需重新下载"
            NEED_DOWNLOAD_MAIN=1
        fi
    else
        info_log "主模型文件不存在或未配置标准哈希，执行下载"
        NEED_DOWNLOAD_MAIN=1
    fi

    # 校验mmproj文件
    if [ -f "${MMPROJ_FILE}" ] && [ -n "${STD_SHA256_MMPROJ}" ]; then
        local_sha_mm=$(calc_sha256 "${MMPROJ_FILE}")
        if [ "${local_sha_mm}" = "${STD_SHA256_MMPROJ}" ]; then
            info_log "mmproj文件哈希校验通过，无需下载"
        else
            info_log "mmproj文件哈希不匹配，文件损坏，需重新下载"
            NEED_DOWNLOAD_MM=1
        fi
    else
        info_log "mmproj文件不存在或未配置标准哈希，执行下载"
        NEED_DOWNLOAD_MM=1
    fi
fi

# ========== 5. 下载缺失文件 ==========
if [ "${NEED_DOWNLOAD_MAIN}" -eq 1 ] || [ "${NEED_DOWNLOAD_MM}" -eq 1 ]; then
    cd "${MODEL_DIR}"
    [ "${NEED_DOWNLOAD_MAIN}" -eq 1 ] && download_file "${MAIN_FILE}" "${URL_MAIN_MODEL}"
    [ "${NEED_DOWNLOAD_MM}" -eq 1 ] && download_file "${MMPROJ_FILE}" "${URL_MM_PROJ}"
    
    # 下载完成后写入标准哈希到标记文件，下次启动直接走存在分支
    cat > "${HASH_FILE}" <<EOF
${MAIN_FILE}: ${STD_SHA256_MAIN}
${MMPROJ_FILE}: ${STD_SHA256_MMPROJ}
EOF
    info_log "模型下载完成，哈希标记已创建"
fi

# ========== 6. 生成纯硬编码启动脚本 ==========
info_log "5. 生成启动脚本：${START_SCRIPT_NAME}"
cat > "./${START_SCRIPT_NAME}" <<EOF
#!/bin/bash
# PaddleOCR-VL 1.6 服务启动脚本
# 自动生成，已匹配当前系统驱动与CUDA后端
# 服务监听：${HOST}:${PORT}

export GGML_BACKEND_PATH="${GGML_BACKEND_PATH}"
export LD_LIBRARY_PATH="${LD_LIB_PATH}"
export CUDA_VISIBLE_DEVICES=${CUDA_DEV}

${LLAMA_SERVER_BIN} \\
    -m ${MODEL_ABS} \\
    --mmproj ${MMPROJ_ABS} \\
    --port ${PORT} \\
    --host ${HOST} \\
    --temp ${TEMP}
EOF

chmod +x "./${START_SCRIPT_NAME}"

info_log "========================================"
info_log "所有前置校验完成，自动启动服务"
info_log "启动脚本路径：$(pwd)/${START_SCRIPT_NAME}"
info_log "服务地址：http://${HOST}:${PORT}"
info_log "========================================"

# ========== 7. 直接执行启动脚本 ==========
bash "./${START_SCRIPT_NAME}"
