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
