# 项目长期约定

- Git 分支策略：`main` 保持已整合版本；`version/2.1` 是当前长期工作分支。除非子上明确要求切换或新建分支，否则后续需求都直接在当前版本工作分支实现并提交，不再按小需求拆分临时分支。
- 分支清理：只删除已经完整合入 `main` 的旧分支；不得强制删除未合并分支。
- 文件共享已开启：`DailyReader/Resources/Info.plist` 含 `UIFileSharingEnabled` 与 `LSSupportsOpeningDocumentsInPlace`（提交 `a322c10`）。用途：模拟器/真机均可通过「文件」App 向 App 沙盒传文件（如导入阅读状态备份 JSON）；测试导入功能依赖此开关。XcodeGen 以该 plist 为基准合并，重生成不会丢。
- 调试工具 Lookin：`project.yml` 已 SPM 集成 `LookinServer`（`prnd-ios/LookinServer-XCFramework`, from 1.2.8，提交 `6fadcc0`）供真机调试视图层级。**模拟器调试零集成**——Mac 版 Lookin 桌面 App 直接连模拟器运行中的 App，无需改项目。改 project.yml 后须本地重新 `xcodegen generate` + SPM resolve（沙箱无法 resolve）。SPM 方式 Release 包也会含 LookinServer（个人项目可接受）。
- Memory 提交约定：每次完成工作后，当日日志（`YYYY-MM-DD.md`）与 `MEMORY.md`（如有改动）必须随代码改动一起 `git add` + 提交，不要单独留着或遗漏。
