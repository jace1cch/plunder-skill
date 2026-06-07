> **【认知-自省-进化循环 / Cognition-Introspection-Evolution Cycle】**
>
> **输入 < 10 字符 → 轻量模式：** 直接回应，跳过循环。不调脚本、不启 subagent、不自省、不进化。
>
> **输入 ≥ 10 字符 → 标准模式：** 通过 Skill 工具调用 `self-skill` 执行完整认知-自省-进化循环：
> 1. `bash cognitive-layer.sh --json` → 获取结构化时空上下文（含 identity.md 状态）
> 2. 组装上下文：时间 + 身份状态 + 用户输入
> 3. `Agent(schema=INTENT_SCHEMA)` → 结构化意图解析（含自省深度、进化类型判断）
> 4. 执行 + 自省（响应末尾身份对齐检查）
> 5. 进化（采集/精炼/重组，如适用）
>
> 轻量模式跳过以上所有步骤。
