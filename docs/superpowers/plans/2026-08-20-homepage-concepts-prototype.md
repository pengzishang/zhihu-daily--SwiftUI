# 日报首页三方案 HTML 原型 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付一个本地可打开的 HTML 页面，以相同示例文章比较三种日报首页信息结构。

**Architecture:** 原型由一个 HTML 页面和一个 CSS 令牌文件组成。HTML 承担语义结构、方案切换和本地主题偏好；CSS 集中定义从 DailyReader 设计系统映射而来的色彩、字体、间距、动效与响应式规则。

**Tech Stack:** 静态 HTML、CSS custom properties、无依赖浏览器原生 JavaScript。

## Global Constraints

- 仅创建 `docs/superpowers/` 和 `outputs/` 下的新文件。
- 使用现有设计系统的暖纸、浓墨、靛蓝、朱砂、宋体与髮丝线。
- 不加载网络资源，不伪造文章指标或人物评价，不模拟浏览器或手机外壳。
- 对 320px、375px、414px、768px 保持无横向滚动与可操作焦点。

---

### Task 1: 记录已确认的原型设计

**Files:**
- Create: `docs/superpowers/specs/2026-08-20-homepage-concepts-design.md`

**Interfaces:**
- Consumes: 用户已确认的扫描任务、碎片时间读者、编辑化气质。
- Produces: 三套原型的内容优先级与非目标约束。

- [ ] **Step 1: 写入设计决策**

记录 A“今日目录”、B“头版 + 全览”、C“主题分版”的结构、取舍及共同设计语言。

- [ ] **Step 2: 审查范围**

确认规格不要求修改 `DailyReader/`、不涉及数据排序或服务端。

### Task 2: 定义原型令牌

**Files:**
- Create: `outputs/首页三套方案-tokens.css`

**Interfaces:**
- Consumes: `docs/design/design-system.md` 的色彩、字体、间距与动效规则。
- Produces: `--color-*`、`--font-*`、`--space-*`、`--dur-*`、`--ease-*` 令牌。

- [ ] **Step 1: 声明深浅主题令牌**

为暖纸、纸面、浓墨、淡墨、靛蓝、朱砂和髮丝线建立对应的 OKLCH 令牌；深色模式映射为“夜里的墨纸”。

- [ ] **Step 2: 声明排版和响应式令牌**

声明宋体/系统黑体角色、4pt 间距阶梯、动画时长与 `prefers-reduced-motion` 回退。

### Task 3: 构建三方案互动设计稿

**Files:**
- Create: `outputs/首页三套方案-互动设计稿.html`
- Uses: `outputs/首页三套方案-tokens.css`

**Interfaces:**
- Consumes: 令牌文件和固定的示例文章数组。
- Produces: 方案选择、浅深色切换及三种首页布局。

- [ ] **Step 1: 写入语义化页面骨架**

使用 `<header>`、`<main>`、`<section>`、`<nav>` 和 `<button>`；方案按钮使用 `aria-pressed`，主题按钮使用可读标签。

- [ ] **Step 2: 实现 A“今日目录”**

渲染紧凑刊头、三条“先看”和连续标题目录，突出标题与已读状态。

- [ ] **Step 3: 实现 B“头版 + 全览”**

渲染低高度的抽象纸面头版和同一组文章目录；不使用伪造摄影内容。

- [ ] **Step 4: 实现 C“主题分版”**

渲染精简主题版面和完整目录，显式说明类别仅是原型信息组织，不代表已验证推荐。

- [ ] **Step 5: 实现本地交互**

用浏览器原生 JavaScript 切换 `data-layout` 与 `data-theme`，将选择保存在 `localStorage`，并在键盘操作时保持焦点与 ARIA 状态一致。

### Task 4: 验证原型

**Files:**
- Verify: `outputs/首页三套方案-互动设计稿.html`
- Verify: `outputs/首页三套方案-tokens.css`

**Interfaces:**
- Consumes: 静态文件。
- Produces: 结构校验、可访问性基本检查与多宽度截图证据。

- [ ] **Step 1: 校验 HTML**

运行 `tidy -qe outputs/首页三套方案-互动设计稿.html`；允许 HTML5 自定义属性相关的非致命提示，但不允许标签未闭合或脚本语法问题。

- [ ] **Step 2: 校验引用与交互代码**

运行 Node 读取页面，确认令牌 CSS 引用、三套布局标识、主题切换与方案切换函数均存在。

- [ ] **Step 3: 手工浏览验证**

在 320px、375px、414px、768px 宽度打开页面，依次切换 A/B/C 与浅深色，确认无横向滚动、按钮可见且内容不重叠。
