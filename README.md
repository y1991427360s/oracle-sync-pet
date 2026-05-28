# Oracle-Sync 桌宠 — 新电脑接入

只要这台电脑已经通过 Syncthing 同步到 `tools\pets\` 这个目录，就只需要跑一次安装命令。

## 安装

按 `Win + R`，粘贴下面这行（替换为你本机的同步根目录路径）：

```
powershell -ExecutionPolicy Bypass -File "D:\Syncthing\Oracle-Sync\tools\pets\install-pet.ps1"
```

回车。脚本会做两件事：

1. 立即启动桌宠 —— 屏幕上会出现一只 🐰
2. 在登录启动项里放快捷方式 —— 之后每次开机自动出现

## 操作

| 操作 | 效果 |
|---|---|
| 左键拖 | 移动位置（位置自动记住，下次启动还在原位）|
| 左键单击 | 打开/激活 Oracle-Sync 文件夹 |
| 右键 | 弹出菜单：打开文件夹 / 查看同步状态 / 暂停或恢复同步 / 回到屏幕中央 / 立即提醒喝水 / 退出 |
| 鼠标悬停 | 放大反馈 |
| 悬停右下角小圆点 | 显示 Syncthing 当前同步状态详情 |
| 闲置 | 每隔 3–6 秒随机做一个动作（跳/晃/转/点头/抖）|
| 点气泡 | 立即关掉当前气泡 |

## Syncthing 同步状态指示

桌宠右下角有一颗小圆点，实时反映本机 Syncthing 对 `Oracle-Sync` 这个文件夹的同步状态：

| 颜色 | 含义 |
|---|---|
| 🟢 绿 | 已同步完成，且至少有一台对端在线 |
| 🟠 橙 | 已同步完成，但对端目前都不在线 |
| 🟡 黄（脉动）| 正在同步 / 正在扫描 |
| 🔵 蓝 | 已被用户主动暂停 |
| 🔴 红 | Syncthing 没在跑，或 API 报错 |
| ⚪ 灰 | 没找到 Syncthing 配置 |

鼠标悬停在小圆点上能看到详细文字（例如"同步中 · 剩 12.3 MB / 5 项"、"已同步 · 与 1 台设备相连"）。状态切换时会主动弹气泡告诉你（开始同步 / 同步完成 / Syncthing 挂了）。也可以右键 → "查看同步状态" 立即查看一次。

## 暂停 / 恢复同步

如果想临时关掉 `Oracle-Sync` 的同步（比如电量紧张或网络忙），右键桌宠 → **⏸ 暂停同步**。再次右键时菜单会自动变成 **▶ 恢复同步**，点一下即可恢复。小圆点也会同步变蓝/恢复原色。

这只暂停 `Oracle-Sync` 这一个文件夹，**不会**停掉 Syncthing 本身——其它文件夹和对端连接照常工作。底层走的是 Syncthing REST API（`PATCH /rest/config/folders/oracle-sync` 改 `paused` 字段），等同于在 Web UI 上点"暂停"。

如果连 Syncthing 进程本身都关了，桌宠没法把它拉起来——需要手动启动（Web UI、计划任务"Syncthing"，或直接跑 `syncthing.exe --no-console --no-browser`）。

无需额外配置：桌宠会从本机 `%LOCALAPPDATA%\Syncthing\config.xml` 实时读取 API key 和 folder id，每 5 秒轮询一次本机 `127.0.0.1:8384`。

## 自动提醒

- **喝水提醒**：每 40 分钟自动弹一个气泡提示喝水，必须点击气泡才会消失。想立即测一下：右键 → "立即提醒喝水"。
- **CLI 任务完成提醒**：每次 Claude Code 或 Codex CLI 完成一轮对话，桌宠会弹气泡告诉你"✅ 任务完成"，必须点击气泡才会消失。需要一次性配置（见下）。

### 给 Claude Code / Codex 接通完成提醒（每台电脑配一次）

桌宠的通知投递箱在 `%LOCALAPPDATA%\OracleSyncPet\notify\`，任何程序往里写 `*.txt` 都会触发气泡。Claude Code 和 Codex 用各自的 hook 机制调用 `tools\pets\notify-pet.ps1`：

**Claude Code** — 编辑 `~/.claude/settings.json`，在顶层加：
```json
"hooks": {
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"D:\\Syncthing\\Oracle-Sync\\tools\\pets\\notify-pet.ps1\" -Message \"✅ Claude Code 任务完成\""
        }
      ]
    }
  ]
}
```

**Codex CLI** — 编辑 `~/.codex/config.toml`，在顶层（任何 `[xxx]` 段之前）加：
```toml
notify = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "D:\\Syncthing\\Oracle-Sync\\tools\\pets\\notify-pet-codex.ps1"]
```

注意：
- 路径写死了 `D:\Syncthing\Oracle-Sync\tools\pets\`，如果同步根在别的盘符要相应改一下。
- 改完配置**只对新开的 CLI 会话生效**，当前正在跑的会话不会弹气泡。
- 这两份配置在用户私有目录，不走 Syncthing，每台电脑都要单独配。

## 关闭后怎么再打开

- 双击 `tools\pets\pet.vbs`，或
- `Win+R` → `wscript "D:\Syncthing\Oracle-Sync\tools\pets\pet.vbs"`，或
- 注销/重启电脑（自启会拉起来）

## 永久卸载

```
powershell -ExecutionPolicy Bypass -File "D:\Syncthing\Oracle-Sync\tools\pets\uninstall-pet.ps1"
```

会停掉当前进程并删除登录自启快捷方式。`tools\pets\` 里的脚本本身不删，方便以后想用再装。

## 换形象

把任意一张透明背景 PNG（建议 96×96 或更大）保存为 `tools\pets\pet.png`，下次启动桌宠会自动用这张图代替 emoji。因为 `tools\pets\` 在同步目录里，所有电脑会自动收到同一只桌宠。
