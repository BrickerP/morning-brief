# Desktop Shell + TCA — Next Loop

## Status

- Creative Builder step: 7 / Re-brainstorm
- Date: 2026-07-28
- Input: `06-dogfood.md` + shipped week-1 slice

## Validated

- 台账作为第一刀正确：捕获 / 改状态 / 热力缓存边界可自用  
- 共享壳（侧栏 + 材料）比 MenuBar 面板更适合桌面日常  
- Feature 边界有用：`WorkFeature` + `BriefctlClient` 即使没有正品 TCA 也能落地  
- 三 lens 同壳可达；晨报切换前置问题可修  

## Falsified / weakened

- 「一周内装上正品 TCA + Luminare SPM」——本机 GitHub 拉取失败，不成立  
- 「手写壳 = 差一点就行」——气质够用，但签名感仍弱于真 Luminare/Loop  
- 「Agent/晨报只挂旧内脏无感」——切 lens 曾暴露窗口前置问题，旧路径仍会咬人  

## New opportunities

1. **换正品依赖**：网络恢复后 SPM → 删 MiniTCA / 手写壳重复  
2. **Agent 确认流进 TCA**：第二刀产品价值（确认闸 + 会话列表）  
3. **晨报阅读进 TCA**：刷新/合成/日期与 Work 日期桥接单一真相  
4. **捕获体验**：冷启动自动聚焦、成功插入动画（design brief 动效 2）  
5. **砍**：继续堆 BriefStore 方法——应冻结，只进 Feature  

## 下一刀（只选一个）

**Agent 确认流 → TCA `AgentFeature`（同壳）**

| | |
|--|--|
| **为什么** | 台账骨头已立；下一痛是「Agent 建议点确认」仍挂在偶然 store 上，也是愿景顺序里的第 2 站（台账 → **Agent** → 晨报） |
| **一周切片** | `AgentFeature`：sessions 列表、locate/analyze、apply 确认横幅、取消；UI 仍在现壳侧栏 Agent |
| **不做** | 晨报 TCA；正品 Luminare 像素复刻；重写 briefctl |
| **成功信号** | 点一条会话 → 出建议 → 确认写入台账 → Work 热力/跨度无需重启即可看到更新 |

备选（若你否决 Agent）：先 **SPM 换正品 TCA**（工程刀，产品体感弱）或 **晨报 Feature**（顺序第三）。

## 下一轮开场假设（若立刻开 step 1）

> HYPOTHESIS：把 Agent 确认流收进与 Work 同构的 Feature/Store 后，确认不再「点了不知道发生什么」，且写入后台账主屏不用重启。  
> 子项目可继续写在 `docs/creative/desktop-shell-tca/`（08+）或新开 `docs/creative/agent-feature/`。

## Gate

用户确认「下一刀 = Agent TCA」后，再开下一轮步骤 1；或改选上面的备选。
