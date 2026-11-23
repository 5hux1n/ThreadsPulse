# 410 / 456 同步赞助内容遗漏分析

## 结论与范围

两个本地解密二进制均存在一条绕过原插件广告 hooks 的同步插入路径。当前主线保留上游 1.31.0 的全部广告拦截，并增加了 410 的旧版回调；未发现广告代码在移植时遗漏。截图设备的客户端版本未知，尚未动态确认截图广告经过此路径。

## 静态调用证据

| 位置 | 410 | 456 |
| --- | --- | --- |
| BCNMainFeedAdsDeliveryManager 同步插入函数 | `0x102070CE8` | `0x100ADDC0C` |
| 同步路径的 Swift 直接调用点 | `0x102070F80` | `0x100ADDFAC` |
| processSponsoredItems 的 Swift 实现 | `0x101CBABD0` | `0x100CC7160` |
| 被绕过的 processSponsoredItems ObjC wrapper | `0x100D74038` | `0x1036CCEA4` |
| IGAdInsertionHandler 的共同投放 IMP | `0x1012F5ED8` | `0x100CD0708` |

同步函数创建 `BCNAdSyncInsertionInterceptor`，临时替换广告插入 delegate / data source，直接调用 Swift 实现。它因此绕过 manager 的 ObjC hook，也绕过原 `BCNMainFeedAdsInsertionSurfaceHandler` 回调。同步调用返回后，恢复原 delegate / data source，再读取 interceptor 的 insertions 并插入信息流。

Swift 实现仍通过 `objc_msgSend` 调用 `IGAdInsertionHandler` 的共同方法：

```objc
-deliverSponsoredItemsWithPosts:deliveryContext:containerModule:surfaceExtraLoggingDicts:extraLoggingDict:requestMetadata:adRequestExtraInfo:acpContext:
```

两版 encoding 均为 `v80@0:8@16Q24@32@40@48@56@64@72`，返回 void，`deliveryContext` 为 unsigned long long，其余七个业务参数为对象。456 的 selector 装载位于 `0x100CC7214/18`，`objc_msgSend` 位于 `0x100CC7230`。

已有 `adPlatformDidDeliverSponsoredItem:atAdRequestIndex:` hook 对应的原函数在两版均为空实现，不能将它算作有效的最后屏蔽层。

## 本轮最小修改与验证

只在原 Ads group 内新增共同投放方法的 hook：去广告开启时提前返回，关闭时原参数完整调用原实现。保留全部旧 hooks，不使用固定地址，不按界面文字隐藏视图。上述地址仅供分析复核，不写入插件。

`scripts/test-ad-delivery.sh` 从生产代码提取该 hook，用实际 Logos internal 生成器在本机编译运行，验证开关开启阻断、关闭放行及再次关闭后的恢复，覆盖所有对象参数和高位 64-bit context。它是本地 stub 测试，不是设备流量或真实广告验收。作者资料及音乐测试另行回归。
