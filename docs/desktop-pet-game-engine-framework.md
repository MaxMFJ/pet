# Desktop Pet Game Engine Framework

## 定位

桌面宠物游戏引擎不是替代现有 `Character OS`，而是挂在语义运行时下游的游戏化执行层。

它负责把“角色想做什么”落成可玩的桌面行为：

- 键盘 / 鼠标 / 触摸输入
- 上下左右移动
- 角色朝向、速度、碰撞和屏幕边界
- 技能释放、技能特效、命中判定
- HP / MP / 攻击 / 防御 / 冷却等数值计算
- Spine / WebP / 粒子 / 音效 / MP4 大招演出
- 桌面窗口层级、穿透、暂停、恢复
- 后续小游戏、战斗、任务、道具、关卡事件扩展

现有 `Character OS` 继续负责语义、情绪、目标、任务、记忆和行为选择；游戏引擎负责执行规则、表现和可玩性。

```text
Keyboard / Mouse / Touch / OCR / LLM / System Events
                         |
                         v
                  Character OS Runtime
       Intent -> Emotion -> Goal -> Task -> Behavior
                         |
                         v
              Desktop Pet Game Engine
 Input -> Movement -> Skill -> Combat -> VFX/Audio/Video
                         |
                         v
        Pet Window / Spine / WebP / Metal / AVPlayer / Desktop
```

## 核心原则

- 语义和游戏规则分层：LLM / OCR / 情绪不能直接播放技能或扣血，只能产出结构化意图。
- 输入统一：键盘、鼠标、触摸、脚本、AI 建议都先转成 `GameCommand`。
- 时间统一：移动、技能、冷却、特效、数值都由同一个 tick 驱动。
- 表现可替换：Spine、WebP、MP4、粒子、音效只是渲染后端，不写死到战斗逻辑里。
- 数据驱动：技能表、数值表、按键映射、特效绑定、动画绑定应尽量放到配置。
- 可暂停 / 可恢复：每个宠物的游戏状态可以序列化，重启后恢复。
- 多宠物可扩展：引擎以 `petId` 为单位运行，不假设全局只有一个宠物。

## 建议目录

首期建议在 macOS 主工程中新增独立模块目录：

```text
DesktopPet/GameEngine/
  Core/
    PETGameEngine.h/.m
    PETGameWorld.h/.m
    PETGameTickDriver.h/.m
    PETGameCommand.h/.m
    PETGameEvent.h/.m
  Input/
    PETKeyboardInputRouter.h/.m
    PETGameInputBinding.h/.m
  Movement/
    PETMovementComponent.h/.m
    PETMovementSystem.h/.m
    PETCollisionSystem.h/.m
  Combat/
    PETStatBlock.h/.m
    PETCombatantComponent.h/.m
    PETDamageCalculator.h/.m
    PETResourceCalculator.h/.m
  Skill/
    PETSkillDefinition.h/.m
    PETSkillRuntime.h/.m
    PETSkillSystem.h/.m
    PETSkillEffectResolver.h/.m
  Presentation/
    PETGamePresentationBridge.h/.m
    PETVFXCue.h/.m
    PETAudioCue.h/.m
    PETVideoCue.h/.m
  Config/
    PETGameConfigLoader.h/.m
    PETGameInputBindings.plist
    PETSkillDefinitions.plist
    PETStatDefaults.plist
```

iOS 后续可复用 `Core / Movement / Combat / Skill / Config`，只替换 `Input / Presentation` 的平台实现。

## 模块职责

### 1. PETGameEngine

总入口，负责创建和驱动每个宠物的游戏实例。

职责：

- 注册 / 注销宠物实例
- 接收 `GameCommand`
- 每帧推进 tick
- 调度 Movement / Skill / Combat / Presentation
- 向 `Character OS` 回写重要游戏事件
- 管理暂停、恢复、序列化

典型接口：

```objc
- (void)registerPetWithProfile:(PETPetProfile *)profile runtimeController:(PETCharacterRuntimeController *)runtimeController;
- (void)removePetWithIdentifier:(NSString *)petId;
- (void)submitCommand:(PETGameCommand *)command;
- (NSDictionary *)serializedStateForPetId:(NSString *)petId;
- (void)restorePetId:(NSString *)petId fromState:(NSDictionary *)state;
```

### 2. PETGameCommand

游戏命令是所有输入的统一格式。

来源可以是：

- keyboard
- mouse
- touch
- runtimeBehavior
- skillScript
- cognitionSuggestion
- debugPanel

建议字段：

```text
commandId
petId
type: move.started | move.changed | move.ended | skill.cast | skill.cancel | ultimate.cast | interact | debug
source
direction: up | down | left | right | vector
skillId
strength
timestamp
context
```

例子：

```json
{
  "petId": "pet-001",
  "type": "skill.cast",
  "source": "keyboard",
  "skillId": "fireball",
  "timestamp": 1780000000.12,
  "context": {
    "key": "J"
  }
}
```

### 3. Input System

负责把平台输入转换成 `PETGameCommand`。

macOS 首期：

- 方向键 / WASD：移动
- J / K / L：普通技能
- Space：跳跃或互动
- U / I / O：大招 / 特殊技
- Esc：取消技能或退出战斗态

输入绑定配置：

```text
W / UpArrow       -> move.up
A / LeftArrow     -> move.left
S / DownArrow     -> move.down
D / RightArrow    -> move.right
J                 -> skill.basic
K                 -> skill.special
L                 -> skill.counter
U                 -> ultimate.cast
Space             -> action.jump
Esc               -> action.cancel
```

注意：

- 输入层只负责“按了什么”，不负责判断能不能释放技能。
- 能不能移动、是否眩晕、MP 是否足够、冷却是否结束，都交给 Movement / Skill / Combat。
- 全局键盘监听需要考虑用户隐私和 macOS 权限；首期可以先只在 app 激活或宠物窗口聚焦时响应。

### 4. Movement System

负责桌面坐标里的移动和基础物理。

职责：

- 上下左右 / 向量移动
- 加速度、减速度、最大速度
- 朝向更新
- 屏幕边界限制
- 多显示器坐标适配
- 移动状态和动画状态绑定
- 未来支持跳跃、冲刺、击退、吸附、巡逻

建议状态：

```text
idle
walk
run
dash
jump
fall
knockback
stunned
locked
```

移动输出：

- 新窗口位置
- 面向方向
- 移动动画 cue
- 运动事件，如 `movement.hitBoundary`、`movement.dashEnded`

### 5. Skill System

负责技能生命周期。

技能阶段：

```text
requested -> checking -> casting -> active -> recovery -> cooldown -> ready
```

职责：

- 检查释放条件
- 消耗 MP / 能量 / 道具
- 进入前摇、命中、后摇、冷却
- 生成 hitbox / projectile / buff / debuff
- 触发 Spine 动画、特效、音效、MP4 大招
- 处理技能被打断、取消、失败

技能定义建议字段：

```text
skillId
displayName
inputAction
category: basic | special | ultimate | passive
cost:
  mp
  hp
  energy
cooldown
castTime
activeTime
recoveryTime
range
targeting: self | direction | nearest | cursor | area
damageFormula
animationCue
vfxCue
audioCue
videoCue
interruptLevel
```

### 6. Combat / Stats System

负责数值、资源和结算。

基础属性：

```text
level
hp / maxHp
mp / maxMp
attack
defense
magicAttack
magicDefense
speed
critRate
critDamage
damageBonus
damageReduction
tenacity
energy
```

资源规则：

- 普通技能消耗 MP
- 大招消耗 energy 或大量 MP
- MP 可随时间回复，也可通过命中、互动、任务奖励回复
- HP 为 0 时进入 `defeated / sleep / recover`，桌宠不一定真正死亡

伤害公式首期建议：

```text
baseDamage = attack * skillMultiplier + flatDamage
mitigated = baseDamage * 100 / (100 + targetDefense)
critical = mitigated * critDamage when random < critRate
finalDamage = max(1, critical * (1 + damageBonus - damageReduction))
```

桌宠场景里可以先支持“自我演出 / 训练目标 / 虚拟敌人”，等玩法明确后再扩展真实敌人系统。

### 7. VFX / Audio / Video Presentation

表现层只接收 cue，不参与规则判断。

Cue 类型：

```text
animationCue: 播放 Spine/WebP 动作
vfxCue: 播放粒子、贴图、屏幕闪光、拖尾
audioCue: 播放音效或语音
videoCue: 播放 MP4 大招
cameraCue: 桌面窗口缩放、震动、置顶、短暂锁定
uiCue: 飘字、伤害数字、MP 不足提示、冷却提示
```

MP4 大招建议：

- 使用 `AVPlayerLayer` 或独立透明/半透明覆盖窗口播放。
- 大招播放期间可锁定移动或降低输入优先级。
- 视频播放完成后发出 `video.finished`，技能系统再进入 recovery / cooldown。
- 视频资源不要写死路径，应通过 `skillId -> videoCue -> assetName` 绑定。

### 8. Game Event Bus

游戏事件用于模块之间通信，也用于回写 Character OS。

事件例子：

```text
game.move.started
game.move.ended
game.skill.requested
game.skill.castStarted
game.skill.hit
game.skill.missed
game.skill.interrupted
game.skill.cooldownReady
game.resource.mpChanged
game.resource.energyFull
game.combat.damageApplied
game.ultimate.videoStarted
game.ultimate.videoFinished
game.state.defeated
```

回写语义运行时：

- `game.skill.castStarted` -> `intent: gameplay.perform`
- `game.resource.mpLow` -> `intent: self.preserve`
- `game.ultimate.videoFinished` -> `intent: celebrate.finish`
- `game.state.defeated` -> `intent: recover.need`

这样游戏行为也会进入情绪、任务和记忆系统，而不是成为孤立效果。

## 数据流

### 键盘移动

```text
KeyDown(W)
  -> PETKeyboardInputRouter
  -> GameCommand(move.started, direction=up)
  -> PETGameEngine
  -> PETMovementSystem
  -> update velocity / position / facing
  -> PETGamePresentationBridge
  -> move pet window + play walk animation
  -> GameEvent(game.move.started)
```

### 技能释放

```text
KeyDown(J)
  -> GameCommand(skill.cast, skillId=basic)
  -> PETSkillSystem
  -> check cooldown / MP / state lock
  -> PETResourceCalculator consumes MP
  -> PETDamageCalculator prepares hit result
  -> PresentationBridge plays animation + vfx + audio
  -> GameEvent(game.skill.castStarted)
  -> CharacterRuntime receives gameplay.perform intent
```

### 大招 MP4

```text
KeyDown(U)
  -> GameCommand(ultimate.cast)
  -> SkillSystem checks energy / cooldown
  -> MovementSystem enters locked state
  -> PresentationBridge opens video overlay
  -> AVPlayer plays ultimate MP4
  -> video.finished
  -> SkillSystem applies effect / enters cooldown
  -> MovementSystem unlocks
  -> CharacterRuntime records memory
```

## 配置设计

### PETGameInputBindings.plist

```text
bindings:
  - key: W
    command: move.up
  - key: A
    command: move.left
  - key: S
    command: move.down
  - key: D
    command: move.right
  - key: J
    command: skill.cast
    skillId: basic
  - key: U
    command: ultimate.cast
    skillId: ultimate_001
```

### PETSkillDefinitions.plist

```text
skills:
  basic:
    category: basic
    mpCost: 0
    cooldown: 0.4
    castTime: 0.1
    activeTime: 0.2
    recoveryTime: 0.2
    damageFormula: attack * 1.0 + 5
    animationCue: attack
    vfxCue: slash_small
    audioCue: hit_light

  ultimate_001:
    category: ultimate
    mpCost: 60
    cooldown: 12.0
    castTime: 0.4
    activeTime: 2.6
    recoveryTime: 0.6
    damageFormula: attack * 5.5 + magicAttack * 2.0
    animationCue: ultimate_start
    vfxCue: ultimate_aura
    audioCue: ultimate_voice
    videoCue: ultimate_001.mp4
    interruptLevel: uninterruptible
```

### PETStatDefaults.plist

```text
defaultStats:
  level: 1
  maxHp: 100
  maxMp: 80
  attack: 12
  defense: 8
  magicAttack: 10
  magicDefense: 8
  speed: 220
  critRate: 0.05
  critDamage: 1.5
  energy: 0
```

## 与现有工程的连接点

### PETPetManager

建议成为游戏引擎注册入口：

- 添加宠物时注册到 `PETGameEngine`
- 删除宠物时注销
- 保存 app 状态时保存游戏状态
- 恢复 app 状态时恢复游戏状态

### PETPetWindow / PETPetView / PETSpineMetalView

建议只负责表现和窗口操作：

- 接收移动系统输出的位置
- 接收动画 cue
- 接收特效 / 视频 overlay 指令
- 不直接判断技能、数值、冷却

### PETCharacterRuntimeController

建议只通过事件桥连接：

- Character OS 可以产出 `runtimeBehavior` 命令，比如 `behavior.follow` -> `move.toTarget`
- 游戏引擎可以回写 `game.*` 事件，进入 intent / memory
- 双方不要互相调用内部细节

### PETCharacterSemanticMappings.plist

后续可新增 `game.*` 语义映射：

```text
game.skill.castStarted -> gameplay.perform
game.resource.mpLow -> self.preserve
game.ultimate.videoFinished -> celebrate.finish
```

## 首期 MVP

第一阶段不要一口吃完整战斗系统，先做一个可以玩的最小闭环。

### P0：引擎骨架

- 新增 `DesktopPet/GameEngine` 目录
- 新增 `PETGameEngine`
- 新增 `PETGameCommand`
- 新增 `PETGameEvent`
- 新增 `PETGameTickDriver`
- 支持每个 pet 注册 / 注销 / tick

验收：

- app 运行后，每个可见宠物都有一个 game session
- 可以打印 tick 和 petId
- 不影响现有拖拽、语义 runtime、Spine/WebP 播放

### P1：键盘移动

- 新增键盘输入路由
- 支持 WASD / 方向键
- 移动宠物窗口
- 根据方向更新朝向
- 行走时播放 walk / run，松开后回 idle

验收：

- 按住 W/A/S/D 可以移动桌宠
- 松开按键停止
- 到屏幕边缘不会飞出可见区域
- 现有鼠标拖拽仍可用

### P2：基础数值和普通技能

- 新增 `PETStatBlock`
- 新增 `PETSkillDefinition`
- 新增 `PETSkillSystem`
- 支持 J 键释放普通技能
- 支持 MP 消耗、冷却、失败原因
- 支持飘字 / debug log

验收：

- J 键能触发攻击动画和特效 cue
- 冷却中重复按键不会重复释放
- MP 不足时给出 game event

### P3：大招 MP4

- 支持 U 键释放大招
- 绑定 MP4 资源
- 播放期间锁定移动
- 播放完成后进入冷却并恢复 idle

验收：

- U 键触发大招动画或 MP4 overlay
- 播放完成有回调
- 移动锁定和恢复稳定
- 大招事件进入 Character OS 记忆

## 后续扩展

- 技能编辑器：在管理窗口里配置技能、按键、MP、冷却、动画、特效、MP4。
- 战斗沙包：生成一个透明训练目标，用于测试命中和伤害。
- 连招系统：按键序列触发不同技能分支。
- Buff / Debuff：加速、护盾、眩晕、燃烧、回血。
- 道具系统：把桌面文件、快捷方式或任务奖励变成道具。
- 任务玩法：Character OS 的 task 可以生成游戏目标，例如“陪我专注 25 分钟积攒能量”。
- 多宠互动：宠物之间互相释放技能、协作、追逐或表演。
- 场景系统：在桌面边缘、Dock 附近、窗口附近生成可交互点。
- 插件 API：第三方玩法模块只通过 command / event / config 接入。

## 命名建议

模块中文名：

- 桌面宠物游戏引擎
- Desktop Pet Game Engine

代码前缀：

- `PETGame...` 用于引擎公共类型
- `PETSkill...` 用于技能系统
- `PETCombat...` 用于战斗系统
- `PETMovement...` 用于移动系统
- `PET...Cue` 用于表现层提示

事件命名：

- 输入命令：`move.up`、`skill.cast`、`ultimate.cast`
- 游戏事件：`game.move.started`、`game.skill.hit`
- 语义意图：`gameplay.perform`、`self.preserve`

## 风险点

- 全局键盘监听可能需要辅助功能权限，首期先做 app 激活态输入更稳。
- MP4 透明通道在 macOS 上要提前验证格式；如果透明视频复杂，可以先用普通 overlay 或序列帧替代。
- 桌面窗口移动和鼠标拖拽可能冲突，需要输入优先级。
- 大招播放期间如果窗口被隐藏或宠物被删除，要正确取消 AVPlayer。
- 数值系统不要和 Character OS 的情绪值混在一起，情绪可以影响战斗参数，但不能共用同一个字段。
- 多显示器坐标系和 Retina 缩放需要单独测试。

## 推荐落地顺序

1. 先实现 `PETGameCommand / PETGameEvent / PETGameEngine`。
2. 接入 `PETPetManager`，让每只宠物拥有 game session。
3. 做 app 激活态键盘输入，打通 WASD 移动。
4. 做 `PETStatBlock` 和一个 `basic` 技能。
5. 做 presentation bridge，只发动画 cue 和 debug log。
6. 接入 MP4 overlay，完成大招闭环。
7. 把技能、按键、数值外置到 plist。
8. 再考虑编辑器、敌人、连招、多宠互动。

## 工程规格草案

这一节把框架继续压实成可以开工的 Objective-C 模块规格。

### 1. 运行时对象关系

```text
PETGameEngine
  |
  +-- sessions[petId] -> PETGameSession
                            |
                            +-- PETGameWorld
                            +-- PETMovementComponent
                            +-- PETCombatantComponent
                            +-- PETSkillRuntime
                            +-- PETGamePresentationBridge
                            +-- PETCharacterRuntimeController weak/ref
```

建议不要让 `PETGameEngine` 自己保存所有细节，而是每只宠物一个 `PETGameSession`。

`PETGameEngine` 负责全局调度；`PETGameSession` 负责单宠物状态；各 system 负责纯逻辑。

### 2. PETGameSession

`PETGameSession` 是每只宠物的游戏状态容器。

职责：

- 保存 petId、profile、runtimeController
- 保存当前坐标、速度、朝向
- 保存当前 stats、技能冷却、状态锁
- 接收 command
- 每帧 tick
- 产出 game events 和 presentation cues
- 支持序列化 / 恢复

建议接口：

```objc
@interface PETGameSession : NSObject

@property (nonatomic, copy, readonly) NSString *petIdentifier;
@property (nonatomic, strong, readonly) PETPetProfile *profile;
@property (nonatomic, strong, readonly) PETStatBlock *stats;
@property (nonatomic, assign, readonly) BOOL paused;

- (instancetype)initWithProfile:(PETPetProfile *)profile
              runtimeController:(PETCharacterRuntimeController *)runtimeController
              presentationBridge:(PETGamePresentationBridge *)presentationBridge;

- (void)submitCommand:(PETGameCommand *)command;
- (NSArray<PETGameEvent *> *)tickWithDeltaTime:(NSTimeInterval)deltaTime;
- (NSDictionary<NSString *, id> *)serializedState;
- (void)restoreFromSerializedState:(NSDictionary<NSString *, id> *)state;
- (void)setPaused:(BOOL)paused reason:(NSString *)reason;

@end
```

### 3. Tick 时序

首期用 `CADisplayLink` 不适合 macOS 主项目，建议 macOS 用 `CVDisplayLink` 或 `NSTimer` 起步。为了少改现有结构，P0 可以先用 `NSTimer`，后面再换高精度驱动。

推荐 tick 频率：

- 逻辑 tick：60 FPS，`dt` 做上限裁剪
- 最大 `dt`：`1.0 / 20.0`，避免窗口卡顿后宠物瞬移
- 表现层可以跟随逻辑 tick，也可以后续独立渲染

每帧顺序：

```text
1. drain pending commands
2. update input state
3. update movement locks
4. update skill cast / active / recovery / cooldown
5. update resources: mp regen, energy regen
6. calculate movement velocity and new position
7. clamp to screen bounds
8. produce animation / vfx / audio / video cues
9. emit game events
10. bridge important events to Character OS
```

注意：

- command 是离散输入；movement state 是连续状态。
- `keyDown W` 进入 `move.up pressed`，`keyUp W` 才退出。
- 多方向同时按下时合成向量，例如 W + D 是右上。

### 4. 输入状态模型

移动不要每次 keyDown 只移动一小步，而是维护按键集合。

建议新增：

```objc
@interface PETGameInputState : NSObject

@property (nonatomic, assign, readonly) BOOL upPressed;
@property (nonatomic, assign, readonly) BOOL downPressed;
@property (nonatomic, assign, readonly) BOOL leftPressed;
@property (nonatomic, assign, readonly) BOOL rightPressed;
@property (nonatomic, assign, readonly) CGVector movementVector;

- (void)applyCommand:(PETGameCommand *)command;
- (void)resetTransientInputs;
- (void)clearAllInputs;

@end
```

合成规则：

```text
up    -> y + 1
down  -> y - 1
left  -> x - 1
right -> x + 1
```

如果 `x` 和 `y` 同时不为 0，需要归一化，避免斜向移动更快。

### 5. GameCommand 类型枚举

建议先不用真实 enum 强绑全部玩法，使用字符串常量更利于配置和后续插件。

首批常量：

```objc
extern NSString * const PETGameCommandMovePressed;
extern NSString * const PETGameCommandMoveReleased;
extern NSString * const PETGameCommandSkillCast;
extern NSString * const PETGameCommandSkillCancel;
extern NSString * const PETGameCommandUltimateCast;
extern NSString * const PETGameCommandPause;
extern NSString * const PETGameCommandResume;
```

方向常量：

```objc
extern NSString * const PETGameDirectionUp;
extern NSString * const PETGameDirectionDown;
extern NSString * const PETGameDirectionLeft;
extern NSString * const PETGameDirectionRight;
```

来源常量：

```objc
extern NSString * const PETGameCommandSourceKeyboard;
extern NSString * const PETGameCommandSourceMouse;
extern NSString * const PETGameCommandSourceTouch;
extern NSString * const PETGameCommandSourceRuntime;
extern NSString * const PETGameCommandSourceDebug;
```

### 6. GameEvent 类型枚举

首批事件：

```objc
extern NSString * const PETGameEventMoveStarted;
extern NSString * const PETGameEventMoveChanged;
extern NSString * const PETGameEventMoveEnded;
extern NSString * const PETGameEventSkillRequested;
extern NSString * const PETGameEventSkillCastStarted;
extern NSString * const PETGameEventSkillFailed;
extern NSString * const PETGameEventSkillCooldownReady;
extern NSString * const PETGameEventResourceChanged;
extern NSString * const PETGameEventUltimateVideoStarted;
extern NSString * const PETGameEventUltimateVideoFinished;
```

事件结构：

```objc
@interface PETGameEvent : NSObject

@property (nonatomic, copy, readonly) NSString *eventType;
@property (nonatomic, copy, readonly) NSString *petIdentifier;
@property (nonatomic, copy, readonly) NSString *source;
@property (nonatomic, strong, readonly) NSDate *timestamp;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *context;

@end
```

### 7. Presentation Cue 类型

不要让 movement 或 skill 直接调用 `PETPetWindow`。

逻辑层产出 cue：

```objc
@interface PETGamePresentationCue : NSObject

@property (nonatomic, copy, readonly) NSString *cueType;
@property (nonatomic, copy, readonly) NSString *petIdentifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *payload;

@end
```

首批 cue：

```text
presentation.moveWindow
presentation.playAnimation
presentation.playVFX
presentation.playAudio
presentation.playVideo
presentation.showFloatingText
presentation.setFacing
presentation.lockInput
presentation.unlockInput
```

`PETGamePresentationBridge` 再把 cue 转成实际 AppKit / Metal / AVFoundation 操作。

### 8. 移动组件规格

```objc
@interface PETMovementComponent : NSObject

@property (nonatomic, assign) CGPoint position;
@property (nonatomic, assign) CGVector velocity;
@property (nonatomic, assign) CGFloat maxSpeed;
@property (nonatomic, assign) CGFloat acceleration;
@property (nonatomic, assign) CGFloat deceleration;
@property (nonatomic, copy) NSString *facingDirection;
@property (nonatomic, copy) NSString *movementState;
@property (nonatomic, assign, getter=isLocked) BOOL locked;

@end
```

默认参数：

```text
maxSpeed: 220 pt/s
acceleration: 1400 pt/s^2
deceleration: 1800 pt/s^2
movementState: idle
facingDirection: right
```

移动状态判断：

```text
locked == YES -> locked
speed == 0 -> idle
speed < maxSpeed * 0.65 -> walk
speed >= maxSpeed * 0.65 -> run
```

动画映射：

```text
idle -> profile resolvedAnimationStateForBehaviorState:@"idle"
walk -> "walk" if exists, otherwise "running" or "idle"
run  -> "running" if exists, otherwise "walk" or "idle"
locked -> keep current skill animation
```

### 9. 屏幕边界规则

桌宠的移动边界应以屏幕 visible frame 为准，不要覆盖菜单栏和 Dock。

规则：

- 获取当前窗口中心所在屏幕
- 使用该屏幕 `visibleFrame`
- 根据宠物窗口尺寸 clamp origin
- 多显示器时允许从一个屏幕移动到另一个屏幕
- 如果宠物跨屏，优先用窗口中心点判断所属屏幕

边界事件：

```text
game.movement.hitBoundary.left
game.movement.hitBoundary.right
game.movement.hitBoundary.top
game.movement.hitBoundary.bottom
```

### 10. 数值组件规格

```objc
@interface PETStatBlock : NSObject

@property (nonatomic, assign) NSInteger level;
@property (nonatomic, assign) double hp;
@property (nonatomic, assign) double maxHp;
@property (nonatomic, assign) double mp;
@property (nonatomic, assign) double maxMp;
@property (nonatomic, assign) double attack;
@property (nonatomic, assign) double defense;
@property (nonatomic, assign) double magicAttack;
@property (nonatomic, assign) double magicDefense;
@property (nonatomic, assign) double speed;
@property (nonatomic, assign) double critRate;
@property (nonatomic, assign) double critDamage;
@property (nonatomic, assign) double energy;
@property (nonatomic, assign) double maxEnergy;

- (NSDictionary<NSString *, id> *)serializedState;
- (void)restoreFromSerializedState:(NSDictionary<NSString *, id> *)state;

@end
```

默认回复：

```text
mpRegenPerSecond: 2
energyRegenPerSecond: 0
energyOnBasicSkill: 8
energyOnSpecialSkill: 14
```

### 11. 技能运行时规格

`PETSkillDefinition` 是配置；`PETSkillRuntime` 是运行状态。

```objc
@interface PETSkillRuntime : NSObject

@property (nonatomic, strong, readonly) PETSkillDefinition *definition;
@property (nonatomic, copy, readonly) NSString *phase;
@property (nonatomic, assign, readonly) NSTimeInterval phaseElapsed;
@property (nonatomic, assign, readonly) NSTimeInterval cooldownRemaining;

- (BOOL)canCastWithStats:(PETStatBlock *)stats reason:(NSString **)reason;
- (NSArray<PETGamePresentationCue *> *)startCastWithStats:(PETStatBlock *)stats;
- (NSArray<PETGameEvent *> *)tickWithDeltaTime:(NSTimeInterval)deltaTime stats:(PETStatBlock *)stats;
- (void)cancelWithReason:(NSString *)reason;

@end
```

阶段推进：

```text
checking:
  validate resources / cooldown / movement lock

casting:
  play cast animation
  after castTime -> active

active:
  emit hit / damage / vfx
  after activeTime -> recovery

recovery:
  keep input partially locked
  after recoveryTime -> cooldown

cooldown:
  cooldownRemaining decreases
  when 0 -> ready
```

### 12. 技能失败原因

统一失败原因，方便 UI、debug 和 Character OS 记忆。

```text
cooldown
notEnoughMP
notEnoughEnergy
movementLocked
stateLocked
missingDefinition
missingAnimation
missingVideo
interrupted
invalidTarget
```

失败事件上下文：

```json
{
  "skillId": "ultimate_001",
  "reason": "notEnoughMP",
  "requiredMP": 60,
  "currentMP": 24
}
```

### 13. 大招视频状态机

大招 MP4 不应该只是“播一下视频”，它需要参与技能生命周期。

```text
ultimate requested
  -> validate resource
  -> consume MP/energy
  -> lock movement
  -> play startup animation
  -> show video overlay
  -> wait video completion
  -> apply ultimate result
  -> hide video overlay
  -> unlock movement after recovery
  -> cooldown
```

视频 cue：

```json
{
  "cueType": "presentation.playVideo",
  "name": "ultimate_001.mp4",
  "payload": {
    "mode": "overlay",
    "blocksMovement": true,
    "blocksSkillInput": true,
    "allowsCancel": false,
    "zPosition": "abovePet",
    "onFinishEvent": "game.ultimate.videoFinished"
  }
}
```

首期 overlay 策略：

- 在宠物窗口上方创建同尺寸或更大尺寸的 borderless window
- 背景透明或黑底可配置
- `AVPlayerLayer` 播放 mp4
- 播放结束后关闭 overlay window
- 如果宠物被隐藏 / 删除 / app 退出，主动 stop player

### 14. Character OS 桥接协议

游戏引擎向语义运行时回写时，不直接操作 emotion / memory，而是继续走 actionKey。

建议映射：

```text
game.move.started -> gameplay.move
game.skill.castStarted -> gameplay.skill.cast
game.skill.failed.cooldown -> gameplay.skill.blocked
game.skill.failed.notEnoughMP -> gameplay.resource.low
game.ultimate.videoStarted -> gameplay.ultimate.perform
game.ultimate.videoFinished -> gameplay.ultimate.finish
game.state.recovered -> gameplay.recover
```

桥接方法可以在 `PETGameSession` 内部调用：

```objc
- (void)bridgeEventToCharacterRuntime:(PETGameEvent *)event {
    NSString *actionKey = [self actionKeyForGameEvent:event];
    [self.runtimeController recordActionKey:actionKey
                                    context:event.context];
}
```

需要避免循环：

- `Character OS -> runtimeBehavior command -> GameEngine`
- `GameEngine -> game event -> Character OS`

如果 context 里有 `originRuntimeEventId`，桥接时要防止同一事件反复进入。

### 15. 持久化结构

建议游戏状态独立保存在 pet record 中，不混入 `PETCharacterSnapshot`。

```json
{
  "gameStateVersion": 1,
  "position": {
    "x": 120,
    "y": 240
  },
  "velocity": {
    "dx": 0,
    "dy": 0
  },
  "facingDirection": "right",
  "movementState": "idle",
  "stats": {
    "level": 1,
    "hp": 100,
    "maxHp": 100,
    "mp": 80,
    "maxMp": 80,
    "energy": 0,
    "maxEnergy": 100
  },
  "skills": {
    "basic": {
      "phase": "ready",
      "cooldownRemaining": 0
    },
    "ultimate_001": {
      "phase": "cooldown",
      "cooldownRemaining": 8.2
    }
  }
}
```

恢复策略：

- 位置恢复，但要重新 clamp 到当前屏幕。
- 速度恢复为 0，避免启动后瞬移。
- 正在 casting / active / video 的技能恢复为 ready 或 cooldown，首期不要恢复半截大招。
- 冷却可以恢复剩余时间，也可以根据离线时间扣减。

### 16. Debug 面板建议

管理窗口后续可以加一个 “Game” 区域。

显示：

- HP / MP / Energy
- position / velocity
- movementState / facing
- activeSkill / skillPhase
- cooldowns
- lastGameEvent
- input pressed set

操作：

- 恢复满 HP/MP
- 触发 basic
- 触发 ultimate
- 清空冷却
- 暂停 / 恢复 game engine
- 导出当前 game state JSON

这个面板会极大降低后续调技能、动画、MP4 的成本。

## 首批代码文件清单

P0 建议一次只加这些文件：

```text
DesktopPet/GameEngine/Core/PETGameCommand.h
DesktopPet/GameEngine/Core/PETGameCommand.m
DesktopPet/GameEngine/Core/PETGameEvent.h
DesktopPet/GameEngine/Core/PETGameEvent.m
DesktopPet/GameEngine/Core/PETGameSession.h
DesktopPet/GameEngine/Core/PETGameSession.m
DesktopPet/GameEngine/Core/PETGameEngine.h
DesktopPet/GameEngine/Core/PETGameEngine.m
DesktopPet/GameEngine/Core/PETGameTickDriver.h
DesktopPet/GameEngine/Core/PETGameTickDriver.m
```

P1 再加：

```text
DesktopPet/GameEngine/Input/PETGameInputState.h
DesktopPet/GameEngine/Input/PETGameInputState.m
DesktopPet/GameEngine/Input/PETKeyboardInputRouter.h
DesktopPet/GameEngine/Input/PETKeyboardInputRouter.m
DesktopPet/GameEngine/Movement/PETMovementComponent.h
DesktopPet/GameEngine/Movement/PETMovementComponent.m
DesktopPet/GameEngine/Movement/PETMovementSystem.h
DesktopPet/GameEngine/Movement/PETMovementSystem.m
DesktopPet/GameEngine/Presentation/PETGamePresentationCue.h
DesktopPet/GameEngine/Presentation/PETGamePresentationCue.m
DesktopPet/GameEngine/Presentation/PETGamePresentationBridge.h
DesktopPet/GameEngine/Presentation/PETGamePresentationBridge.m
```

P2 再加：

```text
DesktopPet/GameEngine/Combat/PETStatBlock.h
DesktopPet/GameEngine/Combat/PETStatBlock.m
DesktopPet/GameEngine/Combat/PETDamageCalculator.h
DesktopPet/GameEngine/Combat/PETDamageCalculator.m
DesktopPet/GameEngine/Skill/PETSkillDefinition.h
DesktopPet/GameEngine/Skill/PETSkillDefinition.m
DesktopPet/GameEngine/Skill/PETSkillRuntime.h
DesktopPet/GameEngine/Skill/PETSkillRuntime.m
DesktopPet/GameEngine/Skill/PETSkillSystem.h
DesktopPet/GameEngine/Skill/PETSkillSystem.m
```

P3 再加：

```text
DesktopPet/GameEngine/Presentation/PETVideoCue.h
DesktopPet/GameEngine/Presentation/PETVideoCue.m
DesktopPet/GameEngine/Presentation/PETUltimateVideoOverlayController.h
DesktopPet/GameEngine/Presentation/PETUltimateVideoOverlayController.m
```

## 第一版提交边界

第一版代码提交建议只做到：

- 编译通过
- game engine 可以注册宠物
- tick 正常运行
- command / event 模型可用
- 不接键盘
- 不移动窗口
- 不接技能

第二版再做键盘移动。这样风险最低，因为现有桌宠窗口和 Character OS 已经有不少逻辑，不适合一次性把输入、移动、技能、视频全部塞进去。
