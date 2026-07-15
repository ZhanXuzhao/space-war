"""
生成 6 面天空盒贴图（Cubemap）
- 读取 Skybox_Cubemap.json (ComfyUI API workflow)
- 为每个面（右/左/上/下/前/后）设置不同的提示词和种子
- 分别发送到 ComfyUI (localhost:8188)
- 下载 6 张图片并保存到 textures/skybox/

用法:
  python generate_skybox_cubemap.py              # 随机种子
  python generate_skybox_cubemap.py --seed 123   # 指定基础种子（每个面seed会+1）
"""

import json
import os
import random
import sys
import time
import urllib.request
import urllib.error

COMFYUI_URL = "http://127.0.0.1:8188"
WORKFLOW_PATH = os.path.join(os.path.dirname(__file__), "Skybox_Cubemap.json")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "textures", "skybox")

# 6 个面的定义（文件名, 面名称, 描述提示词）
CUBEMAP_FACES = [
    ("space_right.png",  "right",  "deep space view looking towards the RIGHT direction, stunning nebula with purple and blue cosmic clouds, countless bright stars, Milky Way galaxy, cosmic dust, vibrant interstellar space, photorealistic, high detail, space background, cubemap right face"),
    ("space_left.png",   "left",   "deep space view looking towards the LEFT direction, stunning nebula with purple and blue cosmic clouds, countless bright stars, Milky Way galaxy, cosmic dust, vibrant interstellar space, photorealistic, high detail, space background, cubemap left face"),
    ("space_top.png",    "top",    "deep space view looking UPWARDS, stunning nebula with purple and blue cosmic clouds, countless bright stars, Milky Way galaxy, cosmic dust, vibrant interstellar space, photorealistic, high detail, space background, cubemap top face, looking up at the cosmos"),
    ("space_bottom.png", "bottom", "deep space view looking DOWNWARDS, stunning nebula with purple and blue cosmic clouds, countless bright stars, Milky Way galaxy, cosmic dust, vibrant interstellar space, photorealistic, high detail, space background, cubemap bottom face, looking down"),
    ("space_front.png",  "front",  "deep space view looking FORWARD, stunning nebula with purple and blue cosmic clouds, countless bright stars, Milky Way galaxy, cosmic dust, vibrant interstellar space, photorealistic, high detail, space background, cubemap front face"),
    ("space_back.png",   "back",   "deep space view looking BACKWARDS, stunning nebula with purple and blue cosmic clouds, countless bright stars, Milky Way galaxy, cosmic dust, vibrant interstellar space, photorealistic, high detail, space background, cubemap back face"),
]

# KSampler 节点和 CLIP 文本编码节点的 ID
KSAMPLER_NODE_ID = "72:70"
CLIP_ENCODE_NODE_ID = "72:67"
LATENT_NODE_ID = "72:68"


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


def generate_face(workflow_template: dict, prompt_text: str, seed: int, face_name: str) -> bool:
    """为单个 cubemap 面生成图片，返回是否成功"""
    workflow = json.loads(json.dumps(workflow_template))  # 深拷贝

    # 设置提示词
    if CLIP_ENCODE_NODE_ID in workflow:
        workflow[CLIP_ENCODE_NODE_ID]["inputs"]["text"] = prompt_text

    # 设置种子
    if KSAMPLER_NODE_ID in workflow:
        workflow[KSAMPLER_NODE_ID]["inputs"]["seed"] = seed

    # 设置正方形尺寸
    if LATENT_NODE_ID in workflow:
        workflow[LATENT_NODE_ID]["inputs"]["width"] = 1024
        workflow[LATENT_NODE_ID]["inputs"]["height"] = 1024

    print(f"  🚀 发送到 ComfyUI...")
    prompt_id = queue_prompt(workflow)
    print(f"     Prompt ID: {prompt_id}")

    # 轮询等待完成
    print(f"  ⏳ 等待生成中...", end="", flush=True)
    while True:
        history = get_history(prompt_id)
        if history:
            print()
            print(f"  ✅ 生成完成！")
            break
        time.sleep(2)
        print(".", end="", flush=True)

    # 获取输出信息
    outputs = history.get("outputs", {})
    image_info = None
    for node_id, node_output in outputs.items():
        if "images" in node_output:
            images = node_output["images"]
            if images:
                image_info = images[0]
                break

    if not image_info:
        print(f"  ❌ 未找到输出图片")
        return False

    filename = image_info["filename"]
    subfolder = image_info["subfolder"]
    folder_type = image_info["type"]

    print(f"  📷 下载图片: {filename}")

    # 下载图片
    img_data = download_image(filename, subfolder, folder_type)

    # 保存到项目目录
    output_path = os.path.join(OUTPUT_DIR, face_name)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(output_path, "wb") as f:
        f.write(img_data)
    print(f"  💾 已保存到: {output_path} ({len(img_data) / 1024:.0f} KB)")

    return True


def main():
    # 解析命令行参数
    base_seed = random.randint(0, 2**63 - 1)
    if "--seed" in sys.argv:
        idx = sys.argv.index("--seed")
        if idx + 1 < len(sys.argv):
            base_seed = int(sys.argv[idx + 1])

    print(f"🎲 基础种子: {base_seed}")
    print(f"📁 输出目录: {OUTPUT_DIR}")
    print()

    # 1. 读取工作流模板
    print(f"📖 读取工作流: {WORKFLOW_PATH}")
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        workflow_template = json.load(f)

    # 2. 为每个面生成图片
    success_count = 0
    for i, (face_filename, face_name, face_prompt) in enumerate(CUBEMAP_FACES):
        face_seed = base_seed + i
        print(f"\n{'='*60}")
        print(f"面 {i+1}/6: {face_name} ({face_filename})")
        print(f"  种子: {face_seed}")
        print(f"  提示词: {face_prompt[:60]}...")

        if generate_face(workflow_template, face_prompt, face_seed, face_filename):
            success_count += 1

        # 短暂停顿避免请求过快
        if i < 5:
            time.sleep(1)

    # 3. 总结
    print(f"\n{'='*60}")
    print(f"\n📊 生成完成: {success_count}/6 个面成功")
    if success_count == 6:
        print("✅ 所有 6 张天空盒贴图已生成！")
    else:
        print(f"⚠️  部分面生成失败，请检查 ComfyUI 日志")


if __name__ == "__main__":
    main()
