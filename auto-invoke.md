---
auto-invoke: false
description: >
  CIE 认知-自省-进化循环。默认关闭，输入以 "self" 开头时由 self-skill 触发。
---

<!-- ============================================================ -->
<!-- 🚫 CIE CYCLE — 默认不启用                                        -->
<!-- ============================================================ -->
<!--                                                              -->
<!-- 如需启用，在 prompt 中输入"用 CIE"或"run CIE"即可。              -->
<!-- 完整 CIE 循环为 5 步：                                         -->
<!--   1. 认知层    → cognitive-layer.sh --json                     -->
<!--   2. 意图解析  → Agent(schema=INTENT_SCHEMA)                   -->
<!--   3. 执行      → 按 intent_type 走对应工具链                   -->
<!--   4. 自省      → introspect.sh save --micro/--meso/--macro     -->
<!--   5. 进化      → self.sh think/absorb (有条件执行)             -->
<!--                                                              -->
<!-- ============================================================ -->

<!-- 以下是完整的 CIE 模板，启用时取消注释即可使用： -->

<!--
> **【认知-自省-进化循环 / CIE Cycle — 必须执行，不可跳过】**
>
> **第一步：判断输入字符数（含标点），严格按此规则执行：**
>
> ┌──────────────────────────────────────────────────────────────┐
> │ 输入字符数 < 10 → 轻量模式                                   │
> │   直接回应用户，不做任何事：                                 │
> │   ✗ 不运行认知层脚本                                       │
> │   ✗ 不做意图解析（不调 Agent）                               │
> │   ✗ 不自省（不调 introspect.sh）                             │
> │   ✗ 不进化（不调 self.sh）                                   │
> │   ✗ 不进行任何工具调用                                      │
> │   只输出文字回应，结束本轮                                  │
> └──────────────────────────────────────────────────────────────┘
> ┌──────────────────────────────────────────────────────────────┐
> │ 输入字符数 ≥ 10 → 标准模式                                   │
> │   严格按以下 5 步执行，不得跳过任何一步：                    │
> └──────────────────────────────────────────────────────────────┘
>
> ---
>
> ### 1️⃣ 认知层（必须执行）
> ```bash
> bash /home/ubuntu/.claude/skills/self-skill/scripts/cognitive-layer.sh --json
> ```
> 输出: 时间 + 会话 + identity.md 状态 + §六计数 + introspection.carryover
>
> ### 2️⃣ 意图解析（必须 Agent 工具调用，带 schema）
> ```json
> { "type": "object", "properties": {
>   "intent_type":        { "type": "string", "enum": ["greeting","conceptual","methodological","creative","analytical","meta","feedback","correction","directive"] },
>   "needs_introspection": { "type": "boolean" },
>   "introspection_depth": { "type": "string", "enum": ["quick","deep","milestone"] },
>   "needs_evolution":     { "type": "boolean" },
>   "evolution_type":      { "type": "string", "enum": ["collection","refinement","restructure",""] },
>   "core_question":       { "type": "string" },
>   "response_strategy":   { "type": "string" },
>   "predicted_tool_chain": { "type": "array", "items": { "type": "string" } },
>   "fallback_strategy":   { "type": "string" },
>   "key_signals":         { "type": "array", "items": { "type": "string" } }
> }, "required": ["intent_type","needs_introspection","needs_evolution","core_question","response_strategy","predicted_tool_chain"] }
> ```
>
> ### 3️⃣ 执行
> | intent_type | 工具链 |
> |-------------|--------|
> | greeting | 直接回（此分支已由字符判断拦截，理论上不会出现） |
> | conceptual | WebSearch → Read → 整合 |
> | methodological | 拆子步骤 → 按序调用 → 验证 |
> | creative | 设计 → 分步实现 → 测试 |
> | analytical | 收集证据 → 因果分析 → 结论 |
> | meta | 读自身文件/配置 → 解释 |
> | feedback/correction | 记录 → 采集 → 应用 |
> | directive | 按指令执行 |
>
> ### 4️⃣ 自省（必须执行）
> 三层次审视本轮工具轨迹：
> - **微观**：实际工具链 vs predicted_tool_chain → 顺序/冗余/遗漏
> - **中观**：intent_type 判断是否准确、策略是否最优
> - **宏观**：跨轮是否存在系统性的模式偏差
>
> ```bash
> bash /home/ubuntu/.claude/skills/self-skill/scripts/introspect.sh save --micro "<轨迹发现>" --meso "<校准发现>" --macro "<模式偏差>" --harvest
> ```
>
> ### 5️⃣ 进化（有条件执行）
> - **用户表达偏好/习惯/反馈** → `self.sh think/absorb --from <源>`
> - **自省发现宏观偏差** → 上一步 `--harvest` 已自动采集
>
> ---
> > **不自省等于本轮没完成。不进化等于本轮没生长。这是硬约束，不是建议。**
-->