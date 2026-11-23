# ThreadsPulse 本地修复与上游迁移维护指南

> 冻结日期：2026-11-20。对应代码/交付包：**1.31.0+16**。本文是维护与迁移账本，不是正式发布日志。源码实现、本机检查、历史设备反馈、当前包真机验收分别记录。

> 当前迁移见[第 11 节](#11-迁移到-v1311)。第 1–10 节保留 1.31.0+16 的冻结记录。

## 1. 对比基线

| 项目 | 冻结值 |
| --- | --- |
| 原项目 | `mumuisdog/ThreadsPulse` |
| 干净上游 | `../ThreadsPulse-upstream-20261119/`，本次确认 Git 工作树干净 |
| 上游 commit | `038d74022ee6df8ab1ac3062195c2a16a74d2d42` |
| commit 日期/标题 | `2026-11-18 21:33:19 +0800` / `Update Info.plist` |
| 上游源码版本 | `TPVersion.h` 的 `1.31.0`；上游 `control` 中 `1.0.0` 是模板值，不作为正式版本依据 |
| 当前维护主线 | `ThreadsPulse-410/`；目录名带 410，但保留新客户端原生/上游路径，不是只支持 410 |
| 当前本地版本 | `1.31.0+16`，`TPVersion.h` / `Makefile` / `control` / 两个对应 DEB 一致 |
| 重点客户端 | 本地 Threads 410 与 456；不由这两版推断所有未来版本 |
| 最低系统 | iOS 15.0；上游原本就声明 iOS15+，不能写成“新增 iOS16+ 支持” |
| 交付工具链 | Xcode 16.4 / iPhoneOS SDK 18.5 |

这是**本地冻结快照**，不是对 GitHub 实时最新版的断言。后续迁移先记录新上游 commit；不能混用其它旧工作目录、测试包里的代码或聊天中已经撤销的尝试。

编写本文前，全量源文件净差异为 **62 条：22 修改、34 新增、6 删除**。6 条删除是原 bundle 路径资源的迁移，不是删除五语功能。完整路径、原/当前 SHA-256 与大小保存在 [冻结差异清单](upstream-diff-1.31.0+16.json)。该清单排除 Git、构建缓存、生成头、dist/packages/build 等产物；冻结后仅编辑本文/清单、两份 README 的文档入口，以及通知分析文档的 expiry 边界说明。冻结清单中的 README/通知分析 hash 是本次文档编辑前值。

### 证据等级与表述

- **源码确认**：实际文件、调用点、开关及初始化存在。
- **静态链路**：本地二进制类/selector/ABI/调用链可对应；不是设备行为结果。
- **本机通过**：生产实现提取测试、fixtures 或 UIKit/UN stubs；不是服务器、播放器、系统合成器或推送验收。
- **历史设备反馈**：此前用户确认过具体行为；不自动扩大成 +16 全部客户端/设备通过。
- **待真机**：缺当前包对应目标场景的真实结果。通知正文复用尤其属于此项。

本次按源码实际差异由三个独立审查方向交叉梳理：主 hooks；作者/音乐/下载；UI/资源/通知。不能用审查通过代替真机验收。

## 2. 差异总账

每次升级都要对每行填写“保留 / 新上游已等价覆盖 / 有明确证据移除 / 待验证”，不得只看编译成功。

| ID | 相对原项目的净差异 | 主要文件 | 当前证据/限制 |
| --- | --- | --- | --- |
| F01 | 旧版广告插入回调与 410/456 同步广告共同投放入口 | `Tweak.x` | 静态链路 + Logos stub；反馈截图实际路径待动态确认 |
| F02 | concrete pasteboard 及 items/options 的旧版复制入口 | `Tweak.x` | 源码；本轮未重新 USB 复制验收 |
| F03 | 旧模块外链处理类，复用现有清理/外部浏览器逻辑 | `Tweak.x` | 源码；站内/外链设备回归待做 |
| F04 | 首页后台恢复、旧标签点击/长按和刷新委托兼容 | `Tweak.x` | 源码；四项开关组合待设备回归 |
| F05 | 旧滚动链固定底栏，保留上游 Lucent 路径 | `Tweak.x` | 410/456 静态 + Logos stub；转场待真机 |
| F06 | 旧已读发送签名和聊天室眼睛原生导航项接入 | `Tweak.x` | 源码；眼睛显示/可切换有历史反馈，不是防撤回开关 |
| F07 | 防撤回直达 delete applicator 的补充路径 | `Tweak.x` | 源码；与系统通知是两条链 |
| F08 | 410 新音乐附件解析、卡片与点按播放 | `TPMusicAttachment.*` / `TPMusicCompat.*` / `Tweak.x` | 解析 fixtures；当前音源/播放器待真机 |
| F09 | 作者资料旧版字段、请求/缓存/整组布局及防崩兼容 | `TPAuthorInfo.*` / `Tweak.x` | fixtures；地区有历史反馈，全部字段/速度待验 |
| F10 | 全屏媒体整 cell 长按入口与浮动按钮布局开销优化 | `Tweak.x`（沿用 TPUI 菜单） | 源码；实际全部媒体保存待回归 |
| F11 | iOS15 对 iOS16 VideoToolbox 转换 API 的保护和降级 | `TPDownloader.m` | 源码/现有包；不是所有 iOS15 HDR 转换均可用 |
| F12 | 截图隐藏 secure 容器生命周期/布局和视觉层接入 | `TPUI.*` / `TPCapsule.m` / `Tweak.x` | 本机 49 checks；系统截图/录屏待验 |
| F13 | 保留上游语言选项，五语内嵌单 dylib，二改署名链接 | `TPLocalization.m` / `resources/` / `TPSettingsViewController.m` | 5×346 项本机回归；Pulse 固定英文是上游既有行为 |
| F14 | 撤回通知翻译及 +16 受条件限制的原正文复用 | `ThreadsPulseNotifications.x` / `TPNotificationPrefs.*` / `TPPrefs.m` | 本机匹配/竞态/文件测试；**等待朋友真实推送测试** |
| B01 | arm64 Rootless / 真 arm64e RootHide、iOS15、双切片解码库 | `Makefile` / `control` / `vendor/` / codec 脚本 | 既有 +16 双包已实解包，本轮未重打包 |
| B02 | 单 target/单 dylib、双进程 Filter、资源生成/注入输入调整 | Filter / 构建脚本 / workflows | 本地双包已查；Ubuntu CI、通知 appex 注入不算已验 |

`TPURLCleaner.m`、`TPHUD.m`、`TPAuthorStatsViewController.*`、`TPSideloadFix.m`、`TPUpdateChecker.m` 等与冻结上游相同。`NoAutoplay`、`NoTyping`、`BlockAnalytics`、推荐隐藏、App 截图检测拦截等组无相关净差异，不能写成本地重新实现或全部已实测适配。修改 `Tweak.x` 不代表其中每个功能都由本地修复。

## 3. 主 hooks：F01–F07

### F01 广告

原 Ads hooks 全保留；`TPKeyBlockAds = tp_block_ads`。补两个入口：

1. `_TtC15IGBCNAdsManager37BCNMainFeedAdsInsertionSurfaceHandler` 的 `adInsertionHandler:shouldTryToInsertSponsoredItem:atInsertionIndex:focusedIndex:validationResultString:insertionContext:`。410 需要 `validationResultString`，两个 index 为 `long long`，不能误抄成上游较短 selector。
2. `IGAdInsertionHandler` 的 `deliverSponsoredItemsWithPosts:deliveryContext:containerModule:surfaceExtraLoggingDicts:extraLoggingDict:requestMetadata:adRequestExtraInfo:acpContext:`。

第二个方法两版 encoding 均为 `v80@0:8@16Q24@32@40@48@56@64@72`：返回 void，`deliveryContext` 是 unsigned 64-bit，其他七个业务参数是对象。开关开提前返回；关闭完整传参 `%orig`。不得截断 context 或漏参数。

同步投放会直接走 Swift 实现，绕开 manager ObjC wrapper/原 surface 回调，但仍通过 ObjC 派发到第二个共同入口。旧 `adPlatformDidDeliverSponsoredItem:atAdRequestIndex:` 在两个本地二进制中为空实现，不算可靠兜底。原 fetcher/manager/surface hooks 和 ctor `%init(Ads)` 不能丢；不能给共同方法加“只 410”白名单。

本机 `test-ad-delivery.sh` 只验证开关往返、原调用次数、对象参数和高位64-bit context。反馈截图版本未知，未证明截图广告就是此路径。地址仅供分析，不写生产代码。详见 [广告链路](ads-410-456-analysis.md)。

### F02 复制链接移除追踪码

`Tracking` group / `TPKeyStripTracking = tp_strip_tracking`：

- 新增 `UIPasteboard -setItems:options:`：逐 item 复制字典；URL 用 `cleanURL:`，字符串用 `cleanString:`，其他类型保留，options 原样传递。
- 新增 `_UIConcretePasteboard -setURL:`、`-setString:`、`-setItems:`。旧版 concrete 写入不保证经过基类，因此只有基类 hook 会漏“复制链接”。这层复用清理器内部开关判断，不是始终清理。
- 每条写路径记录 `gTPOwnPasteboardChange = changeCount`，包括原 items 路径；`TPCheckClipboard` 据此跳过本 App 刚写的链接，避免复制后自己触发提示/自动打开。

**`TPURLCleaner.m` 没改。**xmt/slof、igsh*、utm_* 等清理和跳转展开沿用上游，不能写成此次新增算法。原 `UIActivityViewController`、`IGExternalURLIntentTarget`、`UIApplication openURL` 处理保留。

迁移检查四类 setter、开/关、非追踪业务参数与其他 UTI 保留，以及复制后不自触发剪贴板打开。当前无专用生产抽取测试，本轮只有源码核对。

### F03 旧版外链模块

`ExternalBrowser` / `TPKeyExternalBrowser = tp_external_browser`：新增旧类 `_TtC14BCNLinkHandler18BCNLinkHandlerImpl`：

- `handleLinkWithURL:containerModule:presenter:`。
- `handleLinkWithURL:rawURL:linkProtectionMetadata:mediaPk:mediaAuthorPk:linkTapLocation:containerModule:sponsoredPostInfo:rankingInfoToken:presenter:contextualLoggingParameters:clickSource:`。

上游 `_TtC20BCNLinkHandlerPlugin18BCNLinkHandlerImpl` 路径继续保留；新版长签名还带 `animationViewProvider:`，不可混淆。均复用 `TPOpenExternally → TPExternalBrowserURL → TPURLCleaner`。站内 Threads/子域和非 HTTP(S) 交原生，外部浏览器开关与去追踪开关独立。

### F04 首页四项与旧 Home 入口

| 设置 | key | 需要保留的处理 |
| --- | --- | --- |
| 保留动态位置 | `TPKeyKeepFeed / tp_keep_feed`，期限 `tp_keep_feed_limit` | 原 warm-start/foreground/刷新阈值 + 新 root warm-start |
| 禁用下拉刷新 | `TPKeyNoPullRefresh / tp_no_pull_refresh` | 原主 feed 滚动 + 新 IGRefreshControl 委托 |
| 点首页不回顶 | `TPKeyTabNoScrollTop / tp_tab_no_scroll_top` | 主页中部重选判断及旧按钮入口 |
| 点首页不刷新 | `TPKeyTabNoRefresh / tp_tab_no_refresh` | 主页顶部重选判断及旧按钮入口 |

保留位置：新增 root `_TtC21BCNRootViewController21BCNRootViewController -didWarmStartWithTimeSinceBackground:`，`TPShouldKeepFeed` 为真时传0，否则原值。限时规则仍是0=10分钟、1=30分钟、其他=不限；后台时间 observer、10秒决策缓存、原 main feed/BCNAppViewController/IGFeedRefreshInstructionsStore 路径不删，不伪造冷启动。

旧点击：`TPIsLegacyHomeButton` 沿 superview 找 `IGTabBar.buttons.firstObject`，只识别 Home；root `didTapTabBarButton:` 使用 `TPTabSelectSuppressed / TPShouldBlockHomeReselect`。必须保留 `gTPMainFeedClass` 初始化、`viewDidAppear` 的 `gTPMainFeedVC` 记录、主页 scrollView/顶部偏移判定。中部只按 noScrollTop，顶部只按 noRefresh，不能把两个开关合并为全部吞点击。

旧刷新：新增 `IGRefreshControl -scrollViewDidScroll`、`-scrollViewDidEndDragging`，经 `TPBlockMainFeedPull` 找真实 `_scrollView`，只处理主 feed 且 `refreshState=0`，必要时夹回 top；不吞正在执行刷新收尾，也不影响其他列表。

长按 Home 开设置属于独立 `TPKeyHomeLongPress / tp_home_long_press`，不是四项之一。root `didLongPressTabBarButton:` 只处理第一按钮；Began 抑制选中10秒、触感并开设置，结束/取消/失败缩为0.6秒防松手点击。保留上游 Lucent 和 `LegacyTabFallback` 一秒点击窗口；后者由 `TPMarkLegacyTabTap` 懒安装，不是全局 UIScrollView 永久不滚。

本组没有专用本机脚本，不把菜单存在/编译成功写成四项已验收。

### F05 固定底部标签栏

`TPKeyPinTabBar / tp_pin_tab_bar`。原 `PinTabBar` 的 Lucent/iOS26 路径保留。新增 `LegacyPinTabBar`，使用 root 两个原生方法：

- `moveDownTabBarToOffset:(double)offset percentTransitioned:(double)percent`：`TPKeyPinTabBar` 开时 `%orig(0.0, 0.0)`；关时原样。
- `setBarButtonAlpha:(double)alpha`：开时 `%orig(1.0)`；关时原样。

ctor **同时确认两个 selector 存在**才安装。保留原实现内部状态同步，不直接 return。这个结构 gate 在456也成立，不是410专属白名单；不能说456完全不参与改动。

不全局 hook IGTabBar 的 hidden/transform/layout，不拦整个 header coordinator 滚动，不强制个人页/push/modal 可见性；此前导致底栏问题的广域方案不能带回。`test-pin-tab-bar.sh` 测双精度 ABI/开关原参/禁止广域补丁；首页/个人页、push/modal、全屏退出仍待真机。详见 [底栏分析](pin-tab-bar-410-analysis.md)。

### F06 眼睛与已读：保持原作者语义

眼睛控制**当前聊天室是否允许显示 Seen**，不控制防撤回。`TPKeyNoSeen / tp_no_seen`、`TPKeySeenOnReply / tp_seen_on_reply`；每聊天室例外保存在 standardUserDefaults 的 `tp_seen_allowed_chats`。

| 状态 | 实际行为 |
| --- | --- |
| NoSeen 关闭 | 放行真实已读，眼睛隐藏 |
| NoSeen 开，未加入允许列表 | mark-read builder 用已发送 watermark 或0替换新 timestamp |
| eye + 主题强调色 | 当前聊天室允许 Seen；切入此状态会 `TPSendSeenNow` |
| eye.slash + secondaryLabelColor | 隐藏该聊天室后续 Seen；不能收回已经发出的已读 |
| 隐藏 Seen 且 SeenOnReply 开 | 真实 outgoing payload/update 触发一次补发，不把聊天室永久加入允许列表 |

主题强调色可能默认红色，但换主题后不保证仍红。上游已有“此聊天室显示/隐藏 Seen”toast、haptic 和 accessibilityValue 保留；移除的是此前误接防撤回时增加的那套 toast。

旧版发送链：`TPHoldMessageUntilSeen` 抽出原上游 send service 顺序逻辑；增加 `_TtC25BCNSlideMDCoreSendService25BCNSlideMDCoreSendService -sendMutationWithAppDataModel:offlineThreadingId:optimisticImages:`，并保留上游带 `syncGroupId:` 方法。新增 `BCNSlideOutgoingMessagePayload` 旧 init：`initWithOfflineThreadingId:threadFbid:senderFbid:sendDate:content:navChain:forwardedMessageId:`；长 init/update payload 仍在。

发送依赖 `TPThreadKey / TPChatShowsSeen / TPAllowSeenAfterReply / TPTagMarkRead / PNGraphQLQueryBuilder / PNPandoGraphQLService / TPSendSeenNow / TPRecordWatermark / TPReleaseHeldMessages`。使用已捕获原生服务/参数，不另造请求。上游的按线程延后发送、0.15秒响应后释放、失败立即释放、0.8秒保底仍保留；不是本地新发明发送顺序。

眼睛接入：`TPChatViewControllerOf` 支持 navigationController.visibleViewController；`TPSeenBarItems` 只在 `BCNSlideMessageListNavBarTitleView` **没有** `$__lazy_storage_$_moreButton` 时走旧 fallback。hook `UINavigationItem setRightBarButtonItems:animated:` 在写列表时合入36×36 item，`setTitleView:` 兼容 title 晚到，关联去重；关闭 NoSeen 只移除自己的 item。title 的 `didMoveToWindow` 离窗清 `gTPOpenChatShowsSeen`；入窗且存在关联旧 bar item、有效 chat key 时，同步 `gTPOpenChatKey / gTPOpenChatShowsSeen` 并更新图标。新版有 moreButton 仍走原布局，不双重添加。独立图标视图由 `TPSetSeenButtonState` 更新并接截图保护，外部 UIButton 保持点击和无障碍。

**不迁回未读数据库/红点强改。**用户已确认关闭“不显示已读”后原生可清红点并取消该修复；当前没有附加 inbox/thread 强写。眼睛显示/两种状态有历史用户反馈，本轮未做最终 +16 已读服务端全链验收，也无专用本机测试。

### F07 App 内防撤回

`KeepUnsent` / `TPKeyKeepUnsent = tp_keep_unsent`。保留 `MDCoreDeltaApplyingBridge -mutationCommandsForDeltaWithRequestedState:currentUserFbid:shouldFallbackToInboxResnapshotOnDeltaHandlingError:`；bridge 仅在 `_wrappedTypeName` 为 NSString 且包含 `DeleteMessage` 时过滤，其他返回原结果。提取 `TPFilterUnsentCommands`，再覆盖 `MDCoreDeleteMessageDeltaApplicator -mutationCommandsForDelta:authoritativeThread:requestedState:currentUserFbid:` 的直达路径；该入口已由类型限定，不另需字符串 gate。

仅识别 `MDCoreDeltaApplicationResult` 及其 `_mutationCommands_commands`。`TPDeleteCommandPayload` 经 `matchUpsertCommand:deleteCommand:updateCommand:deleteAllCommand:deleteFolderCommand:` 判断 delete，其他命令保留；真过滤且支持 `mutationCommandsWithCommands:` 才重建结果，否则返回原结果。开关关时原样放行。

`TPRememberUnsent` 根据 `messageAndThreadIds` 去重，`tp_unsent_messages` 最多500条，刷新弱追踪 cells；标注依赖 `TPReadSwiftString / TPMessageIdOfCell / TPUpdateUnsentLabel`。关闭后历史 Unsent 标注保留是上游行为。此路径没有本轮专用脚本，通知测试不能代替 App 内删除命令验收。

## 4. 作者资料、音乐与媒体：F08–F11

### F08 音乐附件：完整迁移链

新增四文件 `TPMusicAttachment.h/.m`、`TPMusicCompat.h/.m`。`MusicCompat` **仅 major=410 安装**：`IGMedia -updateWithDictionary:` 后 `TPMusicUpdateMedia`；`_TtC21BCNFeedNestedPostCell34BCNFeedDeletedQuotedAttachmentCell -layoutSubviews` 后 `TPMusicLayoutCell`。456等保持原生。

数据链 `text_app_music_info → music_consumable_video → audio_metadata → audio_asset`；要求可消费、标题和 DASH。读取 `display_title.text`、可选 `display_artist.text`、`dash_manifest`、`audio_start_time_in_ms`；有效正有限毫秒转秒，否则0。NSXMLParser 禁外部实体，只取音频节点首个**绝对 HTTPS 单文件 BaseURL**，保留 XML 解码后的签名参数。相对地址/分片 manifest 不支持，不绕过版权/地域标记。

partial update 缺 key 不清附件，明确 unavailable/invalid 才清。复用 cell 时清旧 button/attachment；旧按钮仍位于当前 card 内时恢复该 card 的原 label。原 tombstone 卡片内展示歌名/艺人/play.circle；点按 `TPMusicPlayerController : AVPlayerViewController`，AVPlayer ready、页面可见/前台才 seek 起点并播放，退出/后台暂停，清理 KVO/通知。依赖 AVKit、AVFoundation/CoreMedia、TPUI/TPHUD/TPLocalization/TPDownloader 安全 ivar 读取。

解析测试不是实际 CDN/音频/播放器 UI 验收。此前出现“旧修复可播、移植后丢失”，后续必须把模型 hook、cell hook、410 ctor gate、四文件和 AVKit 一起核销，不能只迁界面。

2026-11-22 真机动态分析（`docs/music-attachment-410-analysis.md`）：当前账号拿到的 `text_app_music_info` 已被版权/地域标记裁剪成 `is_available_for_consumption:false` + `error_code:MUSIC_RIGHTS_NOT_LAUNCHED_COUNTRY`，`music_consumable_video` 内不再带 `audio_metadata/audio_asset/dash_manifest`，客户端没有可播放 URL。解析改为在 `text_app_music_info` 内递归找 `dash_manifest`、`display_title`/`title` 兜底、缺失 availability 不判死，并新增 `+[TPMusicAttachment diagnosticsForDictionary:]` 与 `scripts/probe-music-payload.py` 把“服务端裁剪”和“解析失败”区分开。

### F09 作者资料：数据、调度、显示与防崩

保留上游显示开关、资料统计和原生 Bloks 请求体系。`AuthorInfo` group、`TPAuthorInfo.*`、header高度/布局/pk关联、原生 session/context 捕获要作为整组迁移。`enabled` 是本功能及子字段门控，不是插件总开关。

**目标绑定**：`TPHeaderPk` 优先 `viewModel.user.pk` 的数字字符串，后备 `profilePictureView.userPk` 的 Swift Optional String；410 `TPHeaderJoinInfo` 再核对原生 user.pk 与目标一致。标题兼容 `titleLabel` 和 `$__lazy_storage_$_titleLabel`；无新版 content class 时用 cell 本身。`TPHeaderVisible` 检查 window、祖先 hidden/alpha/裁剪，仅实际可见且无缓存的作者入队。

**上下文来源**：`IGUserSession -initWithUser:creationReason:deviceSession:`、`PNPandoGraphQLService -initWithService:`、`PNPandoGraphQLConsistency` 三种 init、`IGApplicationAnalytics -handleApplicationDidBecomeActive`、`BKContext -initWithObjectSet:flags:`、`BKSharedAsyncActionDataFetcher`、`IGBloksAsyncActionHandler` 原 init及新增 `initWithAppID:params:props:context:successHandler:errorHandler:`、`BKDataFetchGraphQL` RootApp/RootAction/Components。`noteUserSession:` / `noteService:kind:` 就绪后主队列立即 pump。

**请求兼容**：优先 `BKSharedAsyncActionDataFetcher +fetchWithObjectSet:appID:params:timeoutOverride:successHandler:errorHandler:callbackQueue:`，appID `com.bloks.www.text_post_app.about_this_profile_async_action`。只在类/selector 不存在时，用 `BKDataFetchGraphQL +fetchRootAppWithObjectSet:appID:params:purpose:cacheTTL:successHandler:errorHandler:callbackQueue:`，appID `com.bloks.www.text_post_app.about_this_profile_bottom_sheet`、`target_user_id` NSNumber、`referer_type=TextPostAppProfileOverflow`、purpose1、cacheTTL3600。不是网络失败后无限改 API 重试。

success block 签名 `(id result, id status)`，error `(id error)`；不恢复旧 `TPCollectArgs` 裸指针猜任意 Foundation 对象方案。`TPAsObject` 仍用于有界 Swift 桥接等用途。合成 BKObjectSet 的上游能力仍保留：已捕获 session/Pando/consistency/analytics、IGSessionContext subtype0..2、30/60/120秒重试节流，必要时等原生上下文；不是本地全部重写。

**解析字段**：`TPHarvestStrings` 支持 Foundation/AttributedString/JSON NSData/数字标记/容器及有界 ObjC ivar，剥离 `for (;;);`；上限6000节点、容器/JSON深度400、一般ObjC对象深度14、NSData小于4MB，跳过 UIKit/session/context 图。`TPStateValues` 识别 `THREADS_ABOUT_THIS_PROFILE:<name>`。

| 缓存字段 | 当前来源/规则 |
| --- | --- |
| `location` | 地区行/Bloks状态，本地映射国旗 |
| `hidden` | country visibility=0 / Not shared 等明确语义，清地区 |
| `joined` | Joined/加入时间行或状态；410以 `IGUser.textPostAppJoinedTime` 补缺，秒/毫秒转本地化公历年月 |
| `number` | Joined同一行/受控分隔；410先 `textPostAppJoinerNumberLabel`（最长24字），再正数 `textPostAppJoinerNumber`，格式化 `#` + 千分位 |
| `u` / `n` | username / display name；头部 handle 仅补 username 字段 `u`，不补 `n` |
| `v` / `x` | 缓存结构版本/过期时间，不是用户信息 |

支持 `July 2023 · #12,345,678`、跨 span 明确分隔、100M+及中文单位；避免取下一行数字/颜色/id。时间数字仅10/13位并排除编号状态。`TPIsNewAccountAtDate` 按公历年月判断当前月至前2个月（差0–2），排除未来/无效月；原默认动物用户名规则保留。

**开关边界**：`tp_author_info` 且 location/joined/new 至少一个开才 enabled，单独 number/default-name 不激活。字段键为 `tp_author_location`、`tp_author_joined`、`tp_author_new`、`tp_author_own_line`、`tp_author_join_number`、`tp_author_default_name`。编号需要 Joined 开且有 joined；窄行 compact level1可省编号/国家全名，level2只留旗帜，不能保证所有宽度显示全部字段。

**整组合并/无空行**：请求前按pk捕获410原生 joined/number；`TPHandleResult` 先解析网络，再补缺，**一次 TPStore**。`TPBadgeText` 由同一缓存生成字段/NEW/默认名的 attributed label；不是先发布地区再逐字段发通知。`extraHeaderHeightForPk:` 只在实际可显示时留行。`IGListAdapter` 通过 `kTPHeaderRowsKey / kTPHeaderPksKey` 绑定item，复用非header清理；`TPInvalidateAuthorHeader` 定位 section执行 `invalidateLayoutForSectionController:completion:`。增加行高后内层header仍自然高度、顶部对齐；有限frame内测文字，不调用自定义Swift view的无界普通测量。

整组意味着**同一次拿到的可用字段合并显示**，不是保证返回齐全或无限等全部字段。未捕获原生user时仍可能只返回地区；不能把解析支持写成真实数据齐备承诺。

**提速/缓存**：410最小请求启动间隔1.5→0.75秒，其他版1.5秒，timer加0.05秒；**仍只有一个 inflight，没有新增并发**。队列最多10、pk去重、最新可见优先，上下文就绪立即pump，drain/resume重排可见目标。慢响应不保证0.75秒出行。每次启动最多400请求、45秒超时，429/rate-limit/feedback_required/spam/checkpoint暂停1小时。尚未获得可用资料时，连续无可用资料结果至少6次，且本次为失败回调，停止本次启动；空成功回调不会单独触发停止。“获得可用资料”可包含原生字段补缺，不等同于网络回调 success。

缓存 `tp_author_cache` / `tp_author_paused_until` / `tp_author_param_format`，结构v5：地区21天、无地区有效结果1天、失败/空30分钟；只有username不算成功。410旧v<5缺joined/number缓存失效刷新一次；**v5部分成功不会因缺编号持续自动补齐**。最多3000条、5秒延迟落盘/淘汰最早过期；request/requeue 防递归pump。

**防崩迁移关键**：`TPBuildClassSet` 与 `Tweak.x` 的 `TPClassFamily` 改用动态 `objc_copyRealizedClassList`、unsafe-unretained class数组，不为枚举主动实现所有Swift类；符号不可用只匹配已知base。不恢复 `objc_copyClassList` 全量扫描/不匹配Swift init/固定结构偏移。与有类型回调、能力检测、pk绑定及有限几何检查一起保留。这是规避已见触发路径，不是所有未来Swift ABI的保证。

`test-author-info.sh` 覆盖JSON/Bloks、Joined编号、隐藏地区、空成功拒绝、NEW边界、v5迁移、原生年月编号。未验证真实私有fetch回调、完整服务端字段、UICollectionView时机/体感速度；此前地区能显示的反馈不能推出全部项在+16均验收。

### F10 全屏长按下载和布局

下载/媒体提取主体大部分沿用上游。新增 `TPLBLongPressHandler / kTPLBLongPressKey`；`TPEnsureLightboxButton` 在有效、居中、启用的全屏分页 host cell 上安装 UILongPressGestureRecognizer，0.55秒、`cancelsTouchesInView=NO`、weak host/button，Began取已存图片/视频菜单，调用原 `+[TPUI tp_showMenu:from:]`。受 `TPKeyShowDownloadBtn / tp_show_download_btn` 控制，非始终开启手势。

hook `_TtC11BCNLightbox20BCNLightboxPhotoCell` / `_TtC11BCNLightbox15BCNLightboxCell -layoutSubviews` 及相关 feed media布局/didMove。短按仍当前媒体；长按可选当前帖子全部图片/视频，“全部”不是任意回复串所有页面。`TPLightboxPagesPhotos` 读 listAdapter.objects 未加载分页；`TPLightboxCarouselChildren` 读 carouselParent/carouselMedia/有guard的 content.body；提取去重及图片原图/当前项兜底、视频URL+DASH保留。

性能差异：缓存 close/more button且复核window/祖先后复用；follower CADisplayLink60→30fps；移除递归presentation-layer透明度/animation链扫描，读source alpha/hidden，保留几何跟随。settle9帧/fade9帧现在各约0.3秒，不能按旧注释写0.15秒。`TPTopViewController` 和原菜单展示 helper 是未改的上游依赖，不列为本地展示上下文修复；TPUI 的净改动归 F12 截图保护。

无专用全屏UI自动测试；应检查图片/视频/混合carousel、短按当前、长按全部及实际照片库保存结果，不只看菜单弹出。

### F11 iOS15下载/转码兼容

`TPDownloader.h` 未变；.m仅增加 iOS16 API保护。`TPSoftDecoder._xfer` 用 `void *` 存，create/transfer/invalidate 与 destination-color properties 放 `@available(iOS 16.0, *)` 内，强类型local session；iOS15需要该转换/色调映射分支时释放buffer、返回明确错误，沿用原DASH失败后progressive720p后备；progressiveConvert自身失败终止，不循环下载。

iOS15可加载不等于所有HDR转换与16相同，也不等于所有软解码都失效。上游 H264/HEVC passthrough、VP9/libvpx、AV1/dav1d、AV1 iOS17+硬解检查、HDR/SDR输出、AAC、取消/后台处理保留。`tp_video_quality`（0最高/1 720p/2询问）、`tp_video_format`（0保留HDR/1兼容）未另起语义。

## 5. UI与资源：F12–F13

### F12 截图隐藏

`TPKeyHideInCaptures / tp_hide_in_captures` 与上游 `TPKeyBlockScreenshotDetect / tp_block_screenshot_detect` 是两个功能；后者阻 App 获知截图、组本身无净差异。

共享 `TPSetCaptureProtectedContent(content, host)`：非零secure UITextField先布局，`TPFindSecureCanvas(field,4)` 有界子树查找；`TPCaptureContainer` 强持有field并保留canvas原生层级，布局后转换几何，content随bounds更新。host保留触摸、位置、accessibility，只搬自有visual，不移动 UIKit 自管button.imageView。弱host集合监听该key变化，已显示控件即时切换；无canvas时正常显示，不留下透明失效按钮。

接入：圆形下载按钮、下载pill、详情卡片、2x滑动锁定提示、固定英文Pulse、聊天室眼睛。`TPCapsule.m`、`TPUI.h` 导出、`Tweak.x` 内各visual的主题/状态更新必须一起迁，不能继续改空host configuration。作者文字、所有toast/原生菜单/原生设置不是整体截图保护范围。

旧的零尺寸field/只找一级/抽走canvas后释放field/移动内部imageView方案不再使用。49项stub覆盖所有权、嵌套坐标、内容替换、开关、resize/fallback；不模拟iOS合成器，截图/录屏、点击/长按、旋转/转场仍待实机。详见 [截图分析](capture-protection-analysis.md)。

### F13 五语、二改署名与单文件资源

交付要求：将原 `ThreadsPulse.bundle` 的五语资源编译进主插件 `ThreadsPulse.dylib`。Rootless / Roothide DEB 各交付一个 dylib 和注入过滤 plist；TrollFools ZIP 仅放 dylib；新版 IPA 注入只传 dylib。每次上游迁移后，从产物解包确认五语目录已编入 dylib、安装路径中没有独立的 `ThreadsPulse.bundle`。

保留上游六选项：0跟随系统、1en、2zh-Hant、3zh-Hans、4ja、5ko。**没有恢复另一套本地多语言体系。**上游原344键各语逐值保留，只增 `Modified and optimized: By %@` 和 `A message was unsent` 两键，当前346×5=1730；Info.plist字节不变。

源文件移到 `resources/localization/`，`scripts/generate-localization.py` 以Python标准库严格解析，拒重复键/非法内容，读Info后生成 deterministic binary plist头 `.generated/TPLocalizationData.h`；输入不变不重写。Makefile的 `before-all before-ThreadsPulse-all` 依赖脚本/Info/所有strings，`.generated/` 忽略提交。改语言应改源表，不手工改生成头。

`TPLocalizationCatalog` dispatch_once解内嵌数据，`TPLocalized` 每次按当前语言选表，回跟随系统不缓存旧手选；未知语种按developmentRegion=en，缺键回原key。无runtime解包、写资源或外部bundle依赖。payload66,626字节，SHA256 `5440289a476c1afcb305eb160b35dc3907bedf141edbb48e34436fa3d18ba859`。

`TPSettingsViewController.m` 保留原赞助footer、`Made by h4x_0x30vm`；根页最后section自适应UITextView再加本地化二改署名，仅Junhong链接 `https://mjh.im/`，走原openLink；非根页footer保留。未替换原作者/Ko-fi/DEB作者，不重设计设置页。

`Pulse` 固定英文、accessibilityLabel=ThreadsPulse，本来与上游一致；当前只是visual/host分离接截图保护。仍在App自己的设置页、保留Home长按/三指长按入口，不改系统PreferenceLoader。

语言测试验证源表/生成payload/手选↔系统/缺键；表中撤回提示键存在不表示通知进程依赖整个catalog，通知用自己的小型五语字典。

## 6. 撤回系统通知：F14

**结论：+16的受限正文复用代码和本机回归已完成，朋友真实推送尚未验收。上一版仅英文变中文，不能算正文保留成功。该失败反馈包含正常包管理器安装DEB，不能直接归咎TrollFools。**

### 6.1 两进程与精确事件

`ThreadsPulseNotifications.x` 合编主dylib。主 `Tweak.x` ctor首句确认进程名 `Threads`，在 `TPSideloadFixInstall`、prefs迁移和任何 %init之前；通知ctor仅 `BarcelonaNotificationExtension`，且确认 `FBNotificationService -didReceiveNotificationRequest:withContentHandler:` / `-serviceExtensionTimeWillExpire` 两方法存在。合并后必须保留双ctor隔离，避免主UI/侧载初始化进入NSE。

两版原生撤回标记：`userInfo[@"c"] == @"text_post_app_recall_notif"`；原生按 `gid` 删除旧delivered通知。不能按英文正文/相同聊天室猜事件或拿n/message_id替代gid。

纯语言回退：原request或final有精确recall标记，且final body严格等于 `A message was unsent` 或带句点版本才翻译。普通私信同句不改，其他正文/标点变体不擅改。只改body；简中/繁中/英/日/韩跟系统 `NSLocale.preferredLanguages`，未知回英文，不跟主App手选语言。**翻译不受KeepUnsent开关控制**，关时仍可翻译系统提示。

### 6.2 +16受限正文复用流程

1. 原request为精确recall、gid非空NSString、共享KeepUnsent明确开、handler存在才查询。
2. 在原生删除前异步 `getDeliveredNotifications`，只匹配 `delivered.request.identifier == gid`。
3. 仅读匹配项body，拒空白/自身recall，保存原body不trim可见文本；不读其他消息正文。
4. 查询回调排主队列继续原生；350ms主队列deadline让未返回查询放行。主线程繁忙时不是绝对350ms实时保证。
5. 原生completion再次读开关，有原文且仍开才copy最终content替换body；title/subtitle/userInfo/thread/category/attachments/sound保持原生最终结果，原request/identifier/trigger不重建。原生已本地化的撤回提示也可替换。
6. 无原文则纯语言回退，不编造；已恢复的原文即便恰好是英文提示也原样保留。
7. `TPNotificationRecovery` 的started/completed锁确保原生最多启动一次/handler一次，弱service/state避免环；统一 `TPCompleteNotification` 清body/闭包/关联。expiry有recovery时在到期线程立即fallback，不等主队列/原生尚未保存的handler，防迟到query/deadline/native重复；普通请求保留原生expiry。

**正常原生完成且成功复用时，原生仍删除旧gid通知；新撤回通知带旧正文，时间/identifier是新的。**不是保住旧系统通知对象，也没有持久化历史正文库。expiry 先完成则直接以保存的 `request.content` 为基底执行统一 completion；原生可能尚未运行，此时不能承诺已执行原生删除或取得原生最终 metadata，fallback 只保留 request 原有字段及当时已获得的可用正文。已清除、没送达、无明文预览、gid不匹配、查询晚于deadline、共享状态不可读、iOS不拉起/杀掉扩展都不能保证恢复。

日志只含版本/hook_ready/recall/lang/restored/translated标记，不输出正文、sender、userInfo、gid或会话标识。

### 6.3 开关跨进程镜像

新增 `TPNotificationPrefs.h/.m`，仅镜像 `KeepUnsent` 到实际共同AppGroup `group.com.burbn.instagram/ThreadsPulse/notification-prefs.plist`，只一个strict CFBoolean `keepUnsent`。原子binary plist，首次解锁后可读保护；不含正文/ID。reader每次读盘，缺失/损坏/非字典/非CFBoolean（包括整数1）/权限或group不可用均off，不缓存旧true。

同步点：`TPPrefs setBool:forKey:`仅目标key、`resetAll`写false、原JSON import通过setter、主Threads ctor初始和 `UIApplicationDidBecomeActiveNotification`。extension只读，不用普通defaults冒充共享。主suite仍 `com.example.threadspulse`，本轮不改既有偏好/defaults，不新增统一总开关；不能写“所有项现已默认关闭”。

### 6.4 安装/注入与测试边界

- 正常越狱包管理器安装DEB可让loader依据双Executable Filter加载，但仍需真实NSE/AppGroup/锁屏/推送验证。
- 已查看的TrollFools官方4.4.2 commit `c5c87b859a9ee34d215548377273eddd34a7c7f6` 不扫描通知appex/不解析tweak Filter，只注入所选主executable/framework。合一个dylib不等于NSE已加载。
- `scripts/inject_ipa.py` 也只注入主App；`--bundle`仅变可选旧格式输入，不是新增NSE注入。不要把主App成功当通知成功。
- 不同时留包管理器加载与手工注入重复副本；本轮没有修改TrollFools、系统进程、已安装App或权限。

通知测试编译实际hook/ctor，覆盖exact marker/gid/元数据/开关/deadline/expiry竞态/-Werror retain cycles；pref用真实Foundation文件IO但测试替身AppGroup/隔离defaults。均不能证明真实entitlement、锁屏读取或真实推送正文恢复。详见 [通知静态证据](notification-unsend-analysis.md)。朋友验收记录应包含客户端/系统/语言/安装方式、原通知是否仍在、开关开/关、无匹配回退结果。

## 7. 构建与交付：B01–B02

| 项目 | Rootless | RootHide |
| --- | --- | --- |
| Theos | `/Users/manjunhong/theos` | `/Users/manjunhong/theos-roothide` |
| scheme | `rootless` | `roothide` |
| 真Mach-O | `arm64` | **`arm64e`** |
| control Architecture | `iphoneos-arm64` | `iphoneos-arm64e` |
| Package | `com.h4x.threadspulse` | `com.h4x.threadspulse.roothide` |
| Name | `ThreadsPulse` | `ThreadsPulse (Roothide)` |
| payload | `/var/jb/Library/MobileSubstrate/DynamicLibraries/` | `/Library/MobileSubstrate/DynamicLibraries/` |
| 交付名 | `ThreadsPulse_1.31.0+16_arm64.deb` | `ThreadsPulse_1.31.0+16_arm64e.deb` |

RootHide带两rpath：`@loader_path/.jbroot/Library/Frameworks`、`@loader_path/.jbroot/usr/lib`；control不声明mobilesubstrate/ellekit等框架Depends。不能通过改名/改Architecture冒充另一架构包。英文交付名沿用用户对本项目明确要求。

Filter是Executables=(Threads, BarcelonaNotificationExtension)，不是Bundles。唯一target=ThreadsPulse，文件列表带通知/偏好/音乐，framework新增AVKit/UserNotifications，Logos internal沿用上游。最终每包1dylib/0bundle/1filter；源码仍分模块维护，“合并”指交付二进制和资源，不把源码硬揉成一文件。

### 7.1 双切片codec

| 库 | 构建固定commit | 当前SHA256 |
| --- | --- | --- |
| libvpx | `6f4dbb1bc6803cbcdb7f54bd1c11a6228b717705` | `500c33533da85b86d7cc374dabf88a304684052435778442eac4daf1be5686c4` |
| dav1d | `39834d7f71c85a9c555f2ddd7a7add6d671750de` | `1e66d968f933f66e4cca4587115420c6b97434773c86eec51047a4da8284e018` |

上游单arm64；当前两库均arm64+arm64e，本轮lipo复核。`scripts/build-codecs.sh` 分架构iOS15构建后lipo，libvpx仅解码/VP9 highbitdepth，禁dotprod/i8mm/SVE/SVE2；dav1d用Meson1.9.1/ninja。需网络/uv等既有能力入口；脚本默认Xcode16.4。vendor/VERSION.txt仍是上游说明，不能据此判断当前切片。只迁.m漏库会破坏arm64e链接，本轮未重建库。

### 7.2 本机隔离构建参考

工作区路径带空格，Theos不接受直接在此路径构建；两个方案使用无空格临时目录并隔离缓存。下列仅作后续获授权打包时参考，本次写文档没执行构建：

~~~bash
SOURCE='/Volumes/代码/ Threads/ThreadsPulse-410'
WORK=$(mktemp -d /tmp/threadspulse-build.XXXXXX)
for SCHEME in rootless roothide; do
  mkdir -p "$WORK/$SCHEME"
  rsync -a --exclude=.git --exclude=.theos --exclude=.generated \
    --exclude=dist --exclude=packages --exclude=build \
    "$SOURCE/" "$WORK/$SCHEME/"
done
# 仅复现冻结版本；下一轮先确定新目标，不自动沿用+16。
env DEVELOPER_DIR=/Applications/Xcode-16.4.app/Contents/Developer LC_ALL=C \
  make -C "$WORK/rootless" THEOS=/Users/manjunhong/theos \
  THEOS_PACKAGE_SCHEME=rootless VERSION=1.31.0+16 FINALPACKAGE=1 package
env DEVELOPER_DIR=/Applications/Xcode-16.4.app/Contents/Developer LC_ALL=C \
  make -C "$WORK/roothide" THEOS=/Users/manjunhong/theos-roothide \
  THEOS_PACKAGE_SCHEME=roothide VERSION=1.31.0+16 FINALPACKAGE=1 package
~~~

Makefile after-package按VERSION/ARCHS输出规范名；核对实际metadata后只交本轮两个DEB，不自动安装/发布或额外交独立dylib/ZIP。dist当前还留历史包，不能用通配符选“最新包”，本次不擅自清理。

### 7.3 CI/IPA差异及未完成项

`build.yml` / `build-ipa.yml` 去旧bundle复制/参数，ZIP只放dylib；`inject_ipa.py --bundle`可选。**Ubuntu Actions未跑验收**：Makefile还有macOS `sed -i ''`，workflow还沿用上游rootful/ZIP产物及scheme调用，不能拿本地macOS双包推断CI产出真RootHide。后续启用前核对Linux sed、SDK/scheme/架构/文件名/发布job。本文只记录，不扩大为CI修复或发布任务。

## 8. 验证账本

### 8.1 2026-11-20重新执行的七组本机检查

全部通过。固定Xcode与macOS SDK，避免Xcode16 linker混读CommandLineTools新版SDK；音乐脚本不自行设SDKROOT，尤需外部指定。此前SDK混用的链接报错属于测试工具链，不是音乐功能故障。

~~~bash
cd '/Volumes/代码/ Threads/ThreadsPulse-410'
export DEVELOPER_DIR=/Applications/Xcode-16.4.app/Contents/Developer
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
for SCRIPT in \
  test-ad-delivery.sh test-author-info.sh test-capture-protection.sh \
  test-localization.sh test-music-attachment.sh \
  test-notification-localization.sh test-pin-tab-bar.sh; do
  bash "scripts/$SCRIPT" || exit 1
done
~~~

| 测试 | 实际覆盖 | 不代表 |
| --- | --- | --- |
| `test-ad-delivery.sh` | 生产Logos hook、开关/参数/64-bit ABI | 所有真实广告已消失 |
| `test-author-info.sh` | 生产解析/缓存helper合成数据 | 线上字段齐备/真实回调ABI/UI速度 |
| `test-capture-protection.sh` | UIKit stubs 49项所有权/布局/开关 | iOS系统截图/录屏隐藏成功 |
| `test-localization.sh` | 五表346键、内嵌源一致、动态选语/缺键 | 全部页面设备逐项验收 |
| `test-music-attachment.sh` | Foundation音乐解析、输入拒绝/音频URL | AVPlayer有声/所有格式可播 |
| `test-notification-localization.sh` | 实际hook/ctor/九种语言含fallback/gid/竞态，真实文件IO但替身group | 真实AppGroup/锁屏/NSE/推送正文保留 |
| `test-pin-tab-bar.sh` | 生产Logos、double ABI、开关/禁止全局补丁 | 全部页面转场UI正常 |

本轮没有附加Frida、操作手机、安装或发布。复制/外部浏览器、首页四项、NoSeen/eye、App内删除过滤、全屏UI没有各自专用本机脚本，不能借其它PASS补齐。

### 8.2 每轮迁移真机矩阵

| 场景 | 410 | 456/新上游目标 | 至少记录 |
| --- | --- | --- | --- |
| 启动/设置/点图/往返滑动 | 当前迁移包待测 | 当前迁移包待测 | 版本、无崩溃/卡死、日志对应 |
| 广告开/关 | 真实投放待测 | 真实投放待测 | 客户端/广告面/关时原生放行 |
| 帖子复制/系统分享/外链 | 待回归 | 待回归 | 实际URL、业务参数、复制不自打开 |
| 首页四项 | 分别/组合 | 分别/组合 | 顶部/中部、前后台、点击双击、长按 |
| 固定底栏 | 待完整转场 | 待完整转场 | 首页↔个人页、push/modal、全屏退出、开关关 |
| 已读眼睛/防撤回 | 待回归 | 待回归 | 两功能独立、对方Seen、发送顺序、普通删除 |
| 全屏下载 | 待回归 | 待回归 | 当前/全部图/全部视频/混合串，照片库结果 |
| 音乐 | 当前音源待回归 | 确认未接管原生 | 起点/有声/退出/后台暂停 |
| 作者资料 | 全字段待回归 | 原生路径待回归 | 冷/热、缺字段/无空行、cell复用、整组/速度 |
| 截图隐藏 | 系统截图/录屏待测 | 系统截图/录屏待测 | 开关、视觉/触摸/无障碍/旋转 |
| 推送撤回 | 等境外朋友 | 可推送设备待测 | 安装方式/NSE/原通知仍在/开关/无匹配回退 |
| 语言/署名 | 五语抽检 | 五语抽检 | Pulse固定英文，UI署名随插件，通知随系统 |

### 8.3 冻结交付包身份

| 包 | 字节数 | SHA256 |
| --- | ---: | --- |
| `dist/ThreadsPulse_1.31.0+16_arm64.deb` | 683668 | `59dee2cd55ea852e50313aff93839d9b91a1f6b7a079f2abad1fe691b1566c6a` |
| `dist/ThreadsPulse_1.31.0+16_arm64e.deb` | 684826 | `a0727efaef23de84518d62ac3fd244720c2d790c5a92deaf6e98540e86da88bc` |

两hash本次重新读取未变。此前+16交付独立实解包确认：各1dylib/0bundle/1filter，版本/实际架构/iOS15/SDK18.5/布局/rpath正确，无框架Depends，catalog与源一致，CodeDirectory页hash已重算。不是本轮重打包/真机验收。

尚未完成：+16真实通知正文复用；当前包410/456完整设备矩阵；作者全字段/冷缓存速度；新增广告路径与截图反馈动态对应；系统截图/录屏；Ubuntu CI双方案。

## 9. 不应迁回的旧尝试与升级流程

### 9.1 不迁回

1. 眼睛误接防撤回及对应额外toast；应保留原Seen语义/提示。
2. 未读红点/双份inbox/thread数据库强改；用户已取消该修复。
3. 全局底栏hidden/transform/layout或页面生命周期强制补位。
4. 缺少 moreButton 的旧版 fallback 不迁回“完成布局后按坐标再塞眼睛/反复叠按钮”补丁；使用原生列表写入及结构互斥。新版有 moreButton 时仍保留上游 layoutSubviews 放置分支，不因这项禁令删除它。
5. 枚举未realize Swift类、不匹配init、裸指针猜回调、固定内存偏移。
6. 独立默认中文体系/旧外部bundle重复源；原上游语言行为应保留。
7. 仅翻译即宣称正文保留；或按threadIdentifier/猜message_id匹配通知。
8. 410补丁覆盖/删除新版上游hooks，造成456广告等能力回退。
9. 改包名冒充架构、乱升正式版、批量重置偏好。

### 9.2 三方迁移顺序

1. 冻结旧上游commit、当前修复树、新上游commit；确认线上真实正式版本，测试最高号不是正式基线。
2. 以新上游为主体按F01–F14/B01–B02逐项处置；禁止整文件覆盖Tweak/TPAuthorInfo/TPUI等。
3. 先对齐构建依赖：iOS15 guard、双切片vendor、单target/双ctor隔离、AVKit/UN、资源生成/Filter/control。
4. 再按原生调用链迁小块：class/selector存在、精确参数/返回ABI；保留新版native处理。存在性gate与410版本gate不能互换，特别F05也会参与456。
5. 上游若等价覆盖，记录新symbol/证据后删重复本地hook；不能只因名字相同就当实现等价。
6. 按全量索引核所有.h导出、调用方、ctor、静态库、strings、构建/注入/测试；防止“文件在但没编进去”。
7. 七组本机→隔离双包→实解包；测试抽取区/源表hash因新上游变化应有依据更新，不能删除校验只求PASS。
8. 独立代理审查“未迁/误删/开关语义/成功声明越界”；之后完成设备矩阵，未测试写明。
9. 同一轮两个架构用同版本，测试交付+N按本项目要求递增；正式目标从线上基准确定，不因返工虚增。打包不自动授权安装/发布。
10. 更新本主文档的基线、差异清单及真实验收；不要只留聊天记录。

~~~text
迁移日期：
旧上游commit：
新上游版本/commit：
本地目标测试版本：
Fxx/Bxx：保留 / 新上游已等价覆盖 / 移除 / 待验证
新上游文件/symbol：
保留的最小改动/原因：
调用方/构建/资源/测试是否齐备：
本机结果：
设备/客户端/安装方式/实际结果：
独立审查结论：
仍缺证据：
~~~

## 10. 全量文件索引

下表来自编写前冻结快照。资源移动显示删除+新增，不能误认为丢翻译；文件hash见JSON。本文/JSON/本次README入口与通知expiry说明校正另属于维护文档变更，不改变插件二进制。

| 状态 | 文件（相对项目根目录） | 迁移归类 |
| --- | --- | --- |
| 修改 | `.github/workflows/build-ipa.yml` | B01/B02 构建/注入/版本 |
| 修改 | `.github/workflows/build.yml` | B01/B02 构建/注入/版本 |
| 修改 | `.gitignore` | B01/B02 构建/注入/版本 |
| 修改 | `Makefile` | B01/B02 构建/注入/版本 |
| 修改 | `README.md` | 维护说明/专项证据 |
| 修改 | `README.zh-TW.md` | 维护说明/专项证据 |
| 修改 | `TPAuthorInfo.h` | F09 作者资料 |
| 修改 | `TPAuthorInfo.m` | F09 作者资料 |
| 修改 | `TPCapsule.m` | F12 共享截图保护 |
| 修改 | `TPDownloader.m` | F11 iOS15 API保护 |
| 修改 | `TPLocalization.m` | F13 语言/署名 |
| 新增 | `TPMusicAttachment.h` | F08 音乐 |
| 新增 | `TPMusicAttachment.m` | F08 音乐 |
| 新增 | `TPMusicCompat.h` | F08 音乐 |
| 新增 | `TPMusicCompat.m` | F08 音乐 |
| 新增 | `TPNotificationPrefs.h` | F14 通知/共享开关 |
| 新增 | `TPNotificationPrefs.m` | F14 通知/共享开关 |
| 修改 | `TPPrefs.m` | F14 通知/共享开关 |
| 修改 | `TPSettingsViewController.m` | F13 语言/署名 |
| 修改 | `TPUI.h` | F12 共享截图保护 |
| 修改 | `TPUI.m` | F12 共享截图保护 |
| 修改 | `TPVersion.h` | B01/B02 构建/注入/版本 |
| 修改 | `ThreadsPulse.plist` | B01/B02 构建/注入/版本 |
| 新增 | `ThreadsPulseNotifications.x` | F14 通知/共享开关 |
| 修改 | `Tweak.x` | F01–F10/F12/F14 主调用链/ctor |
| 修改 | `control` | B01/B02 构建/注入/版本 |
| 新增 | `docs/ads-410-456-analysis.md` | 维护说明/专项证据 |
| 新增 | `docs/capture-protection-analysis.md` | 维护说明/专项证据 |
| 新增 | `docs/notification-unsend-analysis.md` | 维护说明/专项证据 |
| 新增 | `docs/pin-tab-bar-410-analysis.md` | 维护说明/专项证据 |
| 删除 | `layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle/Info.plist` | F13 资源移动/内嵌 |
| 删除 | `layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle/en.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 删除 | `layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle/ja.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 删除 | `layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle/ko.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 删除 | `layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle/zh-Hans.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 删除 | `layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle/zh-Hant.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 新增 | `resources/localization/Info.plist` | F13 资源移动/内嵌 |
| 新增 | `resources/localization/en.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 新增 | `resources/localization/ja.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 新增 | `resources/localization/ko.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 新增 | `resources/localization/zh-Hans.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 新增 | `resources/localization/zh-Hant.lproj/Localizable.strings` | F13 资源移动/内嵌 |
| 新增 | `scripts/build-codecs.sh` | B01 解码库/真实双架构 |
| 新增 | `scripts/generate-localization.py` | F13/B02 构建资源生成 |
| 修改 | `scripts/inject_ipa.py` | B01/B02 构建/注入/版本 |
| 新增 | `scripts/test-ad-delivery.sh` | 对应模块回归检查 |
| 新增 | `scripts/test-author-info.sh` | 对应模块回归检查 |
| 新增 | `scripts/test-capture-protection.sh` | 对应模块回归检查 |
| 新增 | `scripts/test-localization.sh` | 对应模块回归检查 |
| 新增 | `scripts/test-music-attachment.sh` | 对应模块回归检查 |
| 新增 | `scripts/test-notification-localization.sh` | 对应模块回归检查 |
| 新增 | `scripts/test-pin-tab-bar.sh` | 对应模块回归检查 |
| 新增 | `tests/ad-delivery.x` | 对应模块回归检查 |
| 新增 | `tests/author-info.m` | 对应模块回归检查 |
| 新增 | `tests/capture-protection.m` | 对应模块回归检查 |
| 新增 | `tests/localization.m` | 对应模块回归检查 |
| 新增 | `tests/music-attachment.m` | 对应模块回归检查 |
| 新增 | `tests/notification-localization.x` | 对应模块回归检查 |
| 新增 | `tests/notification-prefs.m` | 对应模块回归检查 |
| 新增 | `tests/pin-tab-bar.x` | 对应模块回归检查 |
| 修改 | `vendor/dav1d/lib/libdav1d.a` | B01 解码库/真实双架构 |
| 修改 | `vendor/libvpx/lib/libvpx.a` | B01 解码库/真实双架构 |

未列文件以新上游为准，不为“保留修复”从旧目录回灌。尤其 `TPURLCleaner.m` 无差异、复制兼容在Tweak；`TPHUD.m` 无差异，`TPUI.m` 修改的是截图保护而非顶部控制器查找；作者统计等原能力不要当本地新增覆盖新版。

专项证据入口：[广告](ads-410-456-analysis.md)、[固定底栏](pin-tab-bar-410-analysis.md)、[截图保护](capture-protection-analysis.md)、[通知](notification-unsend-analysis.md)。行为自检在 `scripts/test-*.sh` 和 `tests/`。后续每个修复应同步本总账与验证状态，不能以构建、代码审查或历史单场景反馈冒充当前真实验收。


## 11. 迁移到 v1.31.1

2026-11-22。以上游 `462d912`（v1.31.1）为基线，重放 `038d740` 到旁边 `ThreadsPulse-410` 的 **1.31.0+16** 维护快照，交付 **1.31.1+2**。此前 +1 使用的是更早的工作区快照，缺少底栏和作者资料兼容链。

| 项目 | 本次处置 |
| --- | --- |
| F01–F03 | 保留两代广告入口及旧版复制、外链兼容。剪贴簿自动打开使用上游 v1.31.1 的登录和输入保护。 |
| F04–F07 | 保留旧 root 首页点击及长按、底栏双 selector 兼容、已读与防撤回。上游独立 legacy tab controller 和 Lucent 长按路径保留。 |
| F08 | 保留 410 模型更新与 tombstone cell 的完整音乐路径和 AVKit。+1 和 +16 的音乐模块源码一致，真机不显示的具体条件仍待确认。 |
| F09 | 保留 410 的请求上下文、旧请求回退、资料解析与旧 header 布局。新版继续使用上游的作者预读优先级。 |
| F10–F14 / B01–B02 | 恢复 +16 维护快照中的全屏媒体、iOS 15 解码保护、截图隐藏、内嵌五语、通知链及双架构单 dylib 交付。 |

本机执行迁移指南列出的七组测试，并逐个解包校验架构、iOS 15、注入范围、内嵌语言、兼容 selector、解码库和签名页哈希。410 真机上的音乐卡片、底栏和作者资料仍待验证。GitHub Actions、系统推送和截图未在本轮实测。

### 11.1 全屏图片长按下载（1.31.1+3）

+2 已包含冻结版的长按回调，但它依赖下载按钮初始化。图片尚未解析出 URL 或图像视图时，首轮布局会提前退出。+3 在全屏图片 cell 入窗时接入手势，并在触发时检查下载开关、当前页和触点。菜单以当前图片页为准，复用下载当前图片、下载该贴全部图片的逻辑。全屏图片长按、相册落盘及与原生手势的交互仍待旧版 Threads 真机验证。

### 11.2 Bundle 合并复核（1.31.1+3）

Rootless 与 Roothide 已解包复核。两包均包含一个 `ThreadsPulse.dylib` 和一个注入过滤 plist，五语目录与构建时生成的目录逐字节一致，包内没有独立的 `ThreadsPulse.bundle`。TrollFools 和 IPA 的工作流已移除独立资源参数，本轮未运行 GitHub Actions。

替换曾注入过旧版本的 IPA 时，`scripts/inject_ipa.py` 会移除主 App 目录中残留的 `ThreadsPulse.bundle`。显式传入 `--bundle` 时，脚本先移除旧资源，再拷入指定目录，供需要外部资源的历史版本使用。迁移验收执行 `bash scripts/test-localization.sh` 和 `python3 scripts/verify-packages.py`，并检查 IPA 重注入结果。

## 12. 2026-11-23 上游复核与同步前审查

本次重新 fetch origin 与 tags。当前 HEAD、origin/main、v1.31.1 均为 462d91242b0f2ee7ec7e7df7bf99e5ae213fec6a，与第 11 节迁移基线一致。本地维护版本继续使用 1.31.1+3。

### 本次迁移处置清单

| 指南项 | 处置与核对依据 |
| --- | --- |
| F01 广告 | 保留旧 selector 和共同投放入口，上游 1.31.1 无等价替代。 |
| F02 复制与剪贴簿 | 保留 concrete pasteboard 去追踪入口。已合入上游键盘/弹窗保护、登录后保护、等待新首页及真实前后台判定。 |
| F03 外链 | 保留旧模块与新版模块入口。 |
| F04 首页 | 保留旧 root 点击/长按、刷新及保留位置兼容。 |
| F05 固定底栏 | 保留 LegacyPinTabBar 的双 selector gate 和原 Lucent 路径。 |
| F06 已读眼睛 | 保留旧发送签名和旧原生导航项接入。 |
| F07 防撤回 | 保留 direct delete applicator 补充入口。 |
| F08 音乐 | 保留 410 模型/卡片/播放链。此前同一帖子在 410 与 456 的运行时观测均缺音源，456 抓到 MUSIC_RIGHTS_NOT_LAUNCHED_COUNTRY。该结果仅覆盖所测帖子。 |
| F09 作者资料 | 已合入上游屏内优先及向下预读调度。410 保留可见性筛选、旧请求回退和旧 header 兼容。 |
| F10 全屏下载 | 保留 +3 图片入窗手势接入与独立菜单，真机触发及落盘仍待验证。 |
| F11 iOS 15 | 保留 VideoToolbox 可用性保护。 |
| F12 截图隐藏 | 保留安全容器生命周期与布局修复。 |
| F13 语言/署名 | 保留内嵌五语及二改署名。 |
| F14 通知 | 保留通知翻译和有条件的原正文复用。 |
| B01–B02 构建 | 保留双架构静态库、单 dylib、双进程 Filter 和资源生成/注入调整。 |

同步前独立子代理审查通过。确认上游 1.31.1 的功能变化已包含在当前源码中，其余本地修复继续保留。本次只补充复核记录，交付沿用 1.31.1+3。验证结果及交付后审查记录见下文。

### 本轮验证和交付前二次审查

2026-11-23，广告投放、作者资料、截图容器、五语、音乐解析、通知处理、旧底栏共七组现有本机测试全部通过。verify-packages.py 对 1.31.1+3 的 Rootless 与 Roothide 两包校验通过。二次独立子代理审查通过，无交付阻断项。本轮修改限于本节维护记录，沿用现有双包，未重新构建。当前包的完整真机矩阵、GitHub Actions、真实推送与系统截图仍待验证。

### 交付版本更正

2026-11-23 再查 dist，发现 2026-11-22 16:56 生成的 1.31.1+4 双包。dpkg-deb 实读 metadata 均为 1.31.1+4，分别为 iphoneos-arm64 和 iphoneos-arm64e。因此本目录最高交付包版本为 +4。上述第 12 节验证实际针对 +3 源码和 +3 双包，不能作为 +4 审查或验收结论。当前 TPVersion.h、Makefile 和 control 仍为 +3，+4 对应的源码及构建来源尚未确认。后续升级须先对齐 +4 的构建来源，再进行迁移。

## 13. 音乐可播放标记处理更正（1.31.1+5）

即使 is_available_for_consumption=false 或 error_code 带有地区错误，只要返回的数据包含可解析的 HTTPS 单文件音频 DASH，仍创建音乐附件并允许播放器尝试播放。原可播放标记与错误码继续保留在诊断中。缺少音源、无效清单或不支持的音源形式仍返回 nil。实际 CDN 是否允许访问由播放器请求结果决定。

新增回归用例覆盖 false 标记但带有效音源、地区错误且带有效音源、无音源地区拒绝三种情况。此前文档中将拒绝标记作为解析硬条件的说明由本节更正。版本使用 +5，避免覆盖已存在的 +4 包。真机播放、CDN 接受状态仍待验证。
