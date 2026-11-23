# 音乐附件再次失效：410 动态分析（2026-11-22）

## 结论

不是解析代码被改坏，也不是 cell hook 掉了：**服务端不再下发音频资产**。
当前账号（中国大陆）拿到的 `text_app_music_info` 已被版权/地域标记整段裁剪，
`music_consumable_video` 里只剩 `media_id`、起点和歌词类型，
`audio_metadata → audio_asset → dash_manifest` 全部消失，
同时 `is_available_for_consumption` 为 `false`。

旧代码第一个判断就是 `is_available_for_consumption`，于是 `TPMusicAttachment` 返回 `nil`，
关联对象被清空，`TPMusicLayoutCell` 走 `!attachment` 分支把按钮移除、tombstone 文案恢复——
表现正是“识别不了”。

## 现场证据

设备：iPhone 14 Pro（iOS 16.3，Dopamine RootHide），Threads `410.0.0 (843083167)`。
方式：USB Frida 17.7.3 + `frida_tools` 自带 ObjC bridge（Frida 17 已移除内置桥）。

1. tweak 已注入且 hook 生效：`IGMedia -updateWithDictionary:` 与
   `BCNFeedNestedPostCell.BCNFeedDeletedQuotedAttachmentCell -layoutSubviews`
   的 IMP 都落在 `ThreadsPulse.dylib` 内（`0xede2c` / `0xede98` 偏移），`TPMusicAttachment` 类在进程里。
2. 目标 cell 现状（`recursiveDescription`）：

   ```
   BCNFeedDeletedQuotedAttachmentCell frame = (0 673.667; 393 69)
     └ BCNFeedTombstoneView frame = (64 8; 317 53)
         └ IGCoreTextView text = '这里有新内容。更新应用即可查看：音乐附件'
   ```

   tombstone 仍在，说明 App 自己知道这是音乐附件、只是拒绝渲染。
3. `TPMusicAttachment +attachmentWithDictionary:` 冷启动被调用 20+ 次，全部返回 `nil`，
   入参就是下面这个结构（`NSJSONSerialization` 原样导出）：

   ```json
   {
     "muted_reason": "DENY_IF_NOT_IN_MR_LAUNCHED_GEOS",
     "music_consumable_video": {
       "audio_overlap_duration_in_ms": 0,
       "media_id": "4035721295623286158",
       "audio_start_time_in_ms": 61000,
       "audio_start_time_in_composition_in_ms": 0,
       "lyrics_usage_type_as_string": "NO_USAGE"
     },
     "is_available_for_consumption": false,
     "error_code": "MUSIC_RIGHTS_NOT_LAUNCHED_COUNTRY"
   }
   ```

4. 样本量：冷启动首页 23 条 + 用 frida 驱动 `BCNFeedCollectionView` 滚动加载后 14 条，
   共 37 条媒体、26 个不同的音乐附件，**26/26 全为同一形态**：
   `music_consumable_video` 键集合固定为
   `audio_overlap_duration_in_ms / audio_start_time_in_composition_in_ms /
   audio_start_time_in_ms / lyrics_usage_type_as_string / media_id`，
   `is_available_for_consumption = false`，`error_code = MUSIC_RIGHTS_NOT_LAUNCHED_COUNTRY`，
   没有任何一条含 `audio_metadata` 或 `dash_manifest`。
5. `media_id` 等于该条 media 自己的 `pk`（如 `4035721295623286158`），是帖子媒体 id，
   不是歌曲 id，无法据此反查曲目。
6. 整条 media 字典里与音乐相关的只剩 `text_app_music_info` 与 `music_metadata`（恒为 `null`），
   即 `music_metadata.music_info.music_asset_info` 这条路也不可用。
7. App 数据目录（flash cache v7 sqlite、网络磁盘缓存、IGImageCache 外的全部文件）全量扫描：
   `text_app_music_info`、`music_consumable_video` 只出现在字段名表里，
   **整个 App 数据目录没有一处 `audio_metadata`**，说明这不是“本地缓存过期”，而是服务端已经不再下发。
8. 顺带核对了容易误判的第二处：410 的 `BCNFeedDeletedQuotedAttachmentCell` 自身只有
   `tombstoneView`、`threadline` 两个 ivar，但父类 `BCNFeedBaseCell` 有 `media`，
   `TPDownloader ivarValue:` 会沿父类链找到，因此原 cell 取 media 的写法在 410 仍然有效。

## 能改与不能改

- **不能改**：payload 里没有音频 URL，客户端拿不到可播放资源。这不是 hook 点或解析路径问题；
  换 region/账号或服务端恢复下发后才会重新有声音。任何“让按钮出现”的改动都只能显示一个点了没反应的空壳。
- **能改**（本轮已落地）：
  1. 解析不再写死 `audio_metadata → audio_asset` 这条单一路径，改为在整段 `text_app_music_info` 里
     递归找 `dash_manifest`（限深 6）并按音频 MPD 规则校验，schema 再套一层也不会失配；
     `display_title` / `display_artist` / `audio_start_time_in_ms` 同样支持 `title` / `artist` 兜底。
  2. `is_available_for_consumption` 缺失（部分更新）不再直接判死，只有显式 `false` 才拒绝，
     且拒绝原因会进诊断。
  3. 新增 `+[TPMusicAttachment diagnosticsForDictionary:]`：`recognized / denied / manifests /
     playable / title / error / muted` 七个字段，把“服务端标记”和“解析失败”分开。
  4. `TPMusicUpdateMedia` 在调试开关打开时按不同原因各提示一次
     （最多 8 条，`[TP] music muted · MUSIC_RIGHTS_NOT_LAUNCHED_COUNTRY`），
     下次服务端再动 payload，第一眼就能看到原因，不必再猜。
  5. `TPMusicLayoutCell` 的 tombstone 文案不再依赖 `label` ivar：410 用的是 `IGCoreTextView`，
     改为在 `tombstoneView` 子视图里找文本视图；`tombstoneView` 缺失时退化为覆盖整个 cell。

## 复现与回归

```bash
# 解析单测（payload 形态、递归兜底、地域标记）
bash scripts/test-music-attachment.sh

# 真机抓取当前 payload 形态（默认冷启动首页，--scroll 会驱动列表继续加载）
python3 scripts/probe-music-payload.py --scroll --seconds 40 --out /tmp/music-samples.jsonl
```

判定标准：

- 若 `probe` 输出里出现 `manifests >= 1` 且 `playable: true`，播放按钮应正常出现；
- 若仍是 `denied: true / manifests: 0`，即服务端仍在裁剪，属预期，不是回归。
