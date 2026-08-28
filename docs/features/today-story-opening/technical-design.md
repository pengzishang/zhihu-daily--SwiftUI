# 「今日故事开场」技术方案

## 0. 文档信息

| 项目 | 内容 |
| --- | --- |
| 功能 | 今日故事开场 |
| 平台 | iOS 17+ |
| 技术栈 | SwiftUI + Swift Concurrency + Kingfisher |
| 适用分支 | `version/2.1` |
| 关联 PRD | `docs/features/today-story-opening/product-requirements.md` |
| 当前状态 | 已完成源码实现并通过真实编译与单元测试；Xcode 27 Beta 下 38 个测试中 36 个通过，2 个既有测试失败（与本功能无关，详见测试说明） |

**实现目标：**在现有日报首页的滚动内容中恢复一条顶部故事开场，复用现有 `topStories` 和文章详情导航，不新增接口、不修改数据模型、不扩展文章详情功能。

---

## 1. 现状与技术判断

### 1.1 现有能力

当前项目已经具备实现所需的核心能力：

- `HomeViewModel` 已发布 `topStories: [TopStory]`。
- `TopStory` 已包含 `id`、`title`、可选 `image` 和可选 `url`。
- `HomeViewModel` 的 `apply(_:)` 会随着网络或缓存结果同步更新 `topStories`。
- `HomeView` 已在 `.loaded` 状态渲染日报分节列表，可在同一个 `ScrollView` 中插入开场区域。
- `TopStoriesView` 已证明顶部故事到 `ArticleDetailView` 的导航链路可复用，但它是横向多卡片布局，不满足本次单条开场需求。
- `TopStory.summary` 当前定义在 `TopStoriesView.swift` 的 `private extension` 中，只在该文件可见；新组件不能直接调用，需在组件内部映射，或单独将映射提升为非私有模型扩展。本方案优先采用组件内映射，避免扩大公共 API。
- `RemoteImageView` 已统一处理远程图片、Data URL、下采样、缓存、重试、加载失败和取消加载。
- `PlaceholderImageView` 已提供“日”字纸面占位图，可直接作为开场图片失败/缺失时的底层。
- `HomeInformationDensity` 已提供 `low / medium / high` 三档首页信息密度枚举。
- `DS` 已提供暖纸、纸面浮层、浓墨、淡墨、靛蓝、朱砂、宋体和文武线组件。

### 1.2 关键判断

本功能不需要新增 `HomeViewModel` 状态。开场是否显示由现有 `topStories.first` 派生即可：

```swift
private var openingStory: TopStory? {
    viewModel.topStories.first
}
```

不建议把“是否展示开场”写入 `@Published` 或 `UserDefaults`，原因是：

1. 它不是用户配置，而是当前接口数据的呈现结果。
2. 这样可以避免刷新、缓存和历史分页之间出现第二份状态。
3. `topStories` 为空时自然折叠，不需要额外空态分支。

---

## 2. 实现范围

### 2.1 本次实现

1. 新增一个首页局部组件 `TodayStoryOpeningView`。
2. 在 `HomeView.storyFeed` 中，将它插入第一个 `Section` 之前。
3. 只取 `topStories.first`，展示：
   - 固定标签“今日故事”；
   - `TopStory.image` 主图；
   - `TopStory.title` 标题。
4. 整个开场组件使用一个 `NavigationLink`，点击后进入现有：

```swift
ArticleDetailView(
    story: openingStory.summary,
    homeViewModel: viewModel,
    source: .daily,
    date: ""
)
```

5. 开场图片使用 `RemoteImageView` 或组合后的纸面占位底层。
6. 根据 `HomeInformationDensity` 调整开场高度和标题行数，不改变内容和交互。
7. 增加单元测试与 UI 测试覆盖正常、空数据、导航和密度适配。

### 2.2 明确不实现

- 不修改 `TopStory`、`DailyResponse`、`HomeFeedSnapshot`、缓存编码和接口。
- 不在 `HomeViewModel` 增加新加载任务或单独请求详情图片。
- 不新增轮播、分页圆点、进度条、声音、视频、Toast 或额外按钮。
- 不新增作者、摘要、日期、阅读时长等字段。
- 不修改 `ArticleDetailView`、收藏、已读、AI 或正文渲染。
- 不修改底部 Tab、历史分页、下拉刷新和“不感兴趣”手势。
- 不为开场单独设计一套深色品牌皮肤；遵循 `DS` 动态颜色。

---

## 3. 文件拆分

### 3.1 新增文件

```text
DailyReader/Features/Home/TodayStoryOpeningView.swift
DailyReaderTests/TodayStoryOpeningTests.swift
```

如项目对首页组件已有集中目录，也可以将组件放入现有 `DailyReader/Features/Home/`，不新建子目录，避免目录层级膨胀。

### 3.2 修改文件

```text
DailyReader/Features/Home/HomeView.swift
DailyReaderUITests/HomeFlowUITests.swift
```

预计不修改：

```text
DailyReader/Models/TopStory.swift
DailyReader/Features/Home/HomeViewModel.swift
DailyReader/Shared/Images/RemoteImageView.swift
DailyReader/Shared/UI/PlaceholderImageView.swift
DailyReader/Shared/UI/Theme.swift
project.yml
```

原因是数据、图片加载、占位和设计令牌均已存在。

---

## 4. 组件设计

## 4.1 `TodayStoryOpeningView`

建议接口：

```swift
struct TodayStoryOpeningView: View {
    let story: TopStory
    let density: HomeInformationDensity
    @ObservedObject var homeViewModel: HomeViewModel

    var body: some View { ... }
}
```

如果希望组件更容易做纯 UI 测试，可进一步把导航目标外置：

```swift
struct TodayStoryOpeningView<Destination: View>: View {
    let story: TopStory
    let density: HomeInformationDensity
    @ViewBuilder let destination: () -> Destination
}
```

首版建议采用第一种写法，与现有 `TopStoriesView` 保持一致，减少抽象层。

### 4.2 视觉层级

组件从底到顶：

1. `RoundedRectangle` 纸面/图片容器。
2. 图片占位底：`PlaceholderImageView` 的同源纸面逻辑，或者直接使用 `DS.paperElevated + Text("日")`。
3. `RemoteImageView`：
   - `targetSize` 按容器尺寸传入；
   - `contentMode: .fill`；
   - 用 `.clipped()` 裁剪；
   - 图片缺失或失败时，底层占位继续可见。
4. 顶部深色渐变遮罩，保证标题在复杂图片上可读。
5. 左上角 `SealChip(text: "今日")` 或等价的固定标签。
6. 底部标题 `Text(story.title)`，使用 `DS.songBlack`。
7. 整块内容作为单一 `NavigationLink` 点击目标。

不要在组件中增加“打开文章”按钮；可访问性由链接的 label/hint 表达即可。

### 4.3 推荐布局参数

以 iPhone 390–430pt 宽度为基准：

| 项目 | 标准/中密度 | 沉浸/低密度 | 速览/高密度 |
| --- | ---: | ---: | ---: |
| 外部水平边距 | 20pt | 20pt | 20pt |
| 开场高度 | 248–280pt | 300–340pt | 176–208pt |
| 圆角 | 12pt | 14pt | 10pt |
| 标签内边距 | 5×3pt | 5×3pt | 5×3pt |
| 标题字号 | 24–28pt | 28–32pt | 20–23pt |
| 标题最大行数 | 3 | 3 | 2 |
| 图片内容 | 同一张 `story.image` | 同一张 `story.image` | 同一张 `story.image` |

这些高度是布局目标，不是固定验收值。Dynamic Type 增大时，组件应允许通过 `fixedSize(horizontal: false, vertical: true)` 增高，不能截断关键标题。

### 4.4 示例结构

```swift
struct TodayStoryOpeningView: View {
    let story: TopStory
    let density: HomeInformationDensity
    @ObservedObject var homeViewModel: HomeViewModel

    private var storySummary: StorySummary {
        StorySummary(
            id: story.id,
            title: story.title,
            images: story.image.map { [$0] } ?? [],
            hint: "顶部故事",
            url: story.url
        )
    }

    var body: some View {
        NavigationLink {
            ArticleDetailView(
                story: storySummary,
                homeViewModel: homeViewModel,
                source: .daily,
                date: ""
            )
        } label: {
            ZStack(alignment: .bottomLeading) {
                imageLayer
                LinearGradient(
                    colors: [.clear, DS.ink.opacity(0.86)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                copyLayer
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: density.openingHeight)
            .clipShape(RoundedRectangle(cornerRadius: density.openingCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: density.openingCornerRadius, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 0.7)
            }
            .contentShape(RoundedRectangle(cornerRadius: density.openingCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("今日故事：\(story.title)")
        .accessibilityHint("打开文章")
        .accessibilityIdentifier("home.todayStoryOpening")
    }
}
```

> 上述代码是结构示例，最终实现时应以项目实际 `RemoteImageView` 初始化方式和现有 SwiftUI 编译约束为准。

---

## 5. `HomeInformationDensity` 扩展

建议只在现有枚举中增加展示令牌，不改变已有语义：

```swift
extension HomeInformationDensity {
    var openingHeight: CGFloat {
        switch self {
        case .low: 320
        case .medium: 270
        case .high: 196
        }
    }

    var openingCornerRadius: CGFloat {
        switch self {
        case .low: 14
        case .medium: 12
        case .high: 10
        }
    }

    var openingTitleLineLimit: Int {
        switch self {
        case .low, .medium: 3
        case .high: 2
        }
    }
}
```

### 5.1 三档策略

- **沉浸**：开场更高，给题图和标题更多呼吸空间；不增加摘要。
- **标准**：作为默认实现，平衡题图与下方第一条日报的可见性。
- **速览**：降低开场高度并限制标题最多两行，但不隐藏开场，不改内容入口。

与现有 PRD 的建议一致：三档都保留同一条开场，差异只体现在展示节奏，不产生三套组件。

---

## 6. `HomeView` 接入点

现有 `storyFeed` 的顺序是：离线横幅 → `ForEach(viewModel.visibleSections)` → 历史分页。

调整为：

```swift
ScrollView {
    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
        if let bannerMessage = viewModel.bannerMessage {
            OfflineBanner(...)
        }

        if let openingStory = viewModel.topStories.first {
            TodayStoryOpeningView(
                story: openingStory,
                density: density,
                homeViewModel: viewModel
            )
            .padding(.horizontal, horizontalPadding(for: availableWidth))
            .padding(.top, density == .high ? 4 : 8)
            .padding(.bottom, density == .high ? 10 : 16)
        }

        ForEach(viewModel.visibleSections) { section in
            Section { ... }
        }

        HistoryPaginationFooter(...)
    }
}
```

### 6.1 为什么插入在 `ForEach` 之前

- 符合 PRD：开场位于第一条日期分节之前。
- 和日报列表共享同一个 ScrollView，不会产生独立滚动容器。
- 不改变 `Section` 的吸顶逻辑，日期刊头仍按现有方式工作。
- `topStories` 为空时条件不成立，不产生空白占位。
- 网络刷新或缓存切换时，视图由 `@Published topStories` 自动更新。

### 6.2 与 `visibleSections` 的关系

不要从 `visibleSections` 中查找或过滤顶部故事：

- 顶部故事可能与普通日报条目重复，这是现有接口数据语义，不在本功能中重新去重。
- 不应为了避免重复而修改推荐顺序、已读过滤或列表数据。
- 用户点击开场后的已读状态由现有详情流程处理，普通列表仍由现有 `viewModel.isStoryRead` 控制。

---

## 7. 图片与状态处理

### 7.1 有图

- 使用 `RemoteImageView(urlString: story.image, targetSize: ...)`。
- 目标尺寸按实际容器宽高乘以 `displayScale` 的方式由现有组件/Kingfisher 处理，避免加载原图造成内存浪费。
- 保留现有 `cancelOnDisappear(true)`，滚动离开时取消任务。

### 7.2 无图

- `RemoteImageSource.invalid` 不应让整个开场消失。
- 使用纸面占位：`DS.paperElevated`、淡墨“日”字或同源纹理。
- 标题仍覆盖在底部；如底部对比不足，切换为纸面底 + 浓墨文字，而不是硬套深色渐变。
- 点击目标和导航必须保持可用。

### 7.3 图片失败

- 复用 `RemoteImageView` 的失败回退能力。
- 不新增错误按钮、重试入口或 Toast；图片失败属于局部资源失败，首页仍可继续阅读。
- 失败后的标题、辅助功能标签和 NavigationLink 不受影响。

### 7.4 `topStories` 为空

- `TodayStoryOpeningView` 不创建。
- 不显示“暂无今日故事”，不留下固定高度和上下间距。
- 首页直接从离线横幅（如有）进入日报日期分节。

### 7.5 加载阶段

- `.loading` 仍使用现有 `LoadingView`，不额外为开场做骨架屏。
- 这样可以避免在接口尚未返回时制造一个看似有内容的空开场。

---

## 8. 可访问性与性能

### 8.1 可访问性

- NavigationLink 提供完整 label：`今日故事：{标题}`。
- 提供 hint：`打开文章`。
- `accessibilityIdentifier`: `home.todayStoryOpening`，用于 UI 测试。
- 图片作为装饰层处理，避免 VoiceOver 重复朗读图片描述；标题成为主要可读内容。
- 点击区域为整块开场，远大于 44pt。
- 标题使用 `fixedSize(horizontal: false, vertical: true)`，不依赖固定高度截断语义。
- 使用 `@Environment(\.accessibilityReduceMotion)`，不加入装饰性动画；如保留图片淡入，只在非 Reduce Motion 时启用。
- 动态颜色沿用 `DS`，支持浅色/深色模式。
- 不使用颜色作为唯一的已读/未读信息；本功能首版也不单独改变已读视觉。

### 8.2 性能

- 只渲染一张顶部故事图片。
- 使用已有 Kingfisher 缓存与下采样，不新增网络请求。
- 不使用视频、Canvas、Metal、Three.js 或持续动画；本场景没有引入这些技术的收益。
- 不在 `body` 中执行图片 URL 解析、网络调用或数据转换以外的重计算。
- 不使用 `GeometryReader` 驱动连续状态更新；尺寸由 SwiftUI 布局和现有 `availableWidth` 处理。
- 图片层设置 `.clipped()`，避免超出圆角容器造成额外绘制。

---

## 9. 测试方案

### 9.1 单元测试

新增或扩展 `TodayStoryOpeningTests.swift`，重点测试纯规则，而不是测试 SwiftUI 视觉像素。当前测试 Target 实际使用 XCTest（例如 `HomeViewModelTests`、`HomeInformationDensityTests`）；本需求继续沿用现状，不顺手迁移 Swift Testing，避免扩大范围：

1. `topStories.first` 作为开场故事。
2. `topStories` 为空时开场数据为 nil/不渲染条件成立。
3. `TopStory` 的标题、图片、URL 正确映射为 `StorySummary`。
4. 三档密度的开场高度、圆角和标题行数稳定。
5. 图片为空时不影响故事标题和详情目标映射。

如不想为简单派生属性新增测试文件，可以把密度规则加入现有 `HomeInformationDensityTests`，将导航/映射规则放入现有 `HomeViewModelTests` 或新建轻量测试。

### 9.2 UI 测试

扩展 `HomeFlowUITests.swift`：

```swift
func testTopStoryOpeningAppearsBeforeDailyList() {
    let app = launchApp(scenario: "latest_success")

    let opening = app.descendants(matching: .any)["home.todayStoryOpening"]
    XCTAssertTrue(opening.waitForExistence(timeout: 5))
    XCTAssertEqual(opening.label, "今日故事：今天，先读一篇长一点的故事")

    let firstStory = app.staticTexts["今天，先读一篇长一点的故事"].firstMatch
    XCTAssertTrue(firstStory.exists)
}

func testTopStoryOpeningCanOpenExistingArticleDetail() {
    let app = launchApp(scenario: "latest_success")
    let opening = app.descendants(matching: .any)["home.todayStoryOpening"]
    XCTAssertTrue(opening.waitForExistence(timeout: 5))

    opening.tap()

    XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
}

func testEmptyTopStoriesDoNotShowOpening() {
    let app = launchApp(scenario: "latest_empty")
    XCTAssertFalse(app.descendants(matching: .any)["home.todayStoryOpening"].waitForExistence(timeout: 2))
}
```

测试文案应以实际 SwiftUI 可访问性树为准；如果 NavigationLink 的 label 被拆成多个节点，应保留稳定 identifier，避免依赖图片或字体渲染。

### 9.3 回归范围

- 首页加载成功、缓存加载、离线缓存。
- `topStories` 为空但日报列表有内容。
- 图片为空、非法 URL、图片加载失败。
- 三档信息密度切换。
- 点击普通文章行和点击顶部故事均能进入详情。
- 下拉刷新后顶部故事更新。
- 历史分页和日期刊头吸顶不受影响。
- 深色模式、动态字体、VoiceOver 和 Reduce Motion。

---

## 10. 实施顺序

1. 在 `HomeInformationDensity` 增加开场展示令牌。
2. 新建 `TodayStoryOpeningView.swift`，先实现无图占位和标题/导航。
3. 接入 `RemoteImageView`，补齐有图与失败回退。
4. 在 `HomeView.storyFeed` 的首个日期分节之前插入组件。
5. 为组件补 accessibility identifier、label 和 hint。
6. 增加单元测试和 UI 测试。
7. 运行 `git diff --check`、单元测试、UI 测试和 iOS 构建。
8. 在真机/模拟器验证 iPhone SE、标准 iPhone、Pro Max 和 iPad 宽度。

每一步都不修改接口和数据模型，出现问题时可以通过移除 `HomeView` 的单个插入分支快速回滚。

---

## 11. 风险与决策

| 风险 | 处理 |
| --- | --- |
| 顶部故事与普通列表重复 | 接受现有数据语义，不做本地去重，避免改变推荐顺序 |
| 图片为空时标题对比不足 | 使用纸面占位并切换为浓墨文字，不强制使用图片渐变 |
| Dynamic Type 导致固定高度不足 | 标题允许垂直增长，开场高度只作正常尺寸目标 |
| 大图加载影响首屏 | 复用 Kingfisher 下采样和缓存，限制只加载第一条 |
| UI 测试依赖视觉文本不稳定 | 以 `home.todayStoryOpening` identifier 为主，文本为辅 |
| 三档密度出现三套设计 | 共用一个组件，仅通过枚举令牌改变节奏 |
| 视觉稿和 PRD再次越界 | 以本方案和 PRD 的 Non-goals 作为代码评审检查项 |

---

## 12. 验收清单

- [ ] 新增 `TodayStoryOpeningView`，未新增数据模型或接口。
- [ ] `topStories.first` 在首个日期分节之前展示。
- [ ] `topStories` 为空时无开场空白。
- [ ] 图片有图、无图、失败三种情况都能阅读标题并点击进入详情。
- [ ] 点击开场复用 `ArticleDetailView`，未新增中间页面。
- [ ] 三档信息密度均保留开场，只有高度/标题行数变化。
- [ ] 未加入声音、轮播、进度、作者、摘要、快捷操作等 PRD 明确排除项。
- [ ] 支持深色模式、Dynamic Type、VoiceOver、Reduce Motion。
- [ ] 单元测试和 UI 测试覆盖正常、空数据和导航路径。
- [ ] `git diff --check`、构建和相关测试通过。
