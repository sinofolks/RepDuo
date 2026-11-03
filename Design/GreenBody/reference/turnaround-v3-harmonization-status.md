# 程序化轮廓校正 V3b

用户已明确授权：“允许啊，快点吧”。这是参考图校正，不是模型渲染、模型修复或99%还原声明。

采用文件：`green-body-turnaround-v3b-harmonized.png`。原始 V1、两版生成失败候选、第一版程序映射 V3 均保留。V3 的逐行纹理接缝被拒绝；V3b 平滑位移场后已检查整图，接缝消除。背面的重采样、边缘与局部明暗仍是人为校正的参考素材，不是独立观察数据。

- 原图正面和侧面逐像素保持不变；尺寸与标签不变。
- 背面外轮廓及肢体空隙由原正面镜像确定，原像素遮罩和标准化遮罩重合度均为100%；未通过额外平移搜索获得。
- 背面材质明暗仅来自原图背面，用平滑位移场重新映射；清理背面区域遗留背景边缘。未使用当前 Blender 模型作为参考。
- 原图及旧配置、评分、模型不变。侧面仍保留原图，未宣称三视图已完全符合某个真实三维体。
- 精确日志与哈希见同名 `.json`；可复现程序为 `../calibration/harmonize_turnaround.py`，使用 `--smooth` 与新的 `--out` 路径，拒绝覆盖。

新参考单独锁定在 `../calibration/multiview-reference-v3/`。它继承已获批准的角色设计，记录额外的程序校正授权；未冒充用户对完成图片的再次视觉验收。背面关节坐标由正面镜像推定，保持 provisional 状态。

V10 旧有真实渲染经哈希验证后重新评分，未重新渲染、未修改模型：正面71.39742 / 侧面75.48392 / 背面71.36999，平均72.75045，最低71.36999。前两项与原协议数值一致。新旧协议不能直接相减作为模型进步。新报告为 `../calibration/multiview-reference-v3/report.html`。

下一次真实模型修改，使用相同新协议：

```sh
python3 Design/GreenBody/calibration/multiview_run.py --blend /absolute/path/new-model.blend --label NEW_LABEL --out /absolute/path/new-capture-dir --pose-version v2 --reference-version v3
```

99目标仍未达到。轮廓参考已校正，不代表模型已修好。
