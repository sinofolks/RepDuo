# Green Body v2 — 参考还原迭代

新增：[可重复校准评分系统](calibration/README.md) · [离线叠图报告](calibration/report.html) · [测试记录](calibration/VERIFICATION.md)。评分是指定视角的工程指数，不是三维还原百分比。

2026-09-13，Blender 5.2.1 LTS。独立保存为 `GreenBody-v2.blend`，v1 模型与旧版渲染保留，未修改 iOS 工程。

## 本轮变化

- Hero 相机从正 X 改为负 X，脸朝向及可见耳侧与参考一致。
- 局部收窄肩腰，保留髋宽、腿长和脚踝间距；调整上胸体积，减轻圆形胸部鼓包。
- 头部稍加宽，重建连续的额头、浅鼻梁、简化眼眶、下颌和耳部轮廓；弱化过强眉眼，使用共享切线的插值及连续穹顶处理横向明暗接缝。
- 颈部连接局部平滑，不依靠分离球体或遮挡掩盖接缝。
- 两脚采用不同外转角，手掌略转向，收拢手指并轻微屈曲，替换原先平行双脚及过度张指。
- 重新调整青柠绿缎面材质、明暗与灯光关联：人物保留柔和高光，地板不接受灯具直射，仅保留间接绿色反射。
- 静态深蹲改为低髋姿态；俯卧撑检查手掌、拇指和脚趾的支撑高度。

## 查看成果

- `GreenBody-v2.blend`：中立姿态，包含模型、基础骨骼、灯光、材质及四个全身相机。
- `renders/v2/hero.png`：1000 × 1200 主视角真实渲染。
- `renders/v2/front.png`、`side.png`、`back.png`：全身三视图。
- `renders/v2/head.png`：1000 × 1000 头部真实近景。
- `renders/v2/comparison.png`：参考 / v1 / v2。仅按近似人物高度统一缩放和裁切，没有对模型渲染重绘或非均匀拉伸；参考一栏是原 AI 概念图。
- `renders/v2/poses/`：960 × 720 下蹲、俯卧撑真实渲染，附可编辑姿态 `.blend` 和检查报告。

## 验证与限制

中立模型检查通过：13,024 顶点、12,999 面，单一封闭连通网格，无非流形边、零面积面或未加权顶点；骨骼权重归一化，四机位完整容纳人物。检查报告为 `renders/v2/validation.json`，包括主文件校验值与只读检查前后一致性。

这不等同于“99% 还原”。参考只有概念图，没有可比较的背面与精确尺寸；本轮通过实际渲染逐项对照，不捏造整体相似度百分比。头颈形体、上臂肉量、耳廓和材质层次仍有可见差异。

深蹲的髋关节约低于膝 11 cm，膝内角约 53°；俯卧撑手脚支撑点接近同一地面。姿态报告中的距离仅验证当前静态网格的接地情况，不代表动作准确度、任意姿势下无自交或动画质量通过。关节压缩、掌面承重、背部线条和连续动作变形还未完成动画验收。

没有实现实时摄像头动作跟随、运动计数集成或移动端性能优化，也没有把高细分展示网格直接导入 App。

## 复现

从 RepDuo 工程根目录运行。重建会覆盖 v2 文件，手工编辑前先另存副本；不会覆盖 v1 或修改打开中的 Blender 场景。

```sh
/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python Design/GreenBody/scripts/build_green_body_v2.py -- --preview

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup Design/GreenBody/GreenBody-v2.blend --python Design/GreenBody/scripts/render_review_v2.py

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup Design/GreenBody/GreenBody-v2.blend --python Design/GreenBody/scripts/validate_green_body_v2.py

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python Design/GreenBody/scripts/review_poses_v2.py

/Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup --python Design/GreenBody/scripts/render_comparison_v2.py
```

基础数据继续使用原 MakeHuman CC0 底模与骨骼；具体上游提交、文件映射和许可见 `README.md` 与 `source-checksums.json`。本轮新增的造型、姿态和摄影棚逻辑在独立的 `*_v2.py` 脚本中。
