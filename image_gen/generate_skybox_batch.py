"""
批量生成 4 张不同风格的全景天空盒图片
- 每张图片四周边界留黑（使用 PIL 添加黑边）
- 读取 Skybox.json (ComfyUI API workflow)
- 分别设置不同的提示词和种子
- 发送到 ComfyUI (localhost:8188)
- 等待生成完成
- 添加黑边后保存到 textures/skybox/

用法:
  python generate_skybox_batch.py              # 随机种子
  python generate_skybox_batch.py --seed 123   # 指定基础种子（每张 seed 自动 +1）
"""

import json
import os
import random
import sys
import time
import urllib.request
import urllib.error

try:
    from PIL import Image, ImageOps
except ImportError:
    print("❌ 需要安装 Pillow: pip install Pillow")
    sys.exit(1)

COMFYUI_URL = "http://127.0.0.1:8188"
WORKFLOW_PATH = os.path.join(os.path.dirname(__file__), "Skybox.json")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "textures", "skybox")

# KSampler 和 CLIP 文本编码节点的 ID
KSAMPLER_NODE_ID = "72:70"
CLIP_ENCODE_NODE_ID = "72:67"

# 4 种不同的天空盒风格定义
SKYBOX_STYLES = [
    {
        "name": "purple_nebula",
        "prompt": (
            "equirectangular panorama space skybox, top edge pure black, bottom edge pure black, "
            "left edge black border, right edge black border, four sides black border frame, "
            "center band with vibrant purple and blue nebula, bright stars scattered across the middle, "
            "Milky Way galaxy, cosmic dust, seamless horizontal wrap, photorealistic, high detail"
        ),
    },
    {
        "name": "red_flame",
        "prompt": (
            "equirectangular panorama space skybox, all four edges black border frame, "
            "top black, bottom black, left black, right black, "
            "center area with fiery red and orange emission nebula, glowing hydrogen clouds, "
            "bright stars scattered, dark space, seamless 360 panorama, photorealistic, high detail"
        ),
    },
    {
        "name": "blue_galaxy",
        "prompt": (
            "equirectangular deep space panorama, four edges black border margin, "
            "top edge black, bottom edge black, left edge black, right edge black, "
            "center horizontal band with blue and cyan nebula, dense starfield, "
            "bright core of the Milky Way, interstellar dust, seamless 360 wrapping, photorealistic, high detail"
        ),
    },
    {
        "name": "green_aurora",
        "prompt": (
            "equirectangular space skybox panorama, black border on all four edges, "
            "top and bottom fully black, left and right black margins, "
            "center band with green and teal aurora-like nebula, glowing cosmic gas, "
            "scattered bright stars, dark void around edges, seamless 360 panorama, photorealistic, high detail"
        ),
    },
]

BORDER_WIDTH = 32  # 黑边宽度（像素）


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


def add_black_borders(image_path: str, border: int):
    """给图片四边添加黑边"""
    img = Image.open(image_path)
    # 使用 PIL 的 expand 方法添加黑色边框
    img_with_border = ImageOps.expand(img, border=border, fill=(0, 0, 0))
    img_with_border.save(image_path)
    print(f"   🖼️ 已添加 {border}px 黑边")


def main():
    # 解析命令行参数
    base_seed = random.randint(0, 2**63 - 1)
    if "--seed" in sys.argv:
        idx = sys.argv.index("--seed")
        if idx + 1 < len(sys.argv):
            base_seed = int(sys.argv[idx + 1])

    print("=" * 60)
    print("🚀 批量生成 4 张不同风格的全景天空盒")
    print(f"🎲 基础种子: {base_seed}")
    print("=" * 60)

    # 读取工作流模板
    print(f"📖 读取工作流: {WORKFLOW_PATH}")
    with open(WORKFLOW_PATH, "r", encoding="utf-8") as f:
        workflow_template = json.load(f)

    # 确保输出目录存在
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for i, style in enumerate(SKYBOX_STYLES):
        name = style["name"]
        prompt_text = style["prompt"]
        seed = base_seed + i

        print(f"\n{'─' * 50}")
        print(f"[{i + 1}/4] 生成: {name}")
        print(f"   🎲 种子: {seed}")
        print(f"   📝 提示词: {prompt_text[:80]}...")

        # 深拷贝工作流
        workflow = json.loads(json.dumps(workflow_template))

        # 设置提示词
        if CLIP_ENCODE_NODE_ID in workflow:
            workflow[CLIP_ENCODE_NODE_ID]["inputs"]["text"] = prompt_text

        # 设置种子
        if KSAMPLER_NODE_ID in workflow:
            workflow[KSAMPLER_NODE_ID]["inputs"]["seed"] = seed

        # 发送到 ComfyUI
        print(f"   🚀 发送到 ComfyUI...")
        prompt_id = queue_prompt(workflow)
        print(f"      Prompt ID: {prompt_id}")

        # 轮询等待完成
        print(f"   ⏳ 等待生成中...", end="", flush=True)
        while True:
            history = get_history(prompt_id)
            if history:
                print()
                print(f"   ✅ 生成完成！")
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
            print(f"   ❌ 未找到输出图片")
            continue

        filename = image_info["filename"]
        subfolder = image_info["subfolder"]
        folder_type = image_info["type"]

        print(f"   📷 下载图片: {filename}")

        # 下载图片
        img_data = download_image(filename, subfolder, folder_type)

        # 保存原始图片（临时路径）
        output_filename = f"space_panorama_{name}.png"
        output_path = os.path.join(OUTPUT_DIR, output_filename)
        with open(output_path, "wb") as f:
            f.write(img_data)
        print(f"   💾 已保存: {output_filename} ({len(img_data) / 1024:.0f} KB)")

        # 添加黑边
        add_black_borders(output_path, BORDER_WIDTH)

    print(f"\n{'=' * 60}")
    print("✅ 全部生成完毕！")
    print(f"📁 图片保存在: {OUTPUT_DIR}")
    print("=" * 60)


if __name__ == "__main__":
    main()
