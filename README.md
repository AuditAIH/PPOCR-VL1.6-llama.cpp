# 快速开始 （Quick Start） 
## 如需代理请在github的http前面追加https://gh-proxy.org/https://raw.git...
```
wget https://raw.githubusercontent.com/AuditAIH/PPOCR-VL1.6-llama.cpp/main/start_llama_ppocrvl1.6.sh -O start_llama_ppocrvl1.6.sh
bash start_llama_ppocrvl1.6.sh
```

## 直接执行二进制程序

```
# 下载并安装ollama
curl -fsSL https://ollama.com/install.sh | sh

# 拉取PaddleOCR-VL-1.6模型
ollama pull AuditAid/PaddleOCR-VL-1.6-0.9B

# 直接启动ollama预编译的二进制文件和相应的OCR模型。
export GGML_BACKEND_PATH=/usr/local/lib/ollama/cuda_v13/libggml-cuda.so
export LD_LIBRARY_PATH=/usr/local/lib/ollama:/usr/local/lib/ollama/cuda_v13
export CUDA_VISIBLE_DEVICES=0

/usr/local/lib/ollama/llama-server \
--model /usr/share/ollama/.ollama/models/blobs/sha256-e791f710e32aef14c3c0bcdebe54f46883d49e8882ad554dab11f74f584c9387 \
--mmproj /usr/share/ollama/.ollama/models/blobs/sha256-204d757d7610d9b3faab10d506d69e5b244e32bf765e2bab2d0167e65e0a058a \
--port 8118 \
--host 0.0.0.0 \
--temp 0

# 加速启动 --temp 0 --parallel 12 --flash-attn on -b 2048

# 或由ollama的11434端口接管，自动加载和卸载模型
wget https://raw.githubusercontent.com/AuditAIH/PPOCR-VL1.6-llama.cpp/main/ocr_llama_proxy.py -O ocr_llama_proxy.py
python ocr_llama_proxy.py

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

# 用版面解析前，请先确保按照前序步骤启动好8118端口的vlm后端。
paddleocr doc_parser --input https://paddle-model-ecology.bj.bcebos.com/paddlex/imgs/demo_image/paddleocr_vl_demo.png --vl_rec_backend llama-cpp-server --vl_rec_server_url http://localhost:8118/v1

# [服务化部署，请参考官方](https://www.paddleocr.ai/main/version3.x/pipeline_usage/PaddleOCR-VL.html#441)
paddlex --install serving
paddlex --get_pipeline_config PaddleOCR-VL-1.6

# 替换配置文件，增加8118后端
sed -i '/genai_config:/,/      backend: native/c\    genai_config:\n      backend: llama-cpp-server\n      server_url: http://localhost:8118/v1' PaddleOCR-VL-1.6.yaml
# 默认开放在8080端口，请先确保端口不被占用
paddlex --serve --pipeline ./PaddleOCR-VL-1.6.yaml --port 8080

```
