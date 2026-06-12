#!/bin/bash
set -euo pipefail

###########################################################
# 功能更新：
# 1. 替换为官方GitHub Release依赖包地址
# 2. 废弃ollama cuda库，使用当前目录作为动态链接库路径
# 3. 兼容GitHub镜像代理、手动下载等场景
###########################################################

# ===================== 1. 基础配置 & 获取脚本绝对目录 =====================
# 获取脚本真实所在目录（规避相对路径/软链接问题）
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "${SCRIPT_DIR}" || exit 1

# 文件名与路径配置
WORK_DIR="llama.cpp_ppocrvl1.6"
MM_PROJ_FILE="PaddleOCR-VL-1.6-GGUF-mmproj.gguf"
MAIN_MODEL_FILE="PaddleOCR-VL-1.6-GGUF.gguf"
TAR_PACKAGE="ppocrvl1.6_cuda.tar.gz"
START_SCRIPT_NAME="start_up_llama_ppocrvl1.6.sh"

# 模型下载地址（国内可正常访问）
URL_MM_PROJ="https://www.modelscope.cn/models/Aid003/PaddleOCR-VL-1.6-GGUF/resolve/master/PaddleOCR-VL-1.6-GGUF-mmproj.gguf"
URL_MAIN_MODEL="https://www.modelscope.cn/models/Aid003/PaddleOCR-VL-1.6-GGUF/resolve/master/PaddleOCR-VL-1.6-GGUF.gguf"

# 原始境外依赖包地址（国内直连失败请尝试代理地址）
TAR_URL="https://github.com/AuditAIH/PPOCR-VL1.6-llama.cpp/releases/download/1.0.1/ppocrvl1.6_cuda.tar.gz"

# ===================== 2. 系统依赖检测 =====================
check_dependency() {
    if ! command -v "$1" &> /dev/null; then
        echo "[错误] 缺失工具：$1，请先安装后再运行脚本！"
        exit 1
    fi
}

echo "[1/7] 检测系统必备依赖..."
check_dependency curl
check_dependency jq
check_dependency base64
check_dependency nc
check_dependency wget
echo "✅ 依赖检测通过"

# ===================== 3. 检测 llama-server & 切换工作目录 =====================
echo -e "\n[2/7] 检测 llama-server 程序..."
if [ ! -f "./llama-server" ]; then
    echo "未找到 llama-server，创建专属工作目录：${WORK_DIR}"
    mkdir -p "${WORK_DIR}"
    cd "${WORK_DIR}" || exit 1
else
    echo "✅ 已存在 llama-server，使用当前目录运行"
fi
CURRENT_WORK_DIR=$(pwd)

# ===================== 4. 断点续传下载 GGUF 模型（国内正常访问） =====================
# 下载 mmproj 模型
echo -e "\n[3/7] 检测并下载 MMProj 模型..."
if [ ! -f "${MM_PROJ_FILE}" ]; then
    echo "开始下载：${MM_PROJ_FILE}"
    wget -c --progress=bar "${URL_MM_PROJ}"
else
    echo "✅ ${MM_PROJ_FILE} 已存在，跳过下载"
fi

# 下载主模型
echo -e "\n[4/7] 检测并下载主模型..."
if [ ! -f "${MAIN_MODEL_FILE}" ]; then
    echo "开始下载：${MAIN_MODEL_FILE}"
    wget -c --progress=bar "${URL_MAIN_MODEL}"
else
    echo "✅ ${MAIN_MODEL_FILE} 已存在，跳过下载"
fi

# ===================== 5. 下载并解压 CUDA 依赖包（核心修改：本地so库） =====================
echo -e "\n[5/7] 检测并解压 CUDA 依赖包..."
if [ ! -f "${TAR_PACKAGE}" ]; then
    echo "开始下载依赖包（使用GitHub国内镜像）：${TAR_PACKAGE}"
    wget -c --progress=bar "${TAR_URL}"
else
    echo "✅ ${TAR_PACKAGE} 已存在，跳过下载"
fi

# 解压压缩包（内含所有.so依赖 + 测试图片）
echo "解压 ${TAR_PACKAGE} 到当前目录..."
tar -zxvf "${TAR_PACKAGE}"
echo "✅ 依赖包解压完成，当前目录已包含所有动态链接库"

# ===================== 6. 回到根目录，生成独立启动脚本（库路径已修改） =====================
echo -e "\n[6/7] 生成独立启动脚本 ${START_SCRIPT_NAME} ..."
cd "${SCRIPT_DIR}" || exit 1

# 生成独立启动脚本：使用【当前绝对目录】作为动态库路径，废弃ollama配置
cat > "${START_SCRIPT_NAME}" << 'EOF'
#!/bin/bash
set -euo pipefail

# 获取启动脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
cd "${SCRIPT_DIR}" || exit 1

# 工作目录
WORK_DIR="llama.cpp_ppocrvl1.6"
if [ -d "${WORK_DIR}" ]; then
    cd "${WORK_DIR}" || exit 1
fi

# ========== 核心配置：当前目录优先加载.so库，不再使用ollama路径 ==========
CUR_DIR=$(pwd)
export LD_LIBRARY_PATH="${CUR_DIR}:$LD_LIBRARY_PATH"

# 前台启动服务
./llama-server \
  -m ./PaddleOCR-VL-1.6-GGUF.gguf \
  --mmproj ./PaddleOCR-VL-1.6-GGUF-mmproj.gguf  \
  --port 8118  \
  --host 0.0.0.0 \
  --temp 0 --parallel 12 --flash-attn on -b 2048
EOF

chmod +x "${START_SCRIPT_NAME}"
echo "✅ 独立启动脚本创建完成！单独启动命令：./${START_SCRIPT_NAME}"

# ===================== 7. 启动服务 + OCR自动测试 + 前台保活 =====================
echo -e "\n[7/7] 准备启动服务并执行OCR测试..."
cd "${CURRENT_WORK_DIR}" || exit 1

# 全局设置动态链接库：当前目录优先（关键配置）
export LD_LIBRARY_PATH="${CURRENT_WORK_DIR}:$LD_LIBRARY_PATH"
echo "🔧 动态链接库搜索路径：${LD_LIBRARY_PATH}"

# 后台启动服务
echo "🚀 启动 llama-server 服务（端口 8118）"
./llama-server \
  -m ./PaddleOCR-VL-1.6-GGUF.gguf \
  --mmproj ./PaddleOCR-VL-1.6-GGUF-mmproj.gguf  \
  --port 8118  \
  --host 0.0.0.0 \
  --temp 0 --parallel 12 --flash-attn on -b 2048 &

SERVER_PID=$!
echo "服务进程 PID：${SERVER_PID}"

# 等待端口就绪（超时60秒）
echo "⌛ 等待 8118 端口就绪..."
WAIT_SEC=0
while ! nc -z localhost 8118; do
    sleep 2
    WAIT_SEC=$((WAIT_SEC + 2))
    echo "已等待 ${WAIT_SEC}s"
    if [ ${WAIT_SEC} -ge 60 ]; then
        echo "[错误] 服务启动超时，请检查.so库与模型文件！"
        kill ${SERVER_PID} 2>/dev/null || true
        exit 1
    fi
done
echo "✅ 服务端口就绪"

# 下载测试图片 + 调用OCR接口
DEMO_PNG="paddleocr_vl_demo.png"
echo -e "\n===== 下载演示图片 ====="
curl -L -o "./${DEMO_PNG}" https://paddle-model-ecology.bj.bcebos.com/paddlex/imgs/demo_image/paddleocr_vl_demo.png

echo -e "\n===== 执行OCR接口请求 ====="
curl -s -X POST http://localhost:8118/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d @- << JSON_BODY | jq -r '.choices[0].message.content'
{
  "model": "paddleocr-vl",
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "OCR:"
        },
        {
          "type": "image_url",
          "image_url": {
            "url": "data:image/png;base64,$(base64 -w0 ./${DEMO_PNG})"
          }
        }
      ]
    }
  ],
  "temperature": 0
}
JSON_BODY

echo -e "\n===== OCR 测试完成 ====="
echo -e "\n服务持续运行中，按【Ctrl + C】终止服务"

# 前台阻塞保活服务
wait ${SERVER_PID}
