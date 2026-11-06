# Oracle-Sync 桌宠 — 新电脑接入

只要这台电脑已经通过 Syncthing 同步到 `tools\pets\` 这个目录，就只需要跑一次安装命令。

## 安装

按 `Win + R`，粘贴下面这行（替换为你本机的同步根目录路径）：

```
powershell -ExecutionPolicy Bypass -File "D:\Syncthing\Oracle-Sync\tools\pets\install-pet.ps1"
```

回车。脚本会做三件事：

1. 立即启动桌宠
2. 在登录启动项里放快捷方式 —— 之后每次开机自动出现
3. 给 Claude Code 接上"任务完成"气泡提醒（按本机实际路径写入，见下文）

重复运行是安全的。只想装桌宠、不动 Claude/Codex 配置时加 `-NoHooks`。

## 其他电脑怎么更新

已经装过桌宠的电脑**不需要重新安装**。脚本会通过 Syncthing 自动同步过去，只是正在运行的桌宠仍是旧代码，重启一次就生效：

1. 确认这台电脑已经同步完成：桌宠右下角小圆点为绿色，或在 Syncthing 管理页看到 `Oracle-Sync` 显示“最新”。
2. 按 `Win + R`，粘贴下面这行后回车（同步根不在 D 盘的电脑要改路径，例如笔记本 YSLaptop 是 `E:\Syncthing\Oracle-Sync`）：

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Syncthing\Oracle-Sync\tools\pets\restart-pet.ps1"
   ```

   它会结束旧桌宠，再让资源管理器启动新的。也可以右键桌宠 → **退出桌宠**，再双击 `tools\pets\pet.vbs`。

3. 重启后右键桌宠看一眼菜单，能正常弹出就说明已更新。

下面两种情况才需要再跑一次 `install-pet.ps1`：

- 这台电脑还没装过桌宠，或者开机后桌宠不会自动出现（登录启动项丢失）。
- Claude Code / Codex 跑完任务后桌宠没有弹“任务完成”气泡（hook 配置在每台电脑的用户目录里，不走同步）。

> 2026-10-21 这次更新的内容：新增 `restart-pet.ps1`，修复 `uninstall-pet.ps1` 运行时会把自己也结束掉、导致自启快捷方式和 hook 删不掉的问题。其他电脑按上面第 2 步重启即可。

## 操作

| 操作 | 效果 |
|---|---|
| 左键拖 | 移动位置（位置自动记住，下次启动还在原位）|
| 拖到屏幕左/右外侧边缘松手 | 贴边并半隐藏；鼠标移上去会探出来，离开 1.2 秒后缩回 |
| 左键单击 | 缩放互动动画（打开文件夹请用右键菜单） |
| 单击右下角小圆点 | 打开 Syncthing 网页管理界面（`http://127.0.0.1:8384`）|
| 右键 | 弹出菜单（见下）|
| 鼠标悬停 | 放大反馈；悬停小圆点显示同步状态详情 |
| 闲置 | 每隔 3–6 秒随机做一个动作（跳/晃/转/点头/抖）|
| 点气泡 | 有排队的消息就显示下一条，否则收起 |

右键菜单从上到下：

- 状态信息行：当前同步状态 + 最近同步时间和文件名（只显示，不可点）
- 打开 Oracle-Sync / 打开 Syncthing 管理页
- 查看同步状态 / 暂停或恢复同步 / 同步冲突文件（有冲突时才出现，红色）
- 切换皮肤：5 款皮肤即时切换（默认形象、特锐德牌子、特锐德机器人、特来电机器人、特来电牌子），自动记住上次选择
- 立即提醒喝水 / 已喝水，恢复显示 / 5 分钟后再提醒 / 勿扰 1 小时
- 回到屏幕中央 / 退出桌宠

## Syncthing 同步状态指示

桌宠右下角有一颗小圆点，实时反映本机 Syncthing 对 `Oracle-Sync` 这个文件夹的同步状态：

| 颜色 | 含义 |
|---|---|
| 🟢 绿 | 已同步完成，且至少连接了一台同步设备 |
| 🟠 橙 | 本机无待同步项，但未连接到同步设备；不代表服务器关机 |
| 🟡 黄（脉动）| 正在同步 / 正在扫描 |
| 🔵 蓝 | 已被用户主动暂停 |
| 🔴 红 | Syncthing 没在跑，或 API 报错 |
| ⚪ 灰 | 没找到 Syncthing 配置 |

鼠标悬停在小圆点上能看到详细文字（例如"同步中 · 剩 12.3 MB / 5 项"、"已同步 · 与 1 台设备相连"），以及"最近同步：今天 14:32 · 文件名"。状态切换时会主动弹气泡告诉你（开始同步 / 同步完成 / Syncthing 挂了）。也可以右键 → "查看同步状态" 立即查看一次。

无需额外配置：桌宠会从本机 `%LOCALAPPDATA%\Syncthing\config.xml` 读取 API key 和 folder id，每 3 秒在后台轮询一次本机 `127.0.0.1:8384`，不会卡住桌宠。

## 同步冲突提醒

两台电脑同时改了同一个文件时，Syncthing 会保留一份 `文件名.sync-conflict-日期-时间-设备.扩展名` 副本，很容易被忽略。桌宠启动 1 分钟后开始在后台扫描同步目录（之后每 10 分钟一次，跳过 `.stversions`、`.git`、`node_modules`），发现**新的**冲突文件就弹气泡提醒。

右键 → **同步冲突文件（N）** 会在资源管理器里定位第一个冲突文件，并在气泡里列出前几个的路径。对比内容后保留需要的版本、删掉冲突副本即可，菜单项会在下次扫描后自动消失。

## 暂停 / 恢复同步

如果想临时关掉 `Oracle-Sync` 的同步（比如电量紧张或网络忙），右键桌宠 → **暂停同步**。再次右键时菜单会自动变成 **恢复同步**（图标同步切换），点一下即可恢复。小圆点也会同步变蓝/恢复原色。请求在后台执行，Syncthing 响应慢时桌宠也不会卡住。

这只暂停 `Oracle-Sync` 这一个文件夹，**不会**停掉 Syncthing 本身——其它文件夹和对端连接照常工作。底层走的是 Syncthing REST API（`PATCH /rest/config/folders/oracle-sync` 改 `paused` 字段），等同于在 Web UI 上点"暂停"。

如果连 Syncthing 进程本身都关了，桌宠没法把它拉起来——需要手动启动（Web UI、计划任务"Syncthing"，或直接跑 `syncthing.exe --no-console --no-browser`）。

## 气泡与勿扰

- 气泡都需要点击才收起。连续收到多条通知时会**排队**，气泡底部显示"还有 N 条"，点一下看下一条；重复的同一条消息只留一份。
- 同步状态播报（开始同步 / 同步完成）不会挡住未读的任务通知；挡住时直接跳过，小圆点仍会更新。
- **勿扰 1 小时**：暂停所有自动气泡和喝水滤镜，桌宠变半透明。期间收到的任务通知和冲突提醒先攒着，勿扰结束后依次弹出。再次右键可以提前结束。

## 自动提醒

- **喝水提醒**：给所有显示器叠加 20% 透明度的淡蓝色滤镜，不影响鼠标和键盘操作。右键桌宠 → **"已喝水，恢复显示"** 关闭并重新计时；**"5 分钟后再提醒"** 暂时关闭，5 分钟后再出现。想立即测一下：右键 → "立即提醒喝水"。退出桌宠也会移除滤镜；不修改系统颜色设置。
  - 只累计**人在电脑前**的时间：累计满 30 分钟才提醒。2 分钟以上没有键鼠操作会暂停计时；离开 10 分钟以上视为已经休息，计时清零。
  - 到点时如果正处于勿扰、锁屏、全屏程序或演示模式，会推迟到这些情况结束后再提醒。
  - Windows 安全桌面及独占全屏程序不保证覆盖。
- **立即预览滤镜**：运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\pet.ps1 -WaterPreview`（已有桌宠运行时需先退出）。
- **CLI 任务完成提醒**：每次 Claude Code 或 Codex CLI 完成一轮对话，桌宠会弹气泡告诉你"✅ 任务完成 · 项目名"。

### Claude Code / Codex 完成提醒的配置

桌宠的通知投递箱在 `%LOCALAPPDATA%\OracleSyncPet\notify\`，任何程序往里写 `*.txt` 都会触发气泡；`tools\pets\notify-pet.ps1` 是统一的投递入口（`-Message "文字"` 直接投递，或 `-Source "名称"` 自动生成"✅ 名称 任务完成"）。

**Claude Code** — `install-pet.ps1` 会自动处理：在 `~/.claude/settings.json` 的 `hooks.Stop` 里**追加**一条调用 `notify-pet.ps1 -Source "Claude Code"` 的 hook，路径按本机实际位置写入（同步根在 E 盘也没问题）。已有的其他 Stop hook（比如 Bark 手机通知）原样保留；修改前会备份为 `settings.json.bak-时间戳`。hook 会从 Claude Code 传来的数据里取当前项目文件夹名，显示在气泡里。

**Codex CLI** — Codex 的 `notify` 只能配一个程序。`install-pet.ps1` 只在 `~/.codex/config.toml` 还没有 `notify` 时自动写入；已被别的程序（比如 ChatGPT 桌面端）占用时不会改动，只给出提示。手动配置方式（写在任何 `[xxx]` 段之前）：
```toml
notify = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "D:\\Syncthing\\Oracle-Sync\\tools\\pets\\notify-pet-codex.ps1"]
```

注意：改完配置**只对新开的 CLI 会话生效**；这两份配置在用户私有目录，不走 Syncthing，每台电脑都要跑一次安装脚本。

## 关闭后怎么再打开

- 双击 `tools\pets\pet.vbs`，或
- `Win+R` → `wscript "D:\Syncthing\Oracle-Sync\tools\pets\pet.vbs"`，或
- 注销/重启电脑（自启会拉起来）

**让 AI 工具帮你重启桌宠时**，请它运行 `restart-pet.ps1`，不要让它直接启动 `pet.vbs`。直接启动的桌宠会挂在那个工具下面，工具退出、更新或清理后台任务时，桌宠会被一起结束，看起来就像“莫名其妙被关掉”或“打开就秒关”。这种情况下 `exit.log` 里只有 `start`，没有任何退出记录。

## 永久卸载

```
powershell -ExecutionPolicy Bypass -File "D:\Syncthing\Oracle-Sync\tools\pets\uninstall-pet.ps1"
```

会停掉当前进程、删除登录自启快捷方式，并从 Claude Code 配置里摘掉桌宠的通知 hook（其他 hook 保留；加 `-KeepHooks` 则不动）。`tools\pets\` 里的脚本本身不删，方便以后想用再装。

## 换形象

把任意一张透明背景 PNG（建议 96×96 或更大）保存为 `tools\pets\pet.png`，下次启动桌宠会自动用这张图代替 emoji。因为 `tools\pets\` 在同步目录里，所有电脑会自动收到同一只桌宠。

换图后如果阴影、状态点、气泡的位置不贴合，可以调整 `pet.ps1` 里的 `$shadowXaml`、`$dotXaml`、`$bubbleOffset`，再用预览脚本看效果（见下）。

## 预览界面

改了界面样式后，不用重启桌宠就能看效果：

```
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\Syncthing\Oracle-Sync\tools\pets\preview-ui.ps1"
```

会把桌宠本体、气泡、右键菜单分别渲染成 PNG，放到 `%TEMP%\OracleSyncPetPreview\` 并打开该文件夹（`-OutDir` 指定目录，`-NoOpen` 不打开）。

## 日志

都在 `%LOCALAPPDATA%\OracleSyncPet\`：`exit.log`（启动/退出原因）、`water.log`（喝水提醒）、`notify-pet.log`（收到的通知）、`codex-notify.log`。单个日志超过 256 KB 时，桌宠启动后会自动只保留最近 1000 行。
