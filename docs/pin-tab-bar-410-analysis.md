# Threads 410 固定底栏调查

## 失效原因

原 PinTabBar group 只处理 `BCNLucentTabBarCoordinator` 和 iOS 26 原生 tab controller。410 使用旧的 `BCNScrollableHeaderCoordinator`，不经过这两条链。旧目录中的 `test-pinned-tab.py` 是防止恢复早先全局 transform/layout 补丁的回归约束，并不是 410 固定底栏已经生效的证据。

## 本地二进制证据

目标为本地 `/private/tmp/Threads410.bin`，沿用已有 IDA 分析库。下列地址只记录调查结果，不写入插件。

| 入口 | 410 地址 / 签名 | 调用证据 |
| --- | --- | --- |
| `BCNRootViewController moveDownTabBarToOffset:percentTransitioned:` | `0x10054783c`，`v32@0:8d16d24` | ObjC thunk 调 Swift worker `0x10043bb80` |
| `BCNRootViewController setBarButtonAlpha:` | `0x1016c8f04`，`v24@0:8d16` | 主滚动/收尾动画独立调用，用于底栏按钮淡出 |
| 主首页滚动状态同步 | `0x100413844` | 读取 header coordinator 的 `tabBarOffsetAmount` 和 `tabBarOffsetPercent`，经 `objc_msgSend` 调上述两个 root 方法 |
| 主首页收尾动画 block | `0x101dc0f3c` | 同样经 ObjC 派发更新位置与按钮 alpha |
| `IGCollapsibleNavigationCoordinator` 折叠输出 | `0x100de84d0`，经 thunk `0x10313c0f4` | `scrollViewDidScroll:` / `scrollViewDidEndScrolling:` / `setCollapsed:` 的共享折叠逻辑同样调用上述两个 root 方法 |

`0x10043bb80` 仅写入底栏滚动百分比、垂直平移和上次位移，并更新底栏按钮。`setBarButtonAlpha:` 的 selector 直接交叉引用来自上述滚动输出与动画，未发现用于 push/modal/profile 离场的调用。

不拦旧 header coordinator 的整个 `scrollViewDidScroll:`：它同时负责 header 的拉伸/滚动，而且个人页会绕过 ObjC thunk 直接调用 Swift worker。原生 `resetToDefaultState`、侧边菜单/导航恢复直接调用 root 的 Swift worker，应继续原样执行。

## 最小处理

- 保留原项目的 Lucent 路径。
- 只在 root 上两个真实原生 selector 都存在时安装 `LegacyPinTabBar`。没有客户端版本白名单或固定地址。
- 开关开启时，位置输出给原方法 `0, 0`，按钮透明度输出给原方法 `1`；保留原方法内的状态同步。
- 开关关闭时，两个原始调用及参数完整放行。
- 不 hook `IGTabBar`、布局、页面生命周期或可见性；不强制 `hidden=NO`，不在布局完成后补位。

## 456 复核与作用范围

两个 selector 的存在性 gate **也会在 456 成立**，不能把它描述为 410 版本专属 gate。它只保证不向缺少原生方法的类增加伪接口。复核目标为现存 IDA 数据库对应的 `/private/tmp/Threads456.bin`，SHA-256 为 `2ba76c8e47587b22d96868a97854f562d39a6c779560cb4b71b29b382b4b5396`，已与磁盘文件核对相同。

| 456 入口 | 地址 | 复核结果 |
| --- | --- | --- |
| root `moveDownTabBarToOffset:percentTransitioned:` | `0x10076eb40` | 两个 double 参数原样转发给 `tabBarImpl` 的 `BCNTabBarScrollPushing` witness +8 |
| root `setBarButtonAlpha:` | `0x103018c38` | alpha 转发给相同 `tabBarImpl` 的 witness +16 |
| 协议对象取得 | `0x10004a928` / `0x10007ef7c` | 从 root 的 `tabBarImpl` 做 `BCNTabBarScrollPushing` 协议转换；不改导航控制器可见性 |
| 首页同步 / 动画 | `0x10063f508` / `0x105240238` | 从旧 header coordinator 的 tab offset 字段，经 ObjC 消息输出位移和进度，语义与 410 相同 |
| 折叠导航滚动输出 | `0x102c45844` | `IGCollapsibleNavigationCoordinator` 的 scroll/end-scroll/setCollapsed 共享入口，经 `0x105920128` 输出位移、`0x105920188` 输出 alpha |
| 额外滚动进度路径 | `0x1037947a8` → `0x1015e705c` → `0x103818d00` | 起点同样读取 `BCNScrollableHeaderCoordinator.tabBarOffsetPercent`，再调用 moveDown selector；不是页面 push/modal 隐藏入口 |

456 的 root 方法内部是滚动协议转发，没有设置 `hidden`、改布局或执行 push/modal 的操作；查到的 alpha selector 代码调用来自上述折叠导航滚动输出。开启“固定底栏”后给这些滚动输出归零/取消淡出的语义与该功能一致，静态复核未发现与 456 原有 Lucent hook 冲突的证据。未改动原项目的 Lucent 两个滚动 hook。

这不是“456 行为绝对不受影响”的结论：当 456 使用旧滚动输出时，这两个 hook 会按开关参与处理。尚未进行 456 真机转场验收；开关关闭时的原样传参已由本机测试验证。

## 验证边界

`bash scripts/test-pin-tab-bar.sh` 已通过。它从生产代码抽取真实 Logos group，使用 internal generator 编译并执行 stub，验证启用/关闭/再次关闭时的参数、原方法调用次数和双精度 ABI；另检查未增加全局布局和可见性 hook。

上述为二进制静态调用链和本机 mock 验证。尚未验证手机上的首页滚动、首页与个人页切换、图片全屏退出后的底栏行为。
