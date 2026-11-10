# docs 目录索引

| 文档 | 内容 | 状态 |
|---|---|---|
| [IMPORT_DIALOG_V2.md](IMPORT_DIALOG_V2.md) | 导入弹层 v2 设计（文件/SQLite/远程库/剪贴板） | 活文档（已实现） |
| [CODE_PLOT_DESIGN.md](CODE_PLOT_DESIGN.md) | 代码绘图纳入图库/项目体系的设计 | 活文档（已实现，状态头已更新） |
| [manual/](manual/) | 用户手册（PDF + HTML + 截图），由 `tools/manual_build.mjs` 等脚本生成 | 随版本重新生成 |
| [history/](history/) | 一次性评估/走查快照（2026-11 从仓库根目录移入） | 历史记录，仅供回溯 |

## 根目录文档导航

- **README.md** —— 快速开始、功能总览、开发与测试（唯一入口文档）。
- **FIXES.md** —— 修复日志（持续追加，每批记录问题→验证方式）。
- **POSITRON_PLAN.md** —— Positron 扩展的活跃开发计划。
- **docs/history/** —— 已完结的评估与走查：REVIEW、UI_REVIEW、AI_ASSIST（AI 功能评估，非贡献者文档）、
  RESEARCH_WORKFLOW、EXTENSIONS、EXTENSIONS_ASSESSMENT、STATS_ASSESSMENT、
  DATA_INSIGHT_ASSESSMENT、TAURI_ASSESSMENT、POSITRON_PROTOTYPE。
  其中的结论多为已实现或已过时状态，引用前请核对当前代码。

## 新贡献者路径

1. 读 README「快速开始 + 核心设计」；
2. 跑 `Rscript run_tests.R` 确认环境可用；
3. 改前端：`cd frontend && npm run dev`（代理 /api → 4321）；
4. 改后端：源码改动后重启 `Rscript run.R`，对应测试在 tests/ 有同名覆盖。
