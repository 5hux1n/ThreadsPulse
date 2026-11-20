# ThreadsPulse

[English](README.md) | [繁體中文](README.zh-TW.md) | **简体中文**

Threads（`com.burbn.barcelona`）的 iOS 增强插件。兼容版本：**1.31.0+16**，基于 [h4x_0x30vm 的 ThreadsPulse 1.31.0](https://github.com/mumuisdog/ThreadsPulse)。

本分支保留原作者功能，加入 Threads 410、456 的兼容修正，支持 **iOS 15 及以上**。

[下载 1.31.0+16](https://github.com/5hux1n/ThreadsPulse/releases/tag/1.31.0%2B16) · [所有版本](https://github.com/5hux1n/ThreadsPulse/releases)

| 安装包 | 适用环境 |
|---|---|
| `ThreadsPulse_1.31.0+16_arm64.deb` | Rootless（无根越狱） |
| `ThreadsPulse_1.31.0+16_arm64e.deb` | RootHide |

使用越狱包管理器安装对应的 DEB。TrollFools 请导入 Rootless（`arm64`）DEB 整包，不需要另外导入语言资源包。

插件内置的更新检查仍跟随原作者项目；本分支的兼容版本请从本仓库 Releases 下载。

需要侧载 IPA 时，请参考下方的本地注入命令。Actions 说明保留作为上游流程参考。

## 功能

| 分类 | 功能 | 说明 |
|---|---|---|
| 广告与隐私 | 去除广告 | 隐藏动态里的赞助帖子 |
| | 禁用截图检测 | 截图或录屏时，Threads 不会检测到 |
| | 阻止分析数据上报 | 不上报浏览、停留时间与点击等使用记录，推荐内容可能不够准确（默认关闭） |
| | 移除网址追踪码 | 复制、分享或打开链接时，自动移除 `xmt`、`igshid`、`utm_*` 等追踪参数，并解开 `l.threads.com` 跳转 |
| | 截图时隐藏插件按钮 | 截图或录屏时，画面上不会出现 ThreadsPulse 的按钮 |
| 媒体下载 | 下载按钮 | 帖子右上角 ↓：点击下载全部图片与视频，长按可选择仅下载图片或视频 |
| | 全屏下载 | 全屏查看时 ↓ 在「⋯」旁边：点击保存当前的图片或视频，长按可下载帖子中所有图片或所有视频 |
| | 下载原始尺寸图片 | 从网页版获取最高分辨率；WebP 会转成 JPEG 存入照片 |
| | 下载原始尺寸头像 | 在个人资料长按头像，或全屏查看后点击右下角 ↓ 保存 |
| | 同时下载多个文件 | 下载整篇帖子时，最多同时下载 4 个文件；进度窗口会显示下载速度 |
| | 保存至「Threads」相册 | 下载的项目将同步加入「Threads」相册，首次使用需授予照片「完整访问权限」（默认关闭） |
| | 视频画质 | 最高／720p／每次询问。「最高」从 Threads 的 DASH 流获取最高 1080p 的视频，VP9、AV1 格式会在设备上转码；任何步骤失败都会改下载 720p |
| | 视频格式 | 保留 HDR（HEVC 10-bit，保留 HLG／PQ）或兼容性优先（H.264 SDR） |
| 播放器 | 禁用自动播放 | 浏览动态时，视频不会自动播放，点击后才会开始播放 |
| | 默认播放速度 | 1x／1.25x／1.5x／2x，长按 2 倍速放开后也会回到此速度 |
| 首页动态 | 保留动态位置 | 从后台返回时，首页不刷新、不跳回顶端，也不切换标签页；保留时间可选 10 分钟／30 分钟／不限时间 |
| | 禁用下拉刷新 | 在首页顶端下拉时，不会刷新也不会回弹 |
| | 点首页标签时：不滚回顶端 | 点击首页标签时维持当前位置，不跳回顶端 |
| | 点首页标签时：不刷新 | 位于首页顶端时点击首页标签，不会刷新或加载新帖子 |
| 作者信息 | 显示作者信息 | 在动态中与作者名称一并显示「关于此个人资料」中的信息（默认关闭） |
| | 地点统计 | 依国家统计已读取的作者人数并排序；点击国家可查看作者清单，点作者即可打开其个人资料 |
| | 读取状态与缓存 | 查看已缓存的作者数量、读取是否暂停，并可清除缓存 |
| | 所在地点 | 账号所在的国家或地区，前面显示该国国旗；作者未公开时显示「未分享」 |
| | 加入时间 | 账号加入 Threads 的年月 |
| | 加入编号 | 账号是第几位加入的用户，例如 #7,551,963 或 1 亿+ |
| | 新账号标记 | 最近 2 个月内加入的账号显示绿色「新」标签 |
| | 默认名称标记 | 从未修改注册时系统自动给的账号名称（例如 camel.253044）的账号，显示灰色「默认名称」标签；这不代表是假账号 |
| | 另起一行显示 | 在名称下方多留一行，信息一律完整显示；关闭时改放在名称旁，空间不足会精简或隐藏（默认开启） |
| 隐藏项目：推荐内容 | 推荐账号 | 隐藏动态与个人资料页面的「为你推荐」 |
| | 关注建议 | 隐藏搜索页面的「关注建议」 |
| | 关注对象建议 | 避免自动跳出「关注对象建议」 |
| | 帖子兴趣询问 | 不再询问你对帖子有没有兴趣 |
| 隐藏项目：界面按钮 | 搜索按钮 | 隐藏个人资料页面的搜索按钮（默认关闭） |
| | Instagram 按钮 | 隐藏个人资料页面的 Instagram 按钮（默认关闭） |
| 链接 | 检测剪贴板链接 | 回到 Threads 或切换账号时，检测剪贴板里的 Threads 链接并打开 |
| | 检测到链接时 | 「询问」显示提示（可选上方／中间／下方）；「自动打开」直接跳转 |
| | 使用外部浏览器打开链接 | 帖子与个人简介中的链接改以 Safari 或默认浏览器开启，Threads 链接仍在 App 内打开 |
| 私信 | 不显示已读 | 查看消息时不会通知对方；要让特定聊天室正常显示「已读」，点击聊天室右上角的眼睛图标（默认关闭） |
| | 回复后显示已读 | 开启：回复消息后，对方画面才会显示「已读」；关闭：即使回复，对方画面也不会显示「已读」 |
| | 重置聊天室 | 将通过眼睛图标设为显示「已读」的聊天室，全部恢复为不显示 |
| | 不显示输入中 | 输入消息时，对方不会看到输入提示「…」（默认关闭） |
| | 防止消息撤回 | 对方撤回消息时，消息会保留在聊天室并标示「已撤回」（默认关闭） |
| 界面与交互 | 点赞确认 | 点爱心时会先显示确认提示，取消点赞时不会询问 |
| | 帖子时间格式 | 相对时间／日期时间／含年份／含秒 |
| | 固定底部标签栏 | 滑动时底部标签栏不会自动隐藏 |
| | 复制个人资料信息 | 在个人资料长按姓名、用户名称、个人简介或头像，即可复制相关信息 |
| | 长按首页标签打开设置 | 长按底部的首页标签时，改为打开 ThreadsPulse 设置（默认开启） |
| 备份 | 导出／导入设置 | 将设置导出成 JSON 文件，重新安装或换手机后再导入 |
| 高级 | 调试提示 | 功能异常时开启，画面会显示各功能的运行状态，方便反馈问题 |
| | 分析数据上报记录 | 显示 Threads 收集的使用记录与内容：事件排行与每种事件最新一笔的内容，可复制；记录不会离开你的手机 |
| | 欢迎画面 | 再看一次打开插件设置的方法 |
| | 新功能介绍 | 再看一次这个版本的新功能（更新后首次打开会自动显示一次，可直接开启作者信息） |
| | 自动检查更新 | 每天检查一次 GitHub，有新版本时跳出窗口，可前往下载、稍后提醒或跳过此版本 |
| | 侧载兼容修正 | 重新签名后维持登录与 App 群组数据，仅对重新签名的 App 生效 |

**主题色**：在设置主页最上方的插件信息卡里，点色点即可切换（珊瑚／海洋／薄荷／薰衣草／樱花／琥珀），只改变插件按钮与设置页的颜色。

**语言**：同一张信息卡里可选「跟随系统」、English、繁體中文、简体中文、日本語或한국어，插件自己的文字立即切换，不影响 Threads 本身。

**关于**（主页「备份／高级」卡片最下面一行，旁边直接显示版本号）：显示插件版本、Threads 版本、Bundle ID、机型与 iOS 版本（含构建编号），可一键复制全部信息；另有「检查更新」、GitHub 源代码链接，以及「反馈问题」，会打开 GitHub 新 issue 并自动填入这些信息。「重置所有设置」在这一页最下方。

**设置入口**：Threads「设置」页右上角「〰 Pulse」、长按底部的首页标签，或在任何画面三指长按 1 秒。首次打开 Threads 时会显示欢迎画面说明这些方法。

---

## 上游 IPA 编译流程（参考）

### 事前准备

1. **已解密的 Threads IPA**：这个项目**不提供** Threads 本体，请自行准备。App Store 下载的版本是加密的，不能直接用；必须是已解密的 IPA。
2. **IPA 的直接下载网址**：把 IPA 放到可以直接下载的地方（例如 Dropbox 链接结尾改成 `?dl=1`），用浏览器打开网址时要直接开始下载，而不是显示网页。
3. **签名工具**：用来把产出的 IPA 安装到手机，决定你要选哪个版本（见下方）。

### 两种版本

| 版本 | 适合 | 内容 |
|---|---|---|
| **sideload** | 证书签名：ESign、Feather、Sideloadly＋付费开发者账号等 | 保留 Threads 原本的扩展（小工具、分享等），并加入「Open in Threads」Safari 扩展 |
| **noplugins** | SideStore、AltStore 等**免费 Apple ID** | 移除所有扩展。免费账号无法签名扩展，App ID 数量也有限制 |

**「Open in Threads」Safari 扩展**：侧载的 Threads 收不到通用链接，在 Safari 点 threads.com 链接只会停在网页。这个扩展会把 threads.com／threads.net 的网址转成 Threads App 的链接并自动打开：帖子开到该帖子、个人资料开到该个人资料。
安装后到 **设置 › App › Safari › 扩展**（iOS 17 以前是 **设置 › Safari › 扩展**）开启「Open in Threads」，并允许它在 threads.com 上执行。

### 准备你自己的 repo（二选一）

| 方式 | 优点 | 缺点 |
|---|---|---|
| **Fork**（最简单） | 一键创建；有新版时按 **Sync fork** 就能同步 | Fork 一定是**公开**的 |
| **Import repository**（私有） | 可以设成**私有**，做出来的 IPA 只有你拿得到 | 有新版时要重新导入一次 |

- **Fork**：在本项目页面右上角按 **Fork** → **Create fork**。
  > **公开 repo 的 Artifacts，任何登录 GitHub 的人都能下载**，而做出来的 IPA 含有 Threads 本体。用 Fork 的话，请把 IPA 网址存成 Secret（见下方），并在下载完 IPA 后，到该次执行页面删除 Artifact。
- **Import repository**：GitHub 右上角 **＋** → **Import repository**，**Your old repository's clone URL** 粘贴本项目网址，**Privacy** 选 **Private** → **Begin import**。
  > 私有 repo 的 Actions 有每月免费分钟数限制（macOS 机器分钟数以 10 倍计算），一次编译大约 5～10 分钟。

### 编译步骤

1. 进入你的 repo → **Actions** 标签页。Fork 的 repo 要先按「I understand my workflows, go ahead and enable them」。
2. （建议）把 IPA 网址存成 Secret：**Settings → Secrets and variables → Actions → New repository secret**，名称填 `DECRYPTED_IPA_URL`，值填 IPA 网址。
3. 左侧选 **Build IPA** → 右侧 **Run workflow**：
   - **ipa_url**：IPA 网址。已设置 Secret 就留空。
   - **variant**：`both`（两种都产出，默认）、`sideload`、`noplugins`。
4. 按 **Run workflow**，约 5～10 分钟完成。
5. 点进该次执行，页面最下方 **Artifacts** 下载 `Threads_<版本>_Pulse_<版本>_sideload` 或 `…_noplugins`，解压后就是 IPA。
6. 用你的签名工具安装。Artifact 会在 3 天后自动删除。

**常见错误**

| 错误消息 | 原因 |
|---|---|
| The downloaded file is not an IPA | 网址打开的是网页，不是直接下载 |
| This IPA is not decrypted | 用的是 App Store 加密版本，请换成已解密的 IPA |
| Not enough header space in the executable | 极少见；请反馈 Threads 版本 |

> 请不要把产出的 IPA 上传到公开的 Release 或任何公开位置。

---

## 其他编译方式

### 预编译安装包

请在 [Releases](https://github.com/5hux1n/ThreadsPulse/releases) 下载 Rootless、RootHide 两种 DEB。本分支的发布安装包使用 Xcode 16 在本地编译，不使用上游 Actions 的安装包产出矩阵。

### 本地编译

需要 macOS、Xcode 16、Python 3 与 [Theos](https://theos.dev)。RootHide 安装包使用 [RootHide Theos](https://github.com/roothide/theos) 编译。

```bash
export THEOS=~/theos
make FINALPACKAGE=1            # 只产生 dylib：.theos/obj/ThreadsPulse.dylib
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless    # 产生 Rootless .deb
make -C OpenThreadsSafariExtension FINALPACKAGE=1   # Safari 扩展 → OpenThreadsSafariExtension/.theos/obj/

# 注入已解密的 IPA（只需要 Python 3 与 zip / unzip）
# sideload 版
python3 scripts/inject_ipa.py -i Threads.ipa -d .theos/obj/ThreadsPulse.dylib \
  --appex OpenThreadsSafariExtension/.theos/obj/OpenThreadsSafariExtension.appex -o sideload.ipa
# noplugins 版
python3 scripts/inject_ipa.py -i Threads.ipa -d .theos/obj/ThreadsPulse.dylib \
  --no-plugins -o noplugins.ipa
```

RootHide 请使用对应的 Theos：

```bash
THEOS=~/theos-roothide make clean THEOS_PACKAGE_SCHEME=roothide
THEOS=~/theos-roothide make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

两种安装包输出到 `dist/`，分别为 `ThreadsPulse_<版本>_arm64.deb` 与 `ThreadsPulse_<版本>_arm64e.deb`。

- 使用 Logos `internal` generator，以 ObjC runtime 直接 hook，**不依赖 CydiaSubstrate／ElleKit**，注入 IPA 时不需要另外附上。
- 显示版本号在 `TPVersion.h` 定义；本地化信息位于 `resources/localization/Info.plist`。编译用的 iOS SDK 与最低支持版本在 workflow 的 `SDK_VERSION`、`MIN_IOS`。

### `inject_ipa.py` 做了什么

1. 解开 IPA，把 `ThreadsPulse.dylib` 放进 `Threads.app/Frameworks/`。当前版本已嵌入翻译；可选的 `--bundle` 参数保留给仍需要独立 `ThreadsPulse.bundle` 的旧版使用。
2. 在 Threads 主程序加入一个 `LC_LOAD_DYLIB` 加载指令（`@executable_path/Frameworks/ThreadsPulse.dylib`），已经有就跳过。
3. 检查是否已解密（`LC_ENCRYPTION_INFO_64` 的 `cryptid`），未解密会直接停止。
4. `--appex`：把扩展放进 `PlugIns/`（会去掉里面原有的签名数据）；`--no-plugins`：移除 `PlugIns/`、`Extensions/`、`Watch/`。
5. 重新压成**未签名**的 IPA，由你的签名工具签名。

只用 Python 标准库，不需要安装其他依赖。

---

## 项目结构

```
ThreadsPulse/
├── Makefile
├── control                         安装包信息
├── ThreadsPulse.plist              注入目标（com.burbn.barcelona）
├── Tweak.x                         所有 hook（Logos）
├── TPPrefs.h/.m                    设置访问、默认值、导出导入
├── TPURLCleaner.h/.m               移除网址追踪码
├── TPDownloader.h/.m               网址选择、下载、WebP→JPEG、DASH 1080p（合并／VP9、AV1 转码）、诊断报告
├── TPHUD.h/.m                      进度窗口、toast、提示横幅
├── TPUI.h/.m                       圆形毛玻璃按钮、长按菜单、触感反馈、主题色
├── TPSettingsViewController.h/.m   设置页
├── TPWelcomeViewController.h/.m    首次打开时的全屏欢迎画面
├── TPLocalization.h/.m             TPL() 多语言
├── TPSideloadFix.h/.m              侧载兼容修正（钥匙串、App 群组）
├── TPUpdateChecker.h/.m            从 GitHub Releases 检查新版本
├── vendor/libvpx/                  预先编译的 VP9 解码器（arm64 iOS 静态库）、头文件、授权
├── vendor/dav1d/                   预先编译的 AV1 解码器（arm64 iOS 静态库）、头文件、授权
├── TPVersion.h                     版本号（只在这里改）
├── ThirdPartyLicenses/             引用素材的授权（lee-su-threads）
├── scripts/inject_ipa.py           把插件注入 IPA
├── OpenThreadsSafariExtension/     「Open in Threads」Safari 扩展（只放进 sideload 版）
│   ├── OpenInThreadsHandler.m      原生端（只负责让扩展能被加载）
│   └── Resources/                  content.js（网址转换与跳转）、manifest.json、图标
├── .github/
│   ├── actions/setup-theos/        共用：安装 Theos 与 iOS SDK
│   └── workflows/
│       ├── build.yml               编译插件（zip／deb）
│       └── build-ipa.yml           编译并注入 IPA
└── resources/localization/         编译时嵌入至 ThreadsPulse.dylib
    ├── Info.plist
    ├── en.lproj/Localizable.strings
    ├── zh-Hant.lproj/Localizable.strings
    ├── zh-Hans.lproj/Localizable.strings
    ├── ja.lproj/Localizable.strings
    └── ko.lproj/Localizable.strings
```

## 本地化

- 程序里一律用 `TPL(@"English text")`，**英文原文就是 key**；找不到翻译时直接显示英文。
- 内置语言：英文（`en`）、繁体中文（`zh-Hant`）、简体中文（`zh-Hans`）、日文（`ja`）、韩文（`ko`）。默认跟随系统语言（其他语言显示英文），也可在设置页最上方的「语言」指定。
- 翻译源文件位于 `resources/localization/`；编译时由 `scripts/generate-localization.py` 嵌入 dylib，不需要独立的 `.bundle`。新增语言：复制 `en.lproj` 改名（例如 `fr.lproj`）并翻译，到 `Info.plist` 的 `CFBundleLocalizations` 加上语言代码，再更新语言菜单（`TPSettingsViewController.m`）、`TPLocalization.m` 与生成器的支持语言对应。
- 简体中文、日文、韩文的翻译欢迎母语用户协助修正。

## 实现要点

- **Swift 类**：以 mangled name hook（例如 `_TtC6BCNUFI12BCNUFIButton`），通过 runtime 读取 ivar；读取 Swift enum 内存前会先验证指针与类，避免闪退。
- **批量下载**：从轮播 cell 的数据模型（`BCNFeedMediaViewModel` → `IGPhoto`／`IGVideo`）读取全部项目，不受 cell 重用影响。
- **1080p 视频**：Threads 提供的影音合一 MP4 最高只有 720p，更高画质只在 DASH 清单（`IGVideo.dashManifestData`）里，而且视频流与音频分开。插件挑分辨率最高的视频流与最佳音频（优先 AAC，其次 Opus），下载后在设备上合并：H.264／HEVC 直接沿用（`AVAssetExportSession` passthrough，音频需要重新编码时改用 `AVAssetWriter`）；VP9 用 libvpx 解码；AV1 在支持硬件解码的机型（iPhone 15 Pro 以后，iOS 17+）交给系统的 VideoToolbox 解码，其他机型用 dav1d，再以 VideoToolbox 重新编码——格式代码标示 HLG／PQ 时输出 HEVC Main10（保留 HDR），其他输出 H.264；选「兼容性优先」时先用 `VTPixelTransferSession` 把 HDR 画面转成 BT.709。任何步骤失败都会改下载 720p MP4，不会存成没有声音的视频。一般 MP4 若本身就是 AV1 或 VP9（照片 App 不接受），也会经过同样的转码。下载期间会向系统申请后台运行时间；转码若因切到后台而中断，回到 Threads 后会自动继续。「每次询问」的菜单会出现在点击的下载按钮旁边。
- **同时下载多个文件**：当前项目之后的文件，用第二个 `NSURLSession` 提前下载（3 条连接加上主连接）；存入照片仍依原本顺序。
- **原始图片／头像**：抓 `https://www.threads.com/t/<code>` 或 `/@<username>` 页面，从 JSON 候选网址中以文件名比对出最大尺寸。
- **剪贴板**：先用 `detectPatternsForPatterns:` 判断有没有网址（不会跳出粘贴询问），用户点「打开」或设为自动打开时才读取内容；以 `NSUserActivity`（BrowsingWeb）交给 Threads 自己处理跳转。
- **切换账号**：hook `IGAccountSwitcher`，最后一次切换事件后 1.5 秒检查剪贴板；从其他 App 回到 Threads 则是 0.8 秒。
- **保留动态位置**：让 `applicationWillWarmStartWithTimeIntervalSinceBackgrounded:`（首页与 `BCNAppViewController`）收到 0 秒、回前台前把首页的 `lastBgTime` 设为现在，并把 `IGFeedRefreshInstructionsStore` 的服务器门槛拉高到保留时间。
- **下拉刷新**：在首页的 `scrollViewDidScroll:` 里，用户拖动时不让位置超过顶端，下拉组件就不会触发。
- **点首页标签**：新版标签栏（`BCNLucentTabBarCoordinator`）重复点击同一标签页时，先判断首页是否在顶端，再依开关决定是否让 Threads 处理这次点击（`tabBarController:shouldSelectTab:`、`didSelectTab:previousTab:`、`handleTabBarDoubleTap:`）。旧版标签栏（`BCNLegacyTabBarController`）的判断在 Swift 里拦不到，改成记下点击时间，1 秒内拦截首页的往上滚动与刷新；这组备用 hook 只在第一次点旧版标签栏时才启用。
- **固定底部标签栏**：不让 `BCNLucentTabBarCoordinator` 收到 `scrollViewDidScroll:`／`scrollViewDidEndScrolling:`，并把 iOS 26 的 `tabBarMinimizeBehavior` 设为 never。
- **侧载兼容修正**：加载时存一笔测试数据到钥匙串，读回系统实际指派的访问群组；Team ID 不是 Meta 的（`MH9GU9K5PX`）才启用。改写 App 本身各映像文件（主程序与 `Frameworks/`）符号指针表里的 `SecItemAdd`／`CopyMatching`／`Update`／`Delete`，把 Threads 指定的群组换成实际可用的群组；`containerURLForSecurityApplicationGroupIdentifier:` 返回 nil 时改用 `Library/ThreadsPulseAppGroups/<群组>`。Threads 没有用 iCloud，所以不处理 CloudKit。
- **复制个人资料信息**：可复制姓名（`fullNameLabel`）、用户名称（`usernameLabel`，不含 `@`）或个人简介。在 `BCNProfileHeaderView` 的头像、`fullNameLabel`、`usernameLabel`、`IGProfileBioView` 加上长按手势；个人简介全文取自 `_fullCollapsibleBioString`（折叠时）或 `_stringForView`。功能关闭时手势不会启动，Threads 原本的长按照常运行。
- **隐藏搜索／Instagram 按钮**：在 `BCNProfileViewController` 的 `viewDidLayoutSubviews` 隐藏 `$__lazy_storage_$_searchButton`、`$__lazy_storage_$_appSwitcherButton`，连同只包着它们的外层容器一起隐藏。在 stack view 里会自动靠拢；不在的话，把同一排的其他按钮用 transform 移过去补位（两个都隐藏时取较大的位移，不会重复相加）。
- **推荐账号／关注建议**：`BCNAYMFSectionController`（「为你推荐」区块）依 `placement` 判断位置：0 首页动态、3 个人资料由「推荐账号」控制，2 搜索页由「关注建议」控制。
- **帖子兴趣询问**：`BCNFeedItemSeeMoreSeeLessCell` 高度返回 0 并隐藏，批量询问的 section controller 项目数返回 0。
- **使用外部浏览器打开链接**：拦截 `BCNLinkHandlerImpl` 的两个 `handleLinkWithURL:` 方法（ObjC 协议，调用走 ObjC 派发）。先解开 `l.threads.com` 跳转包装；`threads.net`／`threads.com` 和非网页链接维持原本行为，其他一律用 `-[UIApplication openURL:]` 开启（开启「移除网址追踪码」时会一并清掉追踪参数）。
- **三指长按**：手势识别器同时识别、开始时暂时禁用同一批触控上的其他手势，避免放开手指后又触发原本按到的按钮。
- **长按首页标签打开设置**：拦截 `-[BCNLucentTabBarCoordinator handleTabBarLongPress:]`。长按一开始落在第一个（首页）标签按钮上时，打开 ThreadsPulse 设置并吃掉这次手势的后续；长按其他标签（例如个人资料标签切换账号）照常运行。
- **不显示已读**：调用 `+[BCNSlideMDCoreMarkThreadReadMutationBuilder builderWithOfflineThreadingId:threadFbid:timestampMs:]` 时，把时间换成这个聊天室已经让对方知道的位置（没有就是 0），服务器上的已读位置不会往前移，也不会往回退；你自己这边照常当作已读。聊天室右上角的眼睛图标可以让个别聊天室照常送出。
- **回复后显示已读**：Threads 创建要送出的消息（`BCNSlideOutgoingMessagePayload`）或对消息的动作（`BCNSlideOutgoingMessageUpdatePayload`）时，用记下的参数重新创建已读请求，通过 Threads 自己送已读的 GraphQL 服务送出。消息会在 `-[MDCoreSendService sendMutationWithAppDataModel:…]` 暂停，等服务器收下「已读」才放行（最多 0.8 秒），让对方先看到「已读」再收到回复。
- **不显示输入中**：`+[BCNTypingIndicatorPublishEventMutationBuilder builderWithActivityStatus:threadId:]` 的状态一律改成 0（停止输入），聊天室编号不变，不影响即时收消息。
- **防止消息撤回**：对方撤回消息时，由 Swift 的 `BCNSlideDeleteMessageHandler` 处理，它通过 `MDCoreDeltaApplyingBridge`（创建时带着处理器的类型名称）修改本地数据库。开关开启时，把这个处理器从 `mutationCommandsForDeltaWithRequestedState:…` 返回的删除指令拿掉，消息就会留在你的手机上，并立即在消息下方标示「已撤回」（之后关闭开关，标示也会保留）。已经被删掉的消息，或聊天室从服务器整个重新加载后消失的，无法救回。
- **阻止分析数据上报**：使用记录在收集阶段就丢掉（`-[FBAnalyticsCoreLogger _captureAnalyticsEvent:]`、`_captureAnalyticsEventForBatchUpload:`，`_shouldStreamEvent:` 返回 NO）；之前已存着的记录上传时，改用 Meta 自己的 `FBAnalyticsNoOpNetworkConfigurator` 取代 `IGAnalyticsNetworkConfigurator`，不会发出网络要求。登录、发帖、加载动态等正常 API 不经过这里。
- **分析数据上报记录**：在 `_captureAnalyticsEvent:` 记下 `FBAnalyticsEvent` 的 `eventName` 次数，以及每种事件最新一笔的事件对象；开启记录时才读取 `eventPayload`。只存在内存，关闭 App 就清空。
- **禁用自动播放**：动态里的视频滑进画面时（`-[IGFNFVideoPlayer playWithReason:callsiteContext:]`，原因代码 1），照常让 Threads 走完播放流程，界面（包括声音图标）才会正常出现，但把底层的 `FNFPlayer` 按住：第一次 `play` 以音量 0 试播，让 Threads 走到「开始播放」并显示声音图标，接着在第一帧暂停（`videoPlayerDidInitialPlay:`）；之后的 `play` / `playWithContext:` 一律忽略。点一下视频（手指几乎没移动，所以滑动不算）才放开并让 `FNFPlayer` 开始播放。其他原因（例如全屏）和不在动态里的视频照常播放。开始播放后同一个播放器不再按住，直到它被停止。单个视频下载改成先从附近的数据对象找网址，没播放过的视频也能下载。
- **作者信息**：调用 Threads 自己的 `BKSharedAsyncActionDataFetcher`，以 `com.bloks.www.text_post_app.about_this_profile_async_action` 获取「关于此个人资料」，从返回的 Bloks 版面中解析国家（`about_this_profile_country` 状态）与「已加入」字段。请求需要一个带登录身份的 `BKObjectSet`：启动时记下 `IGUserSession` 与 `PNPandoGraphQLService`，自行组成（含 `IGSessionContext`），首次尝试若闪退会自动禁用，改为借用 Threads 打开 Bloks 页面时创建的对象集。作者 ID 取自 `BCNFeedItemHeaderProfilePicture` 的 Swift `userPk`。速率限制保护：一次一位、间隔 1.5 秒、排队上限 10、每次启动最多 400 次；收到 429、`feedback_required`、spam 等响应时暂停 1 小时；有地点的结果缓存 21 天，没有的 1 天。另起一行显示：在 `BCNFeedSectionController` 创建名称列 cell 时记下列位置，于 `sizeForItemAtIndex:` 加上一行高度后重新排版。
- **隐藏关注对象建议**：`BCNUserRecommendationsViewController` 以弹出方式出现时拦截 `presentViewController:`；推入的页面不受影响。

## 注意事项

Threads 更新后，部分功能可能会暂时失效（不会闪退）。开启「调试提示」可以看出是哪一项，欢迎反馈。

## 第三方库

| 库 | 用途 | 许可证 |
|---|---|---|
| [libvpx](https://chromium.googlesource.com/webm/libvpx) | VP9 解码 | BSD 3-Clause（`vendor/libvpx/LICENSE`、`PATENTS`） |
| [dav1d](https://code.videolan.org/videolan/dav1d) | AV1 解码 | BSD 2-Clause（`vendor/dav1d/COPYING`） |

两者都以预先编译的静态库内附，确切版本与编译选项记录在各文件夹的 `VERSION.txt`。

### 致谢

「作者信息」（在动态显示所在地点、加入时间与新账号标记）参考 meettomorrow 的 [lee-su-threads](https://github.com/meettomorrow/lee-su-threads)（MIT 许可证）。代码为 ThreadsPulse 自行撰写，但沿用该项目的做法（标签解析、缓存期限、1 小时速率限制暂停），以及其默认名称判断规则与动物字词表。许可证全文附在 `ThirdPartyLicenses/lee-su-threads.txt`。

## 免责声明

1. 本项目为独立开发之非官方软件，与 Meta Platforms, Inc.（以下简称「Meta」）及 Apple Inc. 无任何隶属、合作、授权或背书关系。「Threads」及其相关标志为 Meta 之商标，本项目使用该名称仅用于说明兼容对象。
2. 本项目不包含、亦不散布 Threads 应用程序或其任何组成部分。用户应自行合法获取所需文件，且不得公开散布经修改之应用程序。
3. 修改第三方应用程序可能违反该服务之使用条款，并可能导致账号遭限制、禁用或其他后果，相关风险由用户自行评估及承担。
4. 通过本项目下载之内容，其著作权归原权利人所有。用户仅得于法律允许之范围内作个人用途使用，不得侵害他人权利。
5. 本项目依「现状」提供，不附带任何明示或默示之担保。对于因使用或无法使用本项目所生之任何直接、间接、附带或衍生损害，作者概不负责。
6. 用户下载、编译或使用本项目，即视为已阅读、理解并同意本声明之全部内容。

## 作者

h4x_0x30vm · [Ko-fi](https://ko-fi.com/mumuisdog)

二改优化：[Junhong](https://mjh.im/)

© 2026 h4x_0x30vm，保留所有权利。
