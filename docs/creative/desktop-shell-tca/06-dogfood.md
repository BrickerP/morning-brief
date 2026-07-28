# Desktop Shell + TCA — Dogfood

## Status

- Creative Builder step: 6 / Dogfood
- Date: 2026-07-28
- Build under test: `~/Applications/MorningBrief.app` (MiniTCA + hand-rolled shell)

## Cold start（下次再来）

```bash
open ~/Applications/MorningBrief.app
# 应落在「工作台账」；捕获框可点；⌘1/2/3 切 lens
briefctl todo view --days 7   # 状态对照
```

---

## Scripts（3）

### S1 — 冷启动记一条
### S2 — 空历史日热力不丢
### S3 — 改状态 + 壳内其他 lens

（步骤同前一版；略）

---

## Run log

| Script | Result | Notes |
|--------|--------|-------|
| S1 | **PASS**（后端） / UI 部分 | `open` 后窗口 1100×740，侧栏标题可见。经 `briefctl todo add` 同路径写入 `dogfood-S1-冷启动捕获`，`todo view` 可见。未做 GUI 键入自动化。 |
| S2 | **PASS（逻辑）** / 待你目视 | 磁盘日均有 `work.json`；今日 projection 含 8 条可算热力。代码路径：`selectDate` 非今日时 `heatmapUpdated` 来自今日 `todoView`。请你点一个淡日确认绿点不整表消失。 |
| S3 | **PASS（状态）** / 壳切换有摩擦 | `dogfood-S1` → `in_progress`（version 2）与 CLI 一致。菜单切到「晨报」后窗口曾变为 **off-screen**（进程未崩，AXRaise 可找回）。已加 lens 切换后 `makeKeyAndOrderFront` 缓解。 |

### Evidence

- 今日 `briefctl todo view --days 7`：`date=2026-07-28`，`items=8`（含 dogfood 条）
- 切「晨报」：`CGWindowList` 仍有 `Morning Brief` 1100×740，但 `onScreen=0` → 排序/前置问题，非崩溃
- P0 修复：`RootWindowView` 在 `lens` onChange 里 activate + orderFront

### Fixed this round (P0)

- 切 lens（尤其晨报）后窗口失去前置/像「消失」→ 强制 `NSApp.activate` + `makeKeyAndOrderFront`

### Backlog（非 P0）

- GUI 捕获框自动聚焦未在自动化中验证  
- 正品 TCA / Luminare SPM 替换 MiniTCA  
- Agent / 晨报迁入 TCA  
- 热力空日需你再点一次目视确认  

### Dogfood verdict

主路径（记一条 / 改状态 / 壳可达）**可自用**；晨报切换前置问题已补一刀。请你本地再点：空历史日热力、侧栏点晨报是否还会「窗没了」。
