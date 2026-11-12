# tools 目录说明

这里是**手工验证与生成脚本**的集合，不是自动化测试套件（测试在 `tests/`，入口 `Rscript run_tests.R`）。

## 常用 / 持续维护

| 脚本 | 用途 |
|---|---|
| `make_geom_thumbs.R` | 重新生成 geom 示意图缩略图（改了默认主题/映射后跑一次，README 有说明） |
| `manual_build.mjs` / `manual_shots*.mjs` / `manual_verify.mjs` | 生成用户手册（`docs/manual/`）：截图 → 组装 HTML/PDF |
| `make_release.mjs` | 发布打包：`git archive` 干净源码树 + dist → `releases/glyph-<版本>.zip` |
| `test_host.mjs` | 单独验证 DSH 插件宿主半（加载 → 控制服务 → Glyph 进程 → 自动 stop 退出） |

## 代码健康诊断（可复用）

| 脚本 | 用途 |
|---|---|
| `find_dead_r.R` | 扫 R/ + run.R 的函数定义，跨仓库统计引用，列出零引用候选（需人工确认动态调用） |
| `find_dead_js.mjs` | 找 frontend/src 中未被 import 的组件与未使用导出 |
| `find_dup_r.R` | 找 R/ 下同名函数多处定义（source 顺序静默覆盖隐患） |
| `del_block.mjs` | 按签名正则 + 花括号配平，**就地删除**一个 `{…}` 块（通用重构助手，具破坏性，先提交再跑） |

## 一次性检查脚本（check_*.mjs / test_*.mjs / probe_*）

其余 20+ 个 `check_*` / `test_*` / `probe_*` / `shot_*`（含 `check_insert.mjs` 等）是**开发过程中的手工验证脚本**：
起一个临时 Edge 实例走 CDP 驱动页面、打印 JSON 供人工比对，**没有断言、永远 exit 0**，
不能算自动化测试。特征：

- 依赖 Windows + Edge（硬编码 Edge 路径）+ Node ≥ 21（原生 WebSocket）
- 假定 Glyph 服务已在 `127.0.0.1:4321` 运行（先 `Rscript run.R --no-browser`）
- 互相复制粘贴同一段 CDP 样板（约 20 行）——新写脚本建议抽成共享 helper 再加

改前端 UI 时可参考对应名字的脚本（如 `check_workspace_ui.mjs` 验证工作区切换、
`test_drag.mjs` 验证拖拽），跑完后记得删 `%TEMP%` 里的 `gg-*` 临时浏览器 profile。

## 存档

- `extension-eval/` + `fetch_ext_gallery.R` + `ggplot2_extensions_170.csv`：
  2026-11 扩展包可行性调研的输入与探针脚本（结论见 `docs/history/EXTENSIONS_ASSESSMENT.md`）。
