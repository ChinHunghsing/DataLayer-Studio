@AGENTS.md

## 技能（skills）

本项目在 `.claude/settings.json` 里停用了 87 个与本项目无关的用户级技能，只保留 Apple/Swift、App Store 发布、官网与文案、通用工程相关的 47 个，以节省上下文。项目内 `.agents/skills/dls-*` 不受影响。

**代价：被停用的技能不会被自动推荐。** 遇到看起来可能有现成技能的任务（发布流程、设计评审、内容审核、第三方接入等），先查一遍再动手：

    ls ~/.claude/skills
    grep -l -i "<关键词>" ~/.claude/skills/*/SKILL.md

需要某个被停用的技能时，把 `.claude/settings.json` 里对应条目改成 `"on"`，或用 `/skills` 界面开启。个人临时开启可写进优先级更高的 `.claude/settings.local.json`，不影响其他协作者。
