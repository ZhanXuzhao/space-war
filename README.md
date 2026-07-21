# SpaceWar 🚀

**一款 Godot 4 引擎驱动的 EVE 风格单机太空战斗游戏**

> A single-player EVE Online-inspired space combat game built with Godot 4.

---

## 游戏简介 | Overview

SpaceWar 是一款以太空为背景的实时战斗模拟游戏，灵感来源于《EVE Online》的舰船战斗与装备系统。玩家可以操控不同级别的飞船，在深邃的星空中与 NPC 敌人交战、管理护盾/装甲/结构、安装模块与武器，体验太空作战的丰富策略。

Built with **Godot 4.7** (Forward+ renderer), SpaceWar delivers EVE-like ship combat mechanics including layered damage resistance, capacitor management, target locking, active modules, and full 3D space flight.

---

## 特性 | Features

### 🛸 飞船系统 | Ship System
- **三种船型**：护卫舰 (Frigate)、巡洋舰 (Cruiser)、战列舰 (Battleship)
- 每艘飞船拥有独立的护盾、装甲、结构、电容、速度、质量等属性
- 支持动态更换飞船（游戏中无缝切换）

### ⚔️ 战斗系统 | Combat System
- **多层防御**：护盾 → 装甲 → 结构，每层对四种伤害类型（电磁/爆炸/动能/热能）拥有不同抗性
- **武器多样性**：激光 (Laser)、投射物 (Projectile)、导弹 (Missile)、混合武器 (Hybrid)
- **目标锁定**：多目标锁定系统，支持自动锁定与攻击
- **环绕 & 接近**：可命令飞船环绕目标或直线接近

### 🔧 模块系统 | Module System
- **高槽/中槽/低槽**：仿 EVE 的槽位系统
- **模块类型**：护盾回充器、装甲修复器、结构维修器、电容回充器、加力燃烧器
- 模块可独立安装、激活、停用，消耗电容以产生效果

### 🤖 AI 系统 | AI System
- NPC 飞船拥有完整的 AI 行为状态机：巡逻 (Patrol) → 接战 (Engage) → 逃跑 (Flee)
- AI 行为根据船型自动调整探测范围、接战距离、环绕半径
- 敌对 NPC 主动攻击玩家

### 🎮 操控方式 | Controls
- **鼠标拖拽旋转视角**
- **滚轮缩放**（支持超远距/超近距观察）
- **跃迁引擎**：快速跨区域移动
- **环绕/接近/攻击指令**：右键菜单操作

### 🖥️ HUD / UI
- EVE 风格界面：护盾/装甲/结构/电容进度条
- 全景扫描列表 (Overview)
- 目标锁定卡片系统
- 装备面板：实时显示已安装模块状态
- 可拖拽面板窗口

### 💥 特效 | Visual Effects
- **导弹尾焰**（可开关）
- **爆炸特效**（核心火球 + 碎片飞溅 + 冲击波 + 闪光，四种大小预设）
- **激光光束**：红色热能 / 金色导弹 / 蓝色动能 / 紫色混合
- **LOD 系统**：远距离自动切换为 2D 图标，优化性能

---

## 项目结构 | Project Structure

```
space-war/
├── autoload/              # 全局自动加载脚本
│   └── Global.gd          # 全局游戏状态管理（经济、货舱、飞船数据）
├── resources/             # 数据资源
│   ├── game_config.cfg    # 游戏配置文件（维修量、LOD等）
│   ├── ship_data/         # 飞船数据定义 (ShipData.gd)
│   ├── weapon_data/       # 武器数据定义 (WeaponData.gd)
│   └── module_data/       # 模块数据定义 (ModuleData.gd)
├── scenes/                # 场景文件
│   ├── main.tscn          # 主场景入口
│   ├── ships/             # 飞船场景 (Frigate/Cruiser/Battleship)
│   ├── weapons/           # 武器场景 (Missile/Projectile)
│   ├── world/             # 世界场景 (Asteroid/StarSystem/Station)
│   ├── effects/           # 特效场景 (Explosion)
│   └── ui/                # UI场景 (HUD, WeaponCard, LockedTargetCard)
├── scripts/               # 游戏脚本
│   ├── Main.gd            # 主场景逻辑
│   ├── ships/Ship.gd      # 飞船基类
│   ├── controllers/       # 玩家控制器 (PlayerController)
│   ├── ai/                # AI控制器 (AIController)
│   ├── combat/            # 战斗系统 (Weapon/DamageSystem/Missile/Projectile)
│   ├── modules/           # 模块实现 (ShieldBooster/ArmorRepairer/等)
│   ├── ui/                # UI脚本 (HUD/DraggablePanel/等)
│   └── effects/           # 特效脚本 (Explosion)
├── shaders/               # 着色器
│   └── sky_cubemap.gdshader # 天空盒立方体贴图着色器
├── models/                # 3D模型 (.glb)
├── images/                # 图标纹理
├── textures/skybox/       # 天空盒纹理
└── image_gen/             # 天空盒生成工具 (Python)
```

---

## 快速开始 | Getting Started

### 环境要求 | Prerequisites

- **Godot 4.7+**（建议使用 .NET 版本 / .NET version recommended）
- 操作系统：Windows / Linux / macOS

### 运行 | Run

1. 克隆或下载本仓库
2. 使用 Godot 4.7 打开项目根目录
3. 点击 **运行 (F5)** 即可启动

```bash
git clone https://github.com/your-repo/space-war.git
# 用 Godot 打开 space-war/ 目录
```

### 构建 | Build

在 Godot Editor 中：
- **项目 → 导出** → 选择目标平台 → 导出

---

## 配置 | Configuration

核心配置位于 `resources/game_config.cfg`，包含：

| 配置段 | 说明 |
|--------|------|
| `[repair]` | 护盾/装甲/结构修复器的基础修复量 |
| `[tactical_grid]` | 战术网格标签字体大小 |
| `[lod]` | LOD 距离倍数（模型→图标切换阈值） |

---

## 开发 | Development

- 飞船属性通过 `ShipData` 资源类定义，使用静态工厂方法创建预设
- 武器属性通过 `WeaponData` 资源类定义，支持四种武器类型
- 模块属性通过 `ModuleData` 资源类定义
- 伤害抗性系统位于 `DamageSystem.gd`，支持自定义抗性配置
- AI 行为在 `AIController.gd` 中定义，通过状态机驱动

### 添加新船型

```gdscript
# 在 ShipData.ShipClass 枚举中添加新类型
# 实现对应的 create_xxx() 工厂方法
# 创建飞船场景并添加到 PLAYER_SHIP_SCENES 映射
```

### 添加新武器

```gdscript
# 在 WeaponData 中配置属性
# 将 WeaponData 资源赋值给飞船上的 Weapon 节点
```

---

## 技术栈 | Tech Stack

- **Godot 4.7** — 游戏引擎 (Forward+ 渲染器)
- **GDScript** — 脚本语言
- **GLB/GLTF** — 3D 模型格式
- **SVG/PNG** — 图标与纹理
- **Python** — 天空盒生成工具

---

## 许可 | License

[MIT](LICENSE)

---

## 致谢 | Credits

- 灵感来源于 CCP Games 的 **EVE Online**（非商业同人项目）
- 使用 **Godot Engine** 开发

---

> **注意**：本项目为个人学习与练习作品，不使用任何 EVE Online 受版权保护的资产。
