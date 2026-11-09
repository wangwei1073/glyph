# 代码绘图：保存 / 图库 / 项目管理设计

> 状态：方案稿（未实现）。目标是把「高级页运行代码得到的图」纳入现有图库与项目体系，
> 而不是另建一套代码绘图管理系统。

## 1. 目标与非目标

**目标**

- 代码图可以**存入图库**、重命名、删除、导出；
- 从图库打开代码图时，能**还原画布 + 代码 + 数据**；
- 项目保存/打开支持「代码模式」；
- 与现有 spec 图共用一套图库 UI、缩略图、导出入口。

**非目标（本期）**

- 多脚本/脚本工程管理；
- 云端同步、版本历史；
- 任意 R 代码的完全沙箱化。

## 2. 数据模型

### 2.1 图库条目（统一 Entry）

```json
{
  "id": "P12",
  "type": "code",                  // "spec" | "code"，旧条目缺省视为 spec
  "label": "ECMO 分布图",
  "project": "",
  "t": "11-09 15:20",
  "renderOpts": { "width": 900, "height": 560, "dpi": 150 },
  "thumb": "P12.png",              // 缩略图/全图缓存
  "specJson": null,                // spec 图专用
  "code": {
    "text": "library(ggplot2)\n...",
    "packages": ["ggplot2", "ggside"],
    "warnings": []
  },
  "data": {
    "mode": "snapshot",            // "snapshot" | "reference"
    "snapshot": "P12.rds",         // mode=snapshot：df 快照文件
    "source": { "type": "user", "id": "u6" },  // mode=reference
    "prep": { "filter": "", "mutate": [], "sample": null }
  },
  "createdAt": "2026-11-09T15:20:00Z"
}
```

**为什么需要 `data`**

- 代码可以任意操作 `df`，只有快照能保证“打开即重现”；
- 但大数据集快照可能很大，所以保留 `reference` 模式（只存数据源 + 数据准备配置）。

### 2.2 存储布局

```
<app-data>/pins/
  pins.json        # 条目数组（含 type 字段）
  P12.png          # 渲染结果（现有机制复用）
  P12.rds          # 代码图的数据快照
  P12.R            # 可选：保存时同步导出代码
```

### 2.3 项目文件

```json
{
  "version": 2,
  "mode": "code",                 // "spec" | "code"
  "spec": { ... },                // mode=spec
  "code": { "text": "...", "packages": [...] },
  "data": { "mode": "snapshot", "snapshot": "data.rds" },
  "renderOpts": { "width": 900, "height": 560, "dpi": 150 }
}
```

旧项目没有 `mode` 时按 `spec` 处理，无需迁移。

## 3. 保存流程（代码页 → 图库）

入口：高级页工具栏「存入图库」。

1. 校验代码非空；
2. 若当前没有渲染结果，先运行一次（可跳过，用上一次 png）；
3. 弹窗：
   - 名称（默认“代码图 N”）、说明（可选）；
   - 数据绑定：**内嵌快照（推荐）** / 关联当前数据源；
   - 若内嵌，显示快照大小预估；
4. 调用 `POST /api/pins/save-code`：
   - 写 `Pxx.rds`（快照）或记录 `source + prep`；
   - 复用当前 png 作为缩略图；
   - 追加条目到 `pins.json`；
5. 图库刷新，卡片带「代码」徽标。

## 4. 打开流程（图库 → 画布）

1. 点击代码条目：
   - 画布加载 `Pxx.png`；
   - 高级页载入 `code.text`；
   - `mode=snapshot` 时把 `Pxx.rds` 恢复为 `df`；
   - `mode=reference` 时按 `source + prep` 重新解析数据；
2. 若缺少包：提示“需要安装 X、Y”，不阻塞打开；
3. 用户可再次「运行代码」覆盖当前渲染。

## 5. 删除 / 重命名 / 导出

- 删除：删除条目 + `Pxx.png` + `Pxx.rds` + `Pxx.R`；
- 重命名：只改 `label`；
- 导出：复用现有 PNG/SVG/PDF 导出；额外提供「下载 .R」。

## 6. 边界与策略

| 场景 | 策略 |
|---|---|
| 数据集很大（快照 > 50MB） | 提示并建议改「关联数据源」；或只存引用 |
| 代码依赖外部文件/网络 | 保存时提示“无法保证完全重现” |
| 缺少 R 包 | 打开时列出缺失包，提供安装入口 |
| 代码有副作用 | 保存/打开时提示“执行任意代码”，不做沙箱承诺 |
| 旧 pins 无 type | 默认 `spec` |
| 项目模式切换 | 保存项目时写入 `mode`；打开按 mode 恢复画布与高级页 |

## 7. 接口变更

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/pins/save-code` | 保存代码图（label/code/data/renderOpts） |
| GET | `/api/pins` | 条目增加 `type`、`code`、`data` 字段 |
| POST | `/api/pins/delete` | 增加清理 `Pxx.rds` / `Pxx.R` |
| GET | `/api/pins/{id}/data` | 取快照（恢复 df 用） |
| GET | `/api/pins/{id}/code` | 取代码文本 |

## 8. 实施顺序

- **P0（最小闭环）**：保存代码图（快照模式）+ 图库徽标 + 打开还原；
- **P1**：关联数据源模式、缺失包提示、项目 code 模式；
- **P2**：多脚本、版本历史、代码图模板。
