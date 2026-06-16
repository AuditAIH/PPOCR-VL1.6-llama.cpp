import sys
import json
import socket
import subprocess
import os
import time
import uuid
from pathlib import Path
from docx import Document
from docxcompose.composer import Composer

# ===================== 核心配置 =====================
START_PORT = 8118
LLAMA_SERVER_BIN = "/root/llama.cpp/build/bin/llama-server"
MODEL_PATH = "/root/paddleocr_gpu/models/PaddleOCR-VL-1.6-GGUF.gguf"
MMPROJ_PATH = "/root/paddleocr_gpu/models/PaddleOCR-VL-1.6-GGUF-mmproj.gguf"
os.environ["LD_LIBRARY_PATH"] = "/usr/local/lib/ollama/cuda_v13:" + os.environ.get("LD_LIBRARY_PATH", "")
# ====================================================

def get_available_port(start: int = 8118) -> int:
    port = start
    while True:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.1)
            if s.connect_ex(("localhost", port)) != 0:
                return port
        port += 1

def stop_process_by_port(port: int):
    try:
        subprocess.run(f"lsof -i:{port} | grep LISTEN | awk '{{print $2}}' | xargs kill -9 2>/dev/null", shell=True, check=False)
        time.sleep(0.3)
    except:
        pass

# ===================== 🔥 合并所有DOCX+完美保留样式 =====================
def merge_official_docx(official_dir, output_docx):
    docx_files = list(Path(official_dir).glob("*.docx"))
    if not docx_files:
        print("提示：没有找到任何DOCX文件，跳过合并", file=sys.stderr)
        return
    
    # 完全保留你原有的安全排序逻辑
    def safe_sort_key(file_path):
        try:
            return int(file_path.stem.split('_')[-1])
        except:
            return file_path.name
    
    docx_files.sort(key=safe_sort_key)
    total_files = len(docx_files)
    print(f"找到 {total_files} 个DOCX文件，开始合并...", file=sys.stderr)
    
    # 使用第一个文档作为基础
    master_doc = Document(str(docx_files[0]))
    composer = Composer(master_doc)
    
    # 合并剩余所有文档（直接末尾追加，不插入分页符）
    success_count = 1  # 第一个已经作为基础
    for doc_file in docx_files[1:]:
        try:
            temp_doc = Document(str(doc_file))
            composer.append(temp_doc)  # 默认行为：直接追加，不插入分页符
            success_count += 1
            print(f"成功合并: {doc_file.name} ({success_count}/{total_files})", file=sys.stderr)
        except Exception as e:
            print(f"警告：合并文件 {doc_file.name} 失败: {e}", file=sys.stderr)
            continue
    
    # 保存最终合并文档
    master_doc.save(output_docx)
    print(f"✅ 合并完成！共成功合并 {success_count}/{total_files} 个DOCX文件", file=sys.stderr)

# ===================== 仅生成DOCX+新增MD，完全保留原有逻辑 =====================
def official_way_generate(file_path, server_url, uuid_root):
    from paddleocr import PaddleOCRVL
    pipeline = PaddleOCRVL(vl_rec_backend="llama-cpp-server", vl_rec_server_url=server_url)
    
    # 仅解析1次
    output = pipeline.predict(file_path)

    # 生成并合并Word（合并所有文件）
    official_save_dir = Path(uuid_root) / "official_output"
    official_save_dir.mkdir(parents=True, exist_ok=True)
    for res in output:
        res.save_to_word(save_path=str(official_save_dir))
    final_docx = Path(uuid_root) / f"{Path(file_path).stem}.docx"
    merge_official_docx(official_save_dir, str(final_docx))

    # ===================== 【仅新增】你要的MD生成逻辑，无任何修改 =====================
    markdown_contents = []
    for i, res in enumerate(output):
        markdown_content = res.markdown.get('markdown_texts', '')
        markdown_contents.append(f"--- 第{i+1}页 ---\n{markdown_content}")
    md_result = "\n\n".join(markdown_contents) or "未识别到内容"
    # 保存 MD 文件
    md_file = Path(uuid_root) / f"{Path(file_path).stem}.md"
    md_file.write_text(md_result, encoding='utf-8')

    # 返回docx路径 + md路径
    return str(final_docx), str(md_file)

# ===================== 主程序 =====================
if __name__ == "__main__":
    server_process = None
    current_port = None

    try:
        if len(sys.argv) != 2:
            print(json.dumps({"error": "Usage: python ocrtabledocx.py <file_path>"}), file=sys.stderr)
            exit(1)
        input_file = sys.argv[1]

        current_port = get_available_port(START_PORT)
        server_url = f"http://localhost:{current_port}/v1"
        server_process = subprocess.Popen(
            [
                LLAMA_SERVER_BIN,
                "-m", MODEL_PATH,
                "--mmproj", MMPROJ_PATH,
                "--port", str(current_port),
                "--host", "0.0.0.0",
                "--temp", "0",
                "--parallel", "12",
                "--flash-attn", "on",
                "-b", "2048"
            ],
            cwd=os.path.dirname(LLAMA_SERVER_BIN),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )

        time.sleep(3)
        for _ in range(20):
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(0.1)
                if s.connect_ex(("localhost", current_port)) == 0:
                    break
            time.sleep(1)

        uuid_dir = str(uuid.uuid4())
        out_root = Path("./out")
        uuid_save_dir = out_root / uuid_dir
        uuid_save_dir.mkdir(parents=True, exist_ok=True)

        # 只生成DOCX+MD，完全保留原有调用方式
        docx_path, md_path = official_way_generate(input_file, server_url, uuid_save_dir)

        # 【仅输出路径，无MD内容】完全符合你的要求
        print(json.dumps({
            "status": "success",
            "type": "ocrtable",
            "docx_path": os.path.abspath(docx_path),
            "md_path": os.path.abspath(md_path)
        }, ensure_ascii=False))

    except Exception as e:
        print(json.dumps({"status": "error", "error": str(e)}), ensure_ascii=False)

    finally:
        if server_process:
            server_process.terminate()
            server_process.kill()
        if current_port:
            stop_process_by_port(current_port)