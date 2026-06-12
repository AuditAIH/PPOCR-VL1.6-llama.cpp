#!/bin/bash
set -euo pipefail

###########################################################
# 逻辑规则（按要求定制）
# 1. 根目录 = 脚本执行的当前目录，启动sh文件创建在根目录
# 2. 固定查找根目录下的 llama.cpp_ppocrvl1.6 工作文件夹
# 3. tar压缩包：不存在则下载，存在则跳过下载；只要有tar包就强制解压覆盖
# 4. 全程外网直连，无国内代理/镜像
# 5. 自动检测文件夹、程序、模型、压缩包、sh脚本
# 6. 输出所有文件绝对路径，自动生成独立启动脚本
# 7. OCR测试结果仅输出前100字符
###########################################################

# ===================== 全局路径定义（基于当前执行目录） =====================
SCRIPT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
WORK_DIR_NAME="llama.cpp_ppocrvl1.6"
WORK_FULL_PATH="${SCRIPT_ROOT}/${WORK_DIR_NAME}"

MM_PROJ_FILE="PaddleOCR-VL-1.6-GGUF-mmproj.gguf"
MAIN_MODEL_FILE="PaddleOCR-VL-1.6-GGUF.gguf"
TAR_PACKAGE="ppocrvl1.6_cuda.tar.gz"
START_SCRIPT_NAME="start_up_llama_ppocrvl1.6.sh"
START_SCRIPT_FULLPATH="${SCRIPT_ROOT}/${START_SCRIPT_NAME}"

URL_MM_PROJ="https://www.modelscope.cn/models/Aid003/PaddleOCR-VL-1.6-GGUF/resolve/master/PaddleOCR-VL-1.6-GGUF-mmproj.gguf"
URL_MAIN_MODEL="https://www.modelscope.cn/models/Aid003/PaddleOCR-VL-1.6-GGUF/resolve/master/PaddleOCR-VL-1.6-GGUF.gguf"
TAR_URL="https://github.com/AuditAIH/PPOCR-VL1.6-llama.cpp/releases/download/1.0.1/ppocrvl1.6_cuda.tar.gz"
DEMO_PNG="paddleocr_vl_demo.png"

# ===================== 工具函数 =====================
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "[❌ 错误] 缺失工具：$1，请先安装后再运行！"
        exit 1
    fi
}

# ===================== 1. 检测系统依赖 =====================
echo "============================================="
echo "[1/8] 检测系统必备依赖"
check_dependency curl
check_dependency jq
check_dependency base64
check_dependency nc
check_dependency wget
echo "✅ 依赖检测通过"

# ===================== 2. 检测目标文件夹 & 内部所有文件 =====================
echo -e "\n============================================="
echo "[2/8] 检测工作文件夹：${WORK_DIR_NAME}"
if [ ! -d "${WORK_FULL_PATH}" ]; then
    echo "⚠️  文件夹不存在，自动创建：${WORK_FULL_PATH}"
    mkdir -p "${WORK_FULL_PATH}"
else
    echo "✅ 已找到目标文件夹：${WORK_FULL_PATH}"
fi

cd "${WORK_FULL_PATH}" || exit 1
echo -e "\n文件夹内文件预检："

[ -f "./llama-server" ] && echo "  ✅ 存在程序：llama-server" || echo "  ⚠️  缺失程序：llama-server"
[ -f "${MM_PROJ_FILE}" ] && echo "  ✅ 存在模型：${MM_PROJ_FILE}" || echo "  ⚠️  缺失模型：${MM_PROJ_FILE}"
[ -f "${MAIN_MODEL_FILE}" ] && echo "  ✅ 存在模型：${MAIN_MODEL_FILE}" || echo "  ⚠️  缺失模型：${MAIN_MODEL_FILE}"
[ -f "${TAR_PACKAGE}" ] && echo "  ✅ 存在压缩包：${TAR_PACKAGE}" || echo "  ⚠️  缺失压缩包：${TAR_PACKAGE}"

SH_NUM=$(find . -maxdepth 1 -name "*.sh" | wc -l)
if [ "${SH_NUM}" -gt 0 ]; then
    echo "  ✅ 目录内已有 ${SH_NUM} 个Shell脚本"
else
    echo "  ℹ️  目录内暂无Shell脚本"
fi

# ===================== 3. 下载GGUF模型 =====================
echo -e "\n============================================="
echo "[3/8] 检测并下载模型文件"

if [ ! -f "${MM_PROJ_FILE}" ]; then
    echo "开始下载投影模型：${MM_PROJ_FILE}"
    wget -c --progress=bar "${URL_MM_PROJ}"
else
    echo "✅ ${MM_PROJ_FILE} 已存在，跳过下载"
fi

if [ ! -f "${MAIN_MODEL_FILE}" ]; then
    echo "开始下载主模型：${MAIN_MODEL_FILE}"
    wget -c --progress=bar "${URL_MAIN_MODEL}"
else
    echo "✅ ${MAIN_MODEL_FILE} 已存在，跳过下载"
fi

# ===================== 4. 处理CUDA压缩包 =====================
echo -e "\n============================================="
echo "[4/8] 处理CUDA依赖压缩包"

if [ ! -f "${TAR_PACKAGE}" ]; then
    echo "未找到压缩包，开始下载：${TAR_PACKAGE}"
    wget -c --progress=bar "${TAR_URL}"
else
    echo "✅ ${TAR_PACKAGE} 已存在，跳过下载"
fi

echo "开始解压 ${TAR_PACKAGE}，自动覆盖现有文件..."
tar -zxvf "${TAR_PACKAGE}"
echo "✅ 压缩包解压完成"

CURR_WORK_ABS=$(pwd)

# ===================== 5. 生成独立启动脚本 =====================
echo -e "\n============================================="
echo "[5/8] 生成后续启动脚本（存放于根目录）"
cd "${SCRIPT_ROOT}" || exit 1

cat > "${START_SCRIPT_NAME}" << 'EOF'
#!/bin/bash
set -euo pipefail
RUN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
WORK_PATH="${RUN_ROOT}/llama.cpp_ppocrvl1.6"
cd "${WORK_PATH}" || exit 1
CUR_DIR=$(pwd)
export LD_LIBRARY_PATH="${CUR_DIR}:$LD_LIBRARY_PATH"
./llama-server \
  -m ./PaddleOCR-VL-1.6-GGUF.gguf \
  --mmproj ./PaddleOCR-VL-1.6-GGUF-mmproj.gguf  \
  --port 8118  \
  --host 0.0.0.0 \
  --temp 0 --parallel 12 --flash-attn on -b 2048
EOF

chmod +x "${START_SCRIPT_NAME}"
echo "✅ 启动脚本创建/更新成功"
echo "📌 启动脚本绝对路径：${START_SCRIPT_FULLPATH}"

# ===================== 6. 汇总文件路径 =====================
echo -e "\n============================================="
echo "[6/8] 全文件路径汇总"
echo "📂 工作文件夹：${WORK_FULL_PATH}"
echo "⚙️  主程序：${CURR_WORK_ABS}/llama-server"
echo "📦 依赖压缩包：${CURR_WORK_ABS}/${TAR_PACKAGE}"
echo "🧠 投影模型：${CURR_WORK_ABS}/${MM_PROJ_FILE}"
echo "🧠 主模型：${CURR_WORK_ABS}/${MAIN_MODEL_FILE}"
echo "🚀 后续启动脚本：bash ${START_SCRIPT_FULLPATH}"
echo -e "\n💡 日常启动命令：./${START_SCRIPT_NAME}"

# ===================== 7. 启动服务 + 端口检测 =====================
echo -e "\n============================================="
echo "[7/8] 启动OCR服务（端口 8118）"
cd "${CURR_WORK_ABS}" || exit 1
export LD_LIBRARY_PATH="${CURR_WORK_ABS}:$LD_LIBRARY_PATH"
echo "🔧 动态库加载路径：${LD_LIBRARY_PATH}"

# 临时后台启动
./llama-server \
  -m ./PaddleOCR-VL-1.6-GGUF.gguf \
  --mmproj ./PaddleOCR-VL-1.6-GGUF-mmproj.gguf  \
  --port 8118  \
  --host 0.0.0.0 \
  --temp 0 --parallel 12 --flash-attn on -b 2048 &

SERVER_PID=$!
echo "🚀 服务临时后台启动，进程PID：${SERVER_PID}"

# 等待端口
echo "⌛ 等待 8118 端口就绪..."
WAIT_SEC=0
while ! nc -z localhost 8118; do
    sleep 2
    WAIT_SEC=$((WAIT_SEC + 2))
    if [ ${WAIT_SEC} -ge 60 ]; then
        echo "[❌ 错误] 服务启动超时"
        kill ${SERVER_PID} 2>/dev/null || true
        exit 1
    fi
    echo "  已等待 ${WAIT_SEC}s"
done
echo "✅ 服务端口就绪"

# 额外延时：等待接口初始化完成（解决卡死）
echo "⌛ 等待接口初始化完成..."
sleep 5

# ===================== 8. OCR测试（修复语法错误） =====================
echo -e "\n============================================="
echo "[8/8] 执行OCR功能测试"

[ ! -f "${DEMO_PNG}" ] && curl -L -o "./${DEMO_PNG}" https://paddle-model-ecology.bj.bcebos.com/paddlex/imgs/demo_image/paddleocr_vl_demo.png

# 单独构造JSON，彻底规避语法错误
IMG_B64=$(base64 -w 0 "./${DEMO_PNG}")
JSON_BODY=$(cat <<JSON
{
  "model": "paddleocr-vl",
  "messages": [
    {
      "role": "user",
      "content": [
        {"type":"text","text":"OCR:"},
        {"type":"image_url","image_url":{"url":"data:image/png;base64,${IMG_B64}"}}
      ]
    }
  ],
  "temperature": 0
}
JSON
)

echo "正在识别图片..."
OCR_CONTENT=$(curl -s -X POST http://localhost:8118/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "${JSON_BODY}" | jq -r '.choices[0].message.content' | head -c 100)

echo -e "\n📝 OCR识别结果（前100字）："
echo "${OCR_CONTENT}"

# ===================== 切回前台常驻 =====================
echo -e "\n============================================="
echo "🎉 OCR测试完成，服务切换为前台运行"
echo "💡 停止服务：按下 Ctrl + C"
fg ${SERVER_PID}
