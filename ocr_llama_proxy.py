# ========== 依赖安装说明 ==========
# 执行安装：pip install flask requests
# 必须先安装Ollama：curl -fsSL https://ollama.com/install.sh | sh
# 后台启动ollama：ollama serve &
# ==================================
import requests
import json
from flask import Flask, request

# 全局配置
OLLAMA_HOST = "http://127.0.0.1:11434"
OLLAMA_CHAT_URL = f"{OLLAMA_HOST}/api/chat"
TARGET_MODEL = "AuditAid/PaddleOCR-VL-1.6-0.9B"
APP_PORT = 8118

app = Flask(__name__)
# 放开大图请求限制
app.config["MAX_CONTENT_LENGTH"] = 100 * 1024 * 1024

MODEL_MAP = {
    "PaddleOCR-VL-1.6-0.9B": TARGET_MODEL
}

def check_ollama_service() -> bool:
    """检测ollama 11434端口是否可连通"""
    try:
        resp = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=3)
        return resp.status_code == 200
    except Exception:
        return False

def pull_model(model_name: str):
    """拉取指定模型"""
    print(f"未检测到模型 {model_name}，开始自动拉取...")
    pull_url = f"{OLLAMA_HOST}/api/pull"
    payload = {"model": model_name}
    try:
        requests.post(pull_url, json=payload, timeout=300)
        print(f"模型 {model_name} 拉取完成！")
    except Exception as e:
        print(f"模型拉取失败，请手动执行：ollama pull {model_name}，错误：{str(e)}")

def check_and_pull_model():
    """修复：只匹配模型前缀，忽略:latest标签"""
    resp = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=5)
    model_full_names = [item["name"] for item in resp.json()["models"]]
    # 判断规则：存在任意以目标模型名开头的模型即代表已安装
    has_model = any(name.startswith(TARGET_MODEL + ":") for name in model_full_names)
    if not has_model:
        pull_model(TARGET_MODEL)

def openai_to_ollama(payload):
    """OpenAI多模态格式转Ollama /api/chat 标准格式，图片内嵌message内部"""
    model_name = MODEL_MAP.get(payload.get("model", ""), payload.get("model", ""))
    ollama_req = {
        "model": model_name,
        "stream": payload.get("stream", False),
        "temperature": payload.get("temperature", 0.0),
        "messages": []
    }

    for msg in payload.get("messages", []):
        content = msg["content"]
        text_parts, imgs = [], []
        if isinstance(content, list):
            for part in content:
                if part["type"] == "text":
                    text_parts.append(part["text"])
                elif part["type"] == "image_url":
                    b64_raw = part["image_url"]["url"]
                    # 剥离data:image前缀
                    if b64_raw.startswith("data:image"):
                        b64_clean = b64_raw.split(",", 1)[1]
                    else:
                        b64_clean = b64_raw
                    # 清洗换行、空格、制表、回车
                    b64_clean = b64_clean.replace("\n", "").replace(" ", "").replace("\t", "").replace("\r", "")
                    imgs.append(b64_clean)
            new_msg = {"role": msg["role"], "content": "\n".join(text_parts)}
            if imgs:
                new_msg["images"] = imgs
        else:
            new_msg = {"role": msg["role"], "content": content}
        ollama_req["messages"].append(new_msg)
    return ollama_req

@app.route("/v1/chat/completions", methods=["POST"])
def proxy_chat():
    raw_payload = request.get_json()
    ollama_body = openai_to_ollama(raw_payload)
    resp = requests.post(OLLAMA_CHAT_URL, json=ollama_body, headers={"Content-Type": "application/json"})

    # 错误直接透传
    if resp.status_code != 200:
        return resp.content, resp.status_code

    # 转换为标准OpenAI返回结构
    ollama_resp = resp.json()
    openai_resp = {
        "model": ollama_resp.get("model", ""),
        "choices": [
            {
                "message": ollama_resp["message"],
                "finish_reason": ollama_resp.get("done_reason", "stop")
            }
        ]
    }
    return json.dumps(openai_resp, ensure_ascii=False), 200, {"Content-Type": "application/json"}

if __name__ == "__main__":
    print("===== OCR Ollama 代理服务启动前置检测 =====")
    # 1. 检测ollama服务
    if not check_ollama_service():
        print("❌ Ollama 服务未启动/11434端口不通！")
        print("1. 安装命令：curl -fsSL https://ollama.com/install.sh | sh")
        print("2. 后台启动服务：ollama serve &")
        exit(1)
    print("✅ Ollama 11434 端口连通正常")

    # 2. 检测并自动拉取目标OCR模型（已修复匹配逻辑）
    check_and_pull_model()
    print(f"✅ 模型 {TARGET_MODEL} 就绪")
    print(f"===== 代理服务启动，地址：http://0.0.0.0:{APP_PORT}/v1/chat/completions =====")
    app.run(host="0.0.0.0", port=APP_PORT, debug=False)
