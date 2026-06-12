# 快速开始 （Quick Start） （如需代理请在github的http前面追加https://gh-proxy.org/
```
wget https://raw.githubusercontent.com/AuditAIH/PPOCR-VL1.6-llama.cpp/main/start_llama_ppocrvl1.6.sh -O start_llama_ppocrvl1.6.sh
bash start_llama_ppocrvl1.6.sh
```

## 直接执行二进制程序

```
# 创建目录并下载解压预编译包，-p确保目录存在
# Create dir & download/extract precompiled package (-p ensures dir existence)
mkdir -p llama.cpp_ppocrvl1.6 && wget -O - https://github.com/AuditAIH/llama.cpp_rerank/releases/download/0.0.3/0.0.3_20260610_cuda13.2_ubuntu26.04_amd64_allcuda.gz | tar -zxf - -C llama.cpp_ppocrvl1.6/

# 切换工作目录到解压后的程序目录
# Switch working directory to the extracted program directory
cd llama.cpp_ppocrvl1.6

# 添加CUDA v13库路径，解决程序运行依赖，如果没有安装ollama，则需要从英伟达官网自行安装cuda13
# Add CUDA v13 lib path to resolve program runtime dependencies
# export LD_LIBRARY_PATH=/usr/local/lib/ollama/cuda_v13:$LD_LIBRARY_PATH

# 测试llama-server是否可执行，-h输出帮助信息
# Test if llama-server is executable, -h outputs help information
./llama-server -h

```

## 或从源码编译
```
# 1、下载编译工具
sudo apt update && apt install -y cmake gcc g++ libcurl4-openssl-dev
```
如需下载cuda，apt install -y nvidia-cuda-toolkit [参考NVDIA官网](https://developer.nvidia.com/CUDA-TOOLKIT-ARCHIVE)
```
# 下载最新版本的llama.cpp
git clone --depth 1 https://github.com/ggml-org/llama.cpp

cd llama.cpp

 # -DGGML_NATIVE=OFF 非本地GPU构建，可以迁移到别的不同GPU
cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=OFF

# 2. 并行编译（核心加速！-j 后接线程数，$(nproc) 自动获取 CPU 核心数）
cmake --build build --config Release -j$(nproc)
```
编译完成后，运行
`./build/bin/llama-server -h` 测试


## 下载PaddleOCR-VL1.6模型文件
```
modelscope download --model Aid003/PaddleOCR-VL-1.6-GGUF README.md PaddleOCR-VL-1.6-GGUF-mmproj.gguf PaddleOCR-VL-1.6-GGUF.gguf
# 或使用wget下载
# 下载投影文件
wget -c https://www.modelscope.cn/models/Aid003/PaddleOCR-VL-1.6-GGUF/resolve/master/PaddleOCR-VL-1.6-GGUF-mmproj.gguf

# 下载主模型文件
wget -c https://www.modelscope.cn/models/Aid003/PaddleOCR-VL-1.6-GGUF/resolve/master/PaddleOCR-VL-1.6-GGUF.gguf
```

## 启动OCR识别
```
# 直接启动8118端口
llama-server \
    -m /path/to/PaddleOCR-VL-1.6-GGUF.gguf \
    --mmproj /path/to/PaddleOCR-VL-1.6-GGUF-mmproj.gguf  \
    --port 8118  \
    --host 0.0.0.0 \
    --temp 0

# 或者加速启动

#!/bin/bash
#cd /root/llama.cpp/build/bin || exit
#export LD_LIBRARY_PATH=/usr/local/lib/ollama/cuda_v13:$LD_LIBRARY_PATH
./llama-server \
  -m ./PaddleOCR-VL-1.6-GGUF.gguf \
  --mmproj ./PaddleOCR-VL-1.6-GGUF-mmproj.gguf  \
  --port 8118  \
  --host 0.0.0.0 \
  --temp 0 --parallel 12 --flash-attn on -b 2048

# 直接请求
wget -O ./paddleocr_vl_demo.png https://paddle-model-ecology.bj.bcebos.com/paddlex/imgs/demo_image/paddleocr_vl_demo.png && llama-cli -m ./PaddleOCR-VL-1.6-GGUF.gguf --mmproj ./PaddleOCR-VL-1.6-GGUF-mmproj.gguf -p 'OCR:' --image ./paddleocr_vl_demo.png --single-turn
```

## 或者从8118端口直接解析
```
curl -L -o ./paddleocr_vl_demo.png https://paddle-model-ecology.bj.bcebos.com/paddlex/imgs/demo_image/paddleocr_vl_demo.png && \
cat << EOF | curl -s -X POST http://localhost:8118/v1/chat/completions -H "Content-Type: application/json" -d @- | jq -r '.choices[0].message.content'
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
            "url": "data:image/png;base64,$(base64 -w0 ./paddleocr_vl_demo.png)"
          }
        }
      ]
    }
  ],
  "temperature": 0
}
EOF
```

## 或者结合PaddleOCR进行版面解析 (提前安装好PaddlePaddle和PaddleOCR）
### [参考官网安装步骤](https://www.paddleocr.ai/main/quick_start.html)
```
python -m pip install paddlepaddle-gpu==3.3.1 -i https://www.paddlepaddle.org.cn/packages/stable/cu130/
# uv pip install paddlepaddle-gpu==3.3.1 -i https://www.paddlepaddle.org.cn/packages/stable/cu130/
python -m pip install "paddleocr[all]"
# uv pip install "paddleocr[all]"
paddleocr doc_parser --input https://paddle-model-ecology.bj.bcebos.com/paddlex/imgs/demo_image/paddleocr_vl_demo.png --vl_rec_backend llama-cpp-server --vl_rec_server_url http://localhost:8118/v1

```
