"""
生成天空盒全景图脚本
- 读取 Skybox.json (ComfyUI API workflow)
- 自动设置随机种子
- 发送到 ComfyUI (localhost:8188)
- 等待生成完成
- 下载图片并保存到 textures/skybox/space_panorama.png

用法:
  python generate_skybox.py              # 随机种子
  python generate_skybox.py --seed 123   # 指定种子
"""

import json
import os
import random
import sys
import time
import urllib.request
import urllib.error

COMFYUI_URL = "http://127.0.0.1:8188"
WORKFLOW_PATH = os.path.join(os.path.dirname(__file__), "Skybox.json")
OUTPUT_PATH = os.path.join(os.path.dirname(__file__), "..", "textures", "skybox", "space_panorama.png")

# KSampler 节点的 ID
KSAMPLER_NODE_ID = "72:70"


def queue_prompt(workflow: dict) -> str:
    """发送工作流到 ComfyUI 并返回 prompt_id"""
    payload = json.dumps({"prompt": workflow}).encode("utf-8")
    req = urllib.request.Request(
        f"{COMFYUI_URL}/prompt",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data["prompt_id"]


def get_history(prompt_id: str) -> dict | None:
    """查询生成历史，完成时返回结果，否则返回 None"""
    try:
        req = urllib.request.Request(f"{COMFYUI_URL}/history/{prompt_id}")
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        return data.get(prompt_id)
    except urllib.error.HTTPError:
        return None


def download_image(filename: str, subfolder: str, folder_type: str) -> bytes:
    """从 ComfyUI 下载生成的图片"""
    params = f"?filename={filename}&subfolder={subfolder}&type={folder_type}"
    url = f"{COMFYUI_URL}/view{params}"
    with urllib.request.urlopen(url) as resp:
        return resp.read()


def main():
    # 解析命令行参数
    seed = random.randint(0, 2**63 - 1)
    if "--seed" in sys.argv:
        idx = sys.argv.index("--seed")
        if idx + 1 < len(sys.argv):
            seed = int(sys.argv[idx + 1])

    print(f"🎲 种子: {seed}")

    # 1. 读取工作流
    print(f"📖 读取工作流: {WORKFLOW_PATH}")
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        workflow = json.load(f)

    # 2. 注入随机种子
    if KSAMPLER_NODE_ID in workflow:
        workflow[KSAMPLER_NODE_ID]["inputs"]["seed"] = seed
        print(f"   KSampler 种子已设为 {seed}")
    else:
        print(f"⚠️  未找到 KSampler 节点 {KSAMPLER_NODE_ID}，使用工作流默认种子")

    # 3. 发送到 ComfyUI
    print("🚀 发送到 ComfyUI...")
    prompt_id = queue_prompt(workflow)
    print(f"   Prompt ID: {prompt_id}")

    # 4. 轮询等待完成
    print("⏳ 等待生成中...", end="", flush=True)
    while True:
        history = get_history(prompt_id)
        if history:
            print()
            print("✅ 生成完成！")
            break
        time.sleep(2)
        print(".", end="", flush=True)

    # 5. 获取输出信息
    outputs = history.get("outputs", {})
    image_info = None
    for node_id, node_output in outputs.items():
        if "images" in node_output:
            images = node_output["images"]
            if images:
                image_info = images[0]
                break

    if not image_info:
        print("❌ 未找到输出图片")
        return

    filename = image_info["filename"]
    subfolder = image_info["subfolder"]
    folder_type = image_info["type"]

    print(f"📷 下载图片: {filename}")

    # 6. 下载图片
    img_data = download_image(filename, subfolder, folder_type)

    # 7. 保存到项目目录
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    with open(OUTPUT_PATH, "wb") as f:
        f.write(img_data)
    print(f"💾 已保存到: {OUTPUT_PATH}")
    print(f"   ({len(img_data) / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
