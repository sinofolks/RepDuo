# Green Body — Blender 外观阶段稿 v1

更新：当前评分驱动版本为 `GreenBody-v3.1.blend`，说明见 `README-V3.md`，评分见 `calibration/report.html`。V1、V2、V3 中间候选均保留；下文保留 v1 记录。

这是可编辑的真实 3D 模型及 Blender 渲染，不是以生成图片冒充建模结果。暂未接入 RepDuo iOS 工程，也未替换现有摄像头或训练功能。

## 查看

- `GreenBody-v1.blend`：主模型、基础骨骼、材质、灯光和四个相机。
- `renders/hero.png`：主视角实际渲染，1000 × 1200。
- `renders/front.png`、`side.png`、`back.png`：正面、侧面、背面实际渲染。
- `renders/pose-tests/`：下蹲、俯卧撑的静态测试图及各自可编辑 `.blend`，不是正式动作动画。
- `reference/green-body-concept.png`：原 AI 概念参考，不是建模成果。
- `validation.json`：针对保存文件的只读几何、权重及相机构图检查。

在 Blender 打开主文件后，可直接按 F12 渲染。默认视口隐藏辅助线，便于看外观；需要编辑骨骼时，重新开启右上角 Overlays，并在 Outliner 中选择 `GB_ReviewArmature`。

## 当前模型

使用 MakeHuman CC0 人体底模和骨骼数据，调整身高、身形及手臂姿态，并以连续四边面曲面重建了简化头部，包含浅鼻梁、下颌和一体式耳部轮廓。不是完全从零雕刻。

- 设计身高约 1.82 米，Z 轴向上，正面朝 -Y。
- 单一封闭连通人体网格；原始网格 12,224 顶点、12,199 面，其中 12,182 面为四边面。
- 163 根基础骨骼，其中 139 个骨骼组实际影响网格；所有顶点权重归一化。
- 两级细分用于展示，未把该高面数展示网格直接当作移动端优化版本。
- 非金属青柠绿材质、黑色摄影棚背景，无服装和 Logo。
- 文件内没有依赖外部纹理，几何、骨骼、材质和灯光都保存在 `.blend` 内。

## 还未完成的部分

这不是 1:1 复刻完成版。当前头部比参考更抽象，耳廓与浅层五官只有概括形体；体型更窄长，胸肩体积和材质明暗也仍有偏差。

基础骨骼存在不代表运动绑定验收完成。已制作下蹲与俯卧撑两个静态姿势测试，修正了俯卧撑脚趾悬空，但下蹲幅度仍比参考浅，手指支撑和背部线条也需要继续调整。完整运动中的肩腋窝、膝盖和臀部变形仍需要动画检查；摄像头动作跟随、运动计数、移动端性能及 App 集成都不在本阶段交付中。

`validation.json` 的 PASS 仅表示所列几何、权重、相机和文件检查通过，不代表没有任意姿势下的自交，也不代表艺术质量已经等同参考。

## 重建、渲染及检查

已在 Blender 5.2.1 LTS / Apple M1 上运行。以下命令从 RepDuo 工程根目录执行。重建会覆盖本目录的 `GreenBody-v1.blend`，手工修改模型前请先另存副本。所有脚本均在独立后台 Blender 中运行，不改变打开中的用户场景或 Blender 偏好设置。

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python Design/GreenBody/scripts/build_green_body.py -- --preview

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup Design/GreenBody/GreenBody-v1.blend --python Design/GreenBody/scripts/render_review.py

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup Design/GreenBody/GreenBody-v1.blend --python Design/GreenBody/scripts/validate_green_body.py

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python Design/GreenBody/scripts/review_poses.py
```

默认使用 Cycles CPU。四视图脚本使用 64 采样和去噪，只输出图片，不覆盖主模型。

## 资产来源

来源为 [MakeHuman 官方仓库](https://github.com/makehumancommunity/makehuman/tree/a8bc2d54ff0ac92e78ff71431b1023eda42bf482)，固定提交 `a8bc2d54ff0ac92e78ff71431b1023eda42bf482`。只使用人体、形态目标与骨骼数据，没有复制 MakeHuman 程序代码。

本地文件与上游路径：

| 本地 `source/` 文件 | 上游 `makehuman/data/` 路径 |
| --- | --- |
| `makehuman-base.obj` | `3dobjs/base.obj` |
| `default.mhskel` | `rigs/default.mhskel` |
| `default_weights.mhw` | `rigs/default_weights.mhw` |
| `adult-male.target` | `targets/macrodetails/caucasian-male-young.target` |
| `lean-tone.target` | `targets/macrodetails/universal-male-young-maxmuscle-minweight.target` |
| `ideal-proportions.target` | `targets/macrodetails/proportions/male-young-averagemuscle-averageweight-idealproportions.target` |
| `eye-left-closure.target`、`eye-right-closure.target` | `targets/expression/units/caucasian/` 下同名文件 |
| `nose-scale-depth-decr.target` | `targets/nose/nose-scale-depth-decr.target` |
| `mouth-upperlip-volume-decr.target`、`mouth-lowerlip-volume-decr.target` | `targets/mouth/` 下同名文件 |
| `l-ear-scale-decr.target`、`r-ear-scale-decr.target` | `targets/ears/` 下同名文件 |

上游资产标注为 CC0 1.0 Universal。原许可文本保存在 `source/MAKEHUMAN-LICENSE.md` 和 `source/LICENSE-ASSETS-CC0.md`，包括程序代码与图形资产的许可区分；下载文件的校验值保存在 `source-checksums.json`。脸部形态数据参与源网格预处理，最终可见头部已由本项目的新曲面替换。
