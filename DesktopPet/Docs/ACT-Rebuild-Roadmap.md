# DesktopPet ACT 重构路线图

## 目标

把当前 ACT 运行时重构成一套分层清晰、可调试、可扩展的系统，最终支持：

- 稳定的受击与命中表现
- 击飞、浮空停滞、倒地、抓取、举起、摔落
- 数据驱动的技能定义
- 后续可扩展的 ACT 编排 / 时间轴演出
- 技能特效同时支持 `Spine` 与 `PNG 序列`

这份文档是执行路线图。后续严格按阶段推进，当前阶段验收通过之前，不进入下一阶段。

## 当前进度

- 第一阶段：已完成
- 第二阶段：已完成
- 第三阶段：进行中
- 第四阶段：未开始
- 第五阶段：未开始

### 当前已落地内容

- 已拆出独立的 `Target Reaction Runtime`
- 已拆出独立的 `Target Motion Runtime`
- hit result、reaction apply、motion apply、presentation 提示已经形成清晰主链路
- `reaction JSON` 中的 `gravityScale`、`lockHorizontal`、`lockVertical`、`animationState` 已接入运行时
- `airSuspendTarget` 已升级为独立的 `reaction.air_hold` 语义，而不是继续伪装成普通 `launched`
- 调试快照现在可区分：
  - `combat.launched`
  - `reaction.air_hold`
  - `reaction.knockdown`

### 进入第三阶段前的已知边界

- 受击语义层已经成立，但“跟随攻击者 / 跟随骨骼 / 释放投掷”还未开始
- 当前 `air_hold` 解决的是“受控浮空停滞”，不是抓取或举起
- 复杂约束技能仍需第三阶段的 constraint runtime 继续扩展

### 第三阶段当前进展

- 已建立跨 session 的 motion directive 分发链路：
  - `Skill Runtime`
  - `GameEngine`
  - `Target Motion Runtime`
- `Target Motion Runtime` 已具备第一批 constraint mode：
  - `lock_point`
  - `follow_attacker_root`
  - `release_velocity`
- 目标现在可以在运行时：
  - 跟随攻击者 root 点
  - 保持相对偏移
  - 在 release 时带速度脱离约束
- `spear_sky_pierce` 已作为第三阶段首个示例技能开始接入：
  - `launch`
  - `air_hold`
  - `followTargetRoot`
  - `releaseTarget`
- `char_munjoong_vacation` 的 `u / combat.ultimate` 现已改造成基于现有资源的 `Lift Slam` 示例：
  - `lift_hit`
  - `lift_hold`
  - `slam`

## 当前问题诊断

目前 ACT 代码并不是“完全没设计”，而是“设计意图有了，但运行时边界没有真正落地”，主要问题有：

- `PETGameSession` 同时承担了技能推进、施法位移、效果触发、目标受击、事件派发等过多职责
- `PETCombatStateComponent` 只有很粗的战斗状态，无法承载浮空停滞、抓取跟随、举起摔落这类复杂目标表现
- reaction JSON 已经定义了不少字段，但运行时只消费了其中一部分
- 浮空逻辑被拆散在 combat、movement、presentation 三层里
- 表现层还在自行猜测受击动画，而不是消费运行时明确产出的结果

所以现在“浮空 bug 很难修”，本质不是某个判断错了，而是缺少中间层，导致一件事在多个模块里各自表达了一遍。

## 最终分层目标

我们最终要把 ACT 体系整理成下面五层：

1. `ACT Core`
2. `Skill Runtime`
3. `Target Reaction Runtime`
4. `Target Constraint / Motion Runtime`
5. `Presentation / Editor`

### 1. ACT Core

职责：

- 接收战斗命令
- 命中判定
- 生成命中结果
- 维护低层战斗事件流

不负责：

- 浮空保持规则
- 抓取跟随规则
- 受击动画猜测

### 2. Skill Runtime

职责：

- 加载技能定义
- 推进技能 phase
- phase 切换
- hit window 生命周期
- 定时效果事件触发

不负责：

- 直接修改目标复杂位移
- 直接处理表现层猜动画

### 3. Target Reaction Runtime

职责：

- 目标受击状态
- hitstun
- launched
- air_hold
- knockdown
- grabbed
- reaction 动画提示
- gravityScale / 锁轴 / 控制锁定

这是当前系统最缺的一层。

### 4. Target Constraint / Motion Runtime

职责：

- 击飞初速度
- 浮空停滞
- 跟随攻击者
- 跟随攻击者骨骼点
- 约束释放
- 抛投 / 下砸 / 摔落

这一层是后面做“举起、抱摔、抓取、处决”类技能的基础。

### 5. Presentation / Editor

职责：

- 纯展示
- 调试面板
- 后续 ACT 编排编辑器
- 技能特效播放与预览

必须消费运行时明确结果，不再自行猜测战斗语义。

## 特效资源支持目标

后续编排和运行时都必须明确支持两类技能特效资源：

### 1. Spine 特效

支持：

- 读取 Spine JSON / Atlas / PNG
- 播放 Spine 动画
- 绑定到世界坐标
- 绑定到攻击者
- 绑定到被击者
- 绑定到指定骨骼 / 插槽
- 偏移、缩放、层级、翻转

### 2. PNG 序列特效

支持：

- 多帧 PNG 序列播放
- 帧率控制
- 循环 / 单次播放
- 世界坐标 / 角色绑定 / 骨骼绑定
- 偏移、缩放、层级、翻转

### 统一抽象要求

不管底层是 `Spine` 还是 `PNG 序列`，运行时和后续编辑器都要统一抽象成“特效实例”：

- 资源类型
- 开始时间
- 持续时间
- 播放模式
- 绑定目标
- 位置偏移
- 缩放
- 层级

也就是说：

**有设计，而且必须支持 `Spine` 和 `PNG 序列` 双通道播放。**

只是当前这份路线图里把它归在后续运行时与编排层统一能力里，而不是先散落在技能特例逻辑里。

## 阶段计划

## 第一阶段：运行时边界整理

### 进度

已完成。

### 阶段目标

先把当前 ACT 运行时职责拆清，让调试路径可读，不再让 `PETGameSession` 成为总控巨石类。

### 范围

- 梳理并隔离 `PETGameSession` 中混在一起的逻辑
- 明确以下链路的边界：
  - 技能 phase 推进
  - hit result 生成
  - target reaction 应用
  - target motion 应用
  - presentation 提示输出

### 阶段产物

- 更清晰的运行时结构
- 更明确的调试快照字段
- 暂不扩展新玩法

### 本阶段必须成立的事情

- 调 launch / 浮空问题时，能找到单一主链路
- hit result 生成与 target reaction 应用是两个明确步骤
- timed skill effect 与 target motion 应用不再混成一团

### 验收标准

本阶段通过时，必须满足：

1. 代码中存在清晰可追踪的四条主链路：
   - 技能推进
   - 命中结果生成
   - 目标反应应用
   - 目标运动应用
2. 阅读 launch bug 时，不再需要在一个类里来回跳很多段逻辑。
3. 调试快照至少能看到：
   - 当前 skill phase
   - 当前 combat state
   - 当前 reaction state 或预留字段
   - 当前目标是否处于自由运动 / 击飞 / 约束控制

### 本阶段不做

- 不改技能格式
- 不上新 reaction 类型
- 不做编排编辑器

### 完成说明

- `PETGameSession` 不再独占技能推进、命中结果生成、受击应用、目标运动应用四条链路
- 已形成：
  - `Skill Runtime`
  - `Target Reaction Runtime`
  - `Target Motion Runtime`
  - `Presentation Bridge`
- 调试快照已能同时看到：
  - 当前 `skill phase`
  - 当前 `combat state`
  - 当前 `reaction state`
  - 当前目标运动控制模式

## 第二阶段：目标受击运行时

### 进度

已完成。

### 阶段目标

建立独立的目标受击运行时，让浮空、空中停滞、倒地、抓取不再只是字符串状态。

### 范围

引入目标 reaction state，例如：

- `hitstun`
- `launched`
- `air_hold`
- `knockdown`
- `grabbed`

每种 reaction 至少支持：

- 持续时间
- 动画提示
- gravityScale
- horizontal lock
- vertical lock
- control lock

### 阶段产物

- 独立的 target reaction runtime 或等价模块
- reaction JSON 中的关键字段真正被运行时消费
- launched 和 air hold 在内部成为不同语义

### 本阶段必须成立的事情

- `gravityScale`、`lockHorizontal`、`lockVertical`、`animationState` 不再是无效字段
- `airSuspendTarget` 不再只是再造一个 launched hit result
- 目标可以在空中保持一段受控反应，而不是完全依赖 jump 逻辑

### 验收标准

本阶段通过时，必须满足：

1. 一个技能可以把目标打入 `launched`
2. 一个技能可以把目标打入 `air_hold`
3. 目标能按配置停留在持续 reaction 中
4. 调试数据能区分：
   - `combat.launched`
   - `reaction.air_hold`
   - `reaction.knockdown`

### 本阶段不做

- 不做骨骼跟随
- 不做摔投类约束

### 完成说明

- 已引入独立 reaction 语义：
  - `reaction.hitstun`
  - `reaction.launched`
  - `reaction.air_hold`
  - `reaction.knockdown`
  - `reaction.grabbed` 预留
- `PETHitResult` 现在会携带：
  - `reactionState`
  - `reactionGravityScale`
  - `reactionLocksHorizontal`
  - `reactionLocksVertical`
  - `reactionAnimationState`
- `PETTargetReactionRuntime` 已负责维护：
  - 当前 reaction 语义
  - 反应剩余时间
  - 重力缩放
  - 锁轴信息
  - 动画提示
- `PETMovementComponent / PETMovementSystem` 已开始消费 reaction 施加的重力和锁轴，不再把 `controlLocked` 直接当成“物理完全停止”
- `airSuspendTarget` 已生成 `reaction.air_hold`，并驱动更长持续的空中 reaction 表现
- `reaction runtime` 状态已进入序列化 / 恢复路径，避免恢复后把 `air_hold` 丢回模糊 combat 状态

## 第三阶段：目标约束与运动运行时

### 进度

进行中。

### 阶段目标

支持举起、抓取、跟随、摔落、抱摔这类 ACT 技能需要的目标约束能力。

### 范围

引入目标运动 / 约束模式：

- free motion
- launch impulse
- lock point
- follow attacker root
- follow attacker bone
- release with velocity

### 阶段产物

- 独立的 target motion / constraint runtime
- 目标空中控制不再完全依赖 jump 字段
- 目标能独立于施法者 motion 被约束

### 本阶段必须成立的事情

- 目标可以被举到稳定位置
- 目标可以跟随攻击者一段时间
- 目标可以被释放并进入投掷 / 摔落速度

### 验收标准

本阶段通过时，必须满足：

1. 一个技能可以把目标举起到指定相对位置
2. 一个技能可以让目标稳定跟随攻击者
3. 一个技能可以解除约束并把目标摔出去
4. 整个过程不依赖 presentation 层临时猜动画才能成立

### 本阶段不做

- 不做完整时间轴编辑器
- 不做任意拖拽录制

### 当前完成说明

- 已接入新的 motion effect：
  - `followTargetRoot`
  - `lockTargetPoint`
  - `releaseTarget`
- `PETGameEngine` 已能把技能 effect 产出的 target motion directive 路由到目标 session
- `PETTargetMotionRuntime` 调试快照现在能看到：
  - `constraintSourcePetIdentifier`
  - `constraintAnchorPoint`
  - `constraintOffset`
  - `constraintTimeRemaining`
- 当前还缺：
  - `follow attacker bone`
  - 更稳定的举起 / 摔落专项技能验收
  - 更完整的序列化恢复

## 第四阶段：声明式目标片段

### 阶段目标

让复杂技能可以用声明式数据直接描述目标表现，而不是全靠命中副作用硬拼出来。

### 范围

引入 target 侧声明式片段，例如：

- target reaction clip
- target constraint clip
- target motion clip
- target animation clip

此阶段仍然可以先只做 JSON，不做 GUI 编辑器。

### 阶段产物

- 技能数据可以描述目标在一段时间内的持续行为
- hit window 保留，但不再承担所有目标演出的表达
- 复杂技能开始真正数据驱动

### 本阶段必须成立的事情

- “举起 -> 保持 -> 砸下” 可以直接写在 skill 数据里
- `air_ing` 这种持续空中表现不需要靠很多零散 effect hit 硬凑

### 验收标准

本阶段通过时，必须满足：

1. 至少一个示例技能可以声明：
   - hit
   - lift
   - hold
   - slam
2. 至少一个示例技能可以声明：
   - launch
   - air hold
   - repeated hit pulse
   - knockdown finish
3. 数据仍然保持声明式，不演变成脚本语言

### 本阶段不做

- 不做 GUI 时间轴编辑器

## 第五阶段：ACT 编排与时间轴演出

### 阶段目标

在稳定运行时之上，构建 ACT 编排层，用于制作特殊技能演出。

### 范围

未来时间轴轨道包括：

- attacker action track
- effect track
- target reaction track
- target constraint track
- target motion track
- target animation track

并且 effect track 要支持：

- Spine 特效
- PNG 序列特效

### 阶段产物

- 可回放的 ACT 编排 JSON
- 调试播放器或编辑器原型
- 支持举起、跟随、摔落、空连等特殊技能演出

### 本阶段必须成立的事情

- 编排层建立在前几阶段稳定 runtime 之上
- 编辑器或播放器导出的结果可稳定重放

### 验收标准

本阶段通过时，必须满足：

1. 一个编排技能能保存并稳定回放
2. 回放时能还原：
   - 攻击者动作
   - 技能特效
   - 目标 reaction state
   - 目标约束位置
   - 目标释放后运动
3. 一个“举起摔落”示例技能不需要再写大量硬编码运行时逻辑
4. 特效回放同时覆盖：
   - 一个 Spine 特效示例
   - 一个 PNG 序列特效示例

### 本阶段不做

- 不企图一次解决全部战斗系统细节
- 不替代底层 hit confirm

## 推荐推进顺序

不要先上编排，再补运行时。推荐顺序必须是：

1. 第一阶段：运行时边界整理
2. 第二阶段：目标受击运行时
3. 第三阶段：目标约束与运动运行时
4. 第四阶段：声明式目标片段
5. 第五阶段：ACT 编排与时间轴演出

如果跳过第二或第三阶段，后面的编排层只会变成“更复杂地制造不稳定 bug”。

## 第一批值得内部验收的里程碑

最先值得内部通过的一组能力是：

- 击飞
- 空中停滞
- 倒地
- 举起跟随
- 释放摔落

这组能力大概会在第三阶段完成，或者第四阶段前半段可用于第一批复杂技能验证。

## 工作规则

从现在开始，每个阶段都按同样方式推进：

1. 收紧本阶段目标
2. 只做本阶段范围
3. 做 1 到 2 个示例技能
4. 对照验收标准检查
5. 通过后再进入下阶段
