---
name: dls-telemetry
description: 维护 DataLayer Studio 的 FIT/GPX 解析、TelemetrySeries、墙钟时间轴、暂停保持、距离/速度插值和起跑、结尾、运动恢复配速平滑。修改 Sources/OverlayCore/FIT、Sources/OverlayCore/Telemetry、相关测试，或排查配速尖峰、尾段异常、距离补账、分段锚点、暂停恢复与自动对表数据问题时使用。
---

# DataLayer Studio 遥测

## 开始前

1. 完整阅读待改函数、所有调用者和相邻测试；优先在共享解析或序列管线修根因。
2. 涉及起跑、结尾或停顿恢复时，完整阅读 `docs/algorithms/startup-pace-catchup-smoothing.md` 和 `docs/algorithms/motion-resumption-pace-smoothing.md` 的相关章节。
3. 把 FIT/GPX 当不可信输入；不提交真实运动文件，不在日志或回复中暴露路径、GPS、设备标识或完整遥测。

## 不变量

- `OverlayCore` 不依赖 SwiftUI；解析与插值保持平台中立。
- 运动暂停使用墙钟时间轴，暂停区间保持最后有效值；不要退回只按 active duration 映射。
- 纠正算法必须有多重数据证据、保守回退并可幂等重建；设备数据自洽后保持原值。
- 分段/会话锚点与记录近乎同刻时合并，避免插入亚秒样本制造段速尖峰。
- 距离补速保留最小时间窗；不要加全局速度上限误伤骑行、滑雪等合法高速。
- 最终样本与分段累计必须受时长、合理速度及会话总距离守卫；有位移证据的尾段不能按字段缺失整段裁掉。
- 修改距离、速度、步频或锚点时，同时检查起跑、活动结尾、lap 边界、静止、恢复、合法高速和重复初始化。

## 最小验证

先跑：

```bash
swift test --filter FITParserTests
swift test --filter TelemetrySeriesTests
```

非平凡规则补一个能锁住根因的合成测试。需要真实素材差分时只在 `assets/resourses/` 本地验证目标窗口、全程变化数和 lap 边界，不提交素材或完整输出。
