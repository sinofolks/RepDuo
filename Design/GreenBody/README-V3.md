# Green Body V3.1 — 按固定评分协议迭代的 Blender 模型

2026-09-13。本轮只修改 `Design/GreenBody` 内的真实模型、建模脚本和测量证据；没有改动 iOS 工程，没有使用生成图片替代 Blender 渲染。

## 当前查看版本

- `GreenBody-v3.1.blend`：本轮选定的可编辑模型，来自 `renders/v3-experiments/merged-e.blend` 的原样副本。
- `renders/v3.1/hero.png`、`front.png`、`side.png`、`back.png`、`head.png`：真实 Cycles CPU 多视角渲染。
- `renders/v3.1/poses/`：实际最终文件的深蹲、俯卧撑静态检查；不是正式动画。
- `calibration/report.html`：本地离线评分、叠图和历史；也可通过 `http://127.0.0.1:8766/report.html` 打开。
- `v3.1-parameters.json`：保留本轮实际几何和站姿参数，便于继续迭代。
- `validation-v3.1.json`：最终模型的只读结构检查。

V1、V2、V3 文件均保留。V3 是中间候选，**不是本轮推荐打开的最终版本**；它的躯干高度带触发了退步警戒线，随后通过手臂微调形成 V3.1。

## 实测结果与选择理由

固定协议 `a27899fbaaab3a81843483895ebc7f9e27e151740b8476f89b2362f8e0765d1f`，参考锁 `references/v3`。这里的参考 v3 指标注版本，不是模型版本。

| 模型 | 单视角匹配指数 | 相对 V2 | 判断 |
| --- | ---: | ---: | --- |
| V2 | 57.210 | — | 本轮基线 |
| V3 | 65.448 | +8.238 | 躯干高度带下降 3.565 分，继续修正 |
| V3.1 | 66.267 | +9.057 | 对 V2 无高度带下降超过 3 分，保留供人工审阅 |

V3.1 相对 V2：六项总指标均提高；头部/肩部/躯干/髋部/脚部高度带改善，大腿高度带下降 1.823 分、小腿下降 0.600 分。**不是每一处都更好**。高度带包括横穿其中的手臂、手掌，并非语义人体部位分割。

V3.1 相对中间 V3 只提高 0.819 分，低于约 0.986 分的遮罩敏感性幅度，所以工具仍可能对这一小步给出 `hold_for_review`；不把这一小差值称为显著进步。本轮有力的比较是同一协议下的 **V2 → V3.1，+9.057 分**，且侧、背面人工检查未见新增明显破面或塌陷。

相机、灯光、固定材质、参考遮罩、评分权重、评分代码均未改变。身体只做实际网格修形和骨骼姿态调整；没有改变相机来凑分、拉伸渲染图或修改参考图。采集后依然只允许原协议中的等比缩放和平移。

## 实际修改

1. 头部右转约 20°，将侧倾分配到脊柱与颈部，改变过于对称僵直的站姿；没有任意移动独立头部或放大颅骨。
2. 重新平顺前后颈横截面，削弱原有领圈/凹凸；用连续简化面替代眼窝和鼻部的融化感起伏，保留浅鼻和下颌。
3. 胸部使用最大约 6 mm 的局部平顺，保留肩腋轮廓；上臂肌腹轻微径向增厚并调整双臂角度。
4. 小腿肌腹径向增厚、前脚掌横向展开、脚背抬高；不改变骨长，不把脚底压扁。最大实际下肢顶点位移约 6.91 mm。
5. 调整膝踝方向及脚部外转，依据最终变形网格检查实际地面接触，足底间隙约 0.50–0.59 mm。

网格仍为 13,024 顶点、12,999 面的单一封闭连通网格，骨骼和蒙皮权重保留。材质仍是原固定棚拍外观。

## 已知不足

- 单视角指数 **不是 3D 还原百分比，更不是 99% 或 1:1 完成证明**。参考关节标注仍是带不确定性的人工估计。
- 脚掌仍偏窄扁、脚趾细碎，拇指张开略机械；脸/耳廓和鼻颌轮廓仍比参考软。
- 后脑存在轻微横向明暗变化；下腹/髋部形体还不够简洁。
- 深蹲近侧膝盖有局部尖锐褶皱，肩腋变形尚粗；俯卧撑脚趾滚动支撑未完成。静态姿势检查不等于运动动画、实时跟随或生物力学验收。
- 不接入 App，不承诺移动端性能；沿用 MakeHuman CC0 图形资产来源，详见原 `README.md`。

下一轮宜先修脚掌/拇指，再处理头耳的清晰轮廓及动作中的膝腋褶皱；继续用本协议比较站立视图，同时人工查看多视角，不能只追总分。

## 复现与继续迭代

以下命令从 RepDuo 工程根目录执行。建模和输出脚本拒绝覆盖已有文件/目标。选一个新的输出路径；不要直接覆盖 V3.1。

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 --python Design/GreenBody/scripts/build_green_body_v3.py -- --out Design/GreenBody/GreenBody-next.blend --stance --params Design/GreenBody/v3.1-parameters.json

python3 Design/GreenBody/calibration/calibrate.py run --blend Design/GreenBody/GreenBody-next.blend --label next

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup Design/GreenBody/GreenBody-next.blend --python-exit-code 1 --python Design/GreenBody/scripts/render_review_v3.py -- --out Design/GreenBody/renders/next

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python-exit-code 1 --python Design/GreenBody/scripts/review_poses_v3.py -- --blend Design/GreenBody/GreenBody-next.blend --out Design/GreenBody/renders/next/poses

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup Design/GreenBody/GreenBody-next.blend --python-exit-code 1 --python Design/GreenBody/scripts/validate_green_body_v3.py -- --out Design/GreenBody/validation-next.json
```

实际试验过程和被弃方案保留在 `renders/v3-experiments`、`v3-head-experiments`、`v3-stance-experiments`、`v3-lower-experiments`，各自有真实采集和独立测量记录；没有把未采用的试验计作成果。
