# gl启动器

一个使用 **Godot 4.7+ / GDScript** 编写的第三方、非官方本地启动器，只做启动相关的事情：

> 仓库地址：<https://github.com/glgl6688/gl-MC-launcher>  
> 下载器：<https://github.com/glgl6688/gl-MC-downloader/>

- 添加多个游戏文件夹，按文件夹显示可折叠的版本树；
- 每个版本自动使用自己的目录保存配置（`gl-instance.json`），不需要实例名或实例选择；
- 发现本地 `versions` 下的版本，版本名严格使用版本文件夹名；
- 自动/手动选择 Java，组装 JVM 参数与游戏参数；
- 游戏目录固定为 `<游戏文件夹>/versions/<版本文件夹>`，存档从该目录的 `saves/` 读取；
- 支持第三方 Yggdrasil（LittleSkin 等）与正版 Microsoft 设备码登录；
- 版本树直接显示每个版本的 Mod/光影/材质/存档数量，可确认后移出组件；
- 导入 `.mrpack` 中本地已有的部分，复制 Mod / 光影 / 材质；
- 启动器配置、令牌、日志都放在启动器目录，不写 AppData；
- 日志不在底部显示，底部保留「说明书」「免责声明」「下载器链接」三个按钮；
- 所有文件/文件夹选择使用系统原生对话框。

> 本项目不包含、不下载、不分发任何游戏本体、运行库、资源文件、贴图、字体或商标素材；与游戏开发商、发行商及官方启动器没有任何关联。第三方登录只访问用户填写的 Yggdrasil 服务器；正版登录直接访问 Microsoft/Xbox 服务，不经过任何中转服务器。

## 功能边界

| 功能 | 是否实现 | 说明 |
|---|---|---|
| 多游戏文件夹 + 版本树 | 是 | Tree 控件，每个文件夹是父节点，可折叠；版本名用文件夹名 |
| 版本发现 | 是 | 只读 `versions`，校验 `<id>.json` 与 `<id>.jar` |
| 版本设置持久化 | 是 | 保存在版本目录的 `gl-instance.json`，自动保存 |
| 游戏目录 | 固定 | `<游戏文件夹>/versions/<版本文件夹>`，存档从 `saves/` 读取 |
| 组件统计/移出 | 是 | 版本树显示 Mod/光影/材质/存档数量；移出到 `.minecraft` 外的备份目录 |
| Java 自动检测 / 手动选择 | 是 | PATH、JAVA_HOME、常见安装目录、官方启动器 runtime |
| 离线启动 | 是 | 离线 UUID 使用 `OfflinePlayer:<name>` 的 MD5 算法 |
| 第三方 Yggdrasil | 是 | 邮箱/用户名 + 密码登录，authlib-injector 注入 |
| 正版 Microsoft | 是 | 官方 Live 设备码，无需用户填 client_id；显示/复制验证码 |
| 自动中文 | 是 | 启动前写 `lang=zh_cn`、`forceUnicodeFont=true` |
| 日志 | 是 | 启动器目录下 `logs/`，不再显示在底部 |
| 原生文件选择 | 是 | 所有 `FileDialog` 使用 `use_native_dialog` |
| 整合包导入 | 本地部分 | 只复制 `overrides`、`client-overrides` 与本地来源目录中存在的文件 |
| Mod / 光影 / 材质复制 | 是 | 目标目录 `mods` / `shaderpacks` / `resourcepacks`，同名文件备份 |
| 下载 / 在线资源商店 | 否 | 有意不做；登录只访问认证服务 |
| 修改版本 JSON / JAR | 否 | 启动器只读版本描述文件 |

## 环境

- Godot **4.7 或更高版本**（本项目在 Godot **4.7.2 stable** 上验证；项目 `config/features` 为 4.7）。
- Windows / Linux 桌面优先；使用 `gl_compatibility` 渲染器，无第三方 UI 插件。
- 运行游戏需要你本地已安装的 Java；启动器不捆绑 Java。
- 项目文件中的 `config/features` 标记为 4.7；使用 4.7.2 打开即可，不需要额外插件。

## 运行

```bash
godot --path .
```

或直接运行导出后的可执行文件。

## 第一次使用

1. 点击顶部「添加游戏文件夹」，选择包含 `versions` 的目录（通常是 `.minecraft`）。可以添加多个，重复添加会被忽略。
2. 左侧版本树按文件夹分组，点击文件夹可折叠；版本名使用版本文件夹的名字。
3. 游戏目录固定为 `<游戏文件夹>/versions/<版本文件夹名>`，没有实例名/游戏目录选择；配置自动保存在该目录的 `gl-instance.json`。
4. 选择启动模式：
   - **离线**：填玩家名；
   - **第三方认证**：填 Yggdrasil 根地址、邮箱/用户名、密码，点「登录第三方」，并准备 `authlib-injector.jar`；
   - **正版**：点「登录正版」，按浏览器提示输入启动器显示的验证码；不需要 Azure client_id。
5. 在 Java 设置中确认自动检测结果，或手动选择 `java.exe` / `java`。
6. 按需勾选「启动时自动设置游戏中文」。
7. 设置会随修改自动保存；点击「启动游戏」即可。

## 存档与 Mod

当前版本的游戏目录就是版本文件夹，存档从该目录的 `saves/` 读取，Mod 从 `mods/` 读取，`options.txt` 也在同一层。版本树上会显示两者的数量。

- 旧版 `user://instances` 里的设置会**自动迁移**到版本目录的 `gl-instance.json`，不会重置。
- 需要清理某个版本的组件时，点「管理组件…」，勾选后移出到 `.minecraft` 外面的 `gl-component-backup`，界面会显示备份路径；不会直接删除。
- 「打开游戏目录」按钮会打开当前版本目录，方便检查 `saves/` / `mods/`。

## 第三方 Yggdrasil 登录

支持标准 Yggdrasil/authlib-injector 认证服务器，例如 LittleSkin、Blessing Skin 等。只支持 Yggdrasil 协议；只提供 OAuth 登录、没有 Yggdrasil 接口的服务器不能作为第三方账号使用。

- 用户名栏支持 **邮箱或用户名**；邮箱验证/2FA 需要先在认证网站完成，启动器不发送验证邮件。第三方区域的「打开网站」按钮会打开认证服务器首页，方便完成邮箱验证或开启 2FA。
- 认证地址示例：`https://littleskin.cn/api/yggdrasil`。
- 启动器会尝试从 `versions/<版本id>/PCL/Setup.ini` 读取 `VersionServerAuthServer`。
- 启动时自动添加：
  `-javaagent:<authlib-injector.jar>=<认证地址>`
- `authlib-injector.jar` 是用户本地提供的 Java 代理，把游戏的 Mojang 认证请求重定向到第三方 Yggdrasil 服务器；本启动器不分发它。
- 自动查找位置：游戏根目录、`PCL/`、同级目录、同级目录的 `PCL/`。
- 密码只用于本次登录请求，不写入磁盘、不写日志；成功后只保存 `accessToken`、`clientToken`、`uuid`、`name`、`server` 到 `<启动器目录>/auth/thirdparty.json`。
- 登录令牌过期后需要重新点击「登录第三方」。

## 正版 Microsoft 登录

采用与 PCL/官方启动器相同的设备码流程，但使用 Microsoft 官方 Minecraft 启动器的 **公开 Live 客户端 ID**，所以不需要你注册 Azure 应用，也没有 client_id 输入步骤：

1. 点「登录正版」；
2. 启动器显示验证码，并打开 `https://www.microsoft.com/link`；
3. 在浏览器输入验证码并登录；
4. 启动器轮询令牌，依次请求 Xbox Live、XSTS、Minecraft Services，最后读取角色；
5. 成功后写入 `<启动器目录>/auth/premium.json`，启动参数使用 `--userType msa`。

说明：

- 这是官方启动器使用的 Live 设备码入口，不是 PCL 私有的 OAuthClientId；因此本启动器不需要用户填 client_id。
- `login.live.com/oauth20_remoteconnect.srf` 是旧版 Live Connect 入口；现代设备码流程使用 `https://www.microsoft.com/link`（或 Microsoft 返回的 `microsoft.com/devicelogin`）。
- 登录过程只接触设备码，不接触 Microsoft 密码。
- 「复制验证码」「打开登录页」始终可用，不会因为浏览器被关掉或登录失败变灰；没有验证码时复制会提示先登录。
- 令牌过期后需要重新走设备码；当前不实现自动刷新。
- 没有正版账号时可继续使用离线或第三方模式。

## JVM 参数

启动器会自动设置：

- `-Xmx<内存>M`、`-Xms512M`；
- `-Dlog4j2.formatMsgNoLookups=true`；
- `-Dfile.encoding=UTF-8`；
- `-Dminecraft.launcher.brand=gl-launcher`、`-Dminecraft.launcher.version`；
- natives 的 `-Djava.library.path`、JNA/LWJGL 临时目录；
- 版本 JSON 自带的 JVM 参数；
- 第三方登录时的 `-javaagent:authlib-injector.jar=...`；
- `-cp` 完整 classpath；
- 游戏参数 `--username`、`--uuid`、`--accessToken`、`--gameDir`、`--assetsDir`、`--assetIndex`、`--userType` 等。

内存可在界面中调整；其他参数由版本 JSON 与启动器自动组装，暂不提供自由文本 JVM 参数框。

## 自动中文

勾选「启动时自动设置游戏中文」后，启动前会：

- 如果游戏目录缺少 `options.txt`，先尝试从共享根目录复制；
- 写入/修正 `lang:zh_cn`；
- 写入/修正 `forceUnicodeFont:true`。

这只会修改语言与 Unicode 字体，不改按键、画面、难度等其他设置。

## 界面动效

本版接入了基础动效层：

- 所有按钮：悬停亮度、底部光条、按下缩放、点击波纹、焦点光条；
- 启动按钮：进度环，启动成功后绿色反馈，失败时红色反馈；
- 启动器打开时主面板淡入 + 轻微缩放；
- 「减少动效」：关闭位移/缩放，只保留极短淡入；
- 「低配模式」：关闭 Shader/粒子类效果（当前动效未使用 Shader/粒子，保留回退开关）。

未逐项实现整份绚丽版清单中的列表拖拽、粒子背景、窗口模糊、托盘呼吸、长按环形进度、逐字标题等；这些需要单独排期，当前不影响启动功能。

## 日志

日志不再显示在底部，统一写入启动器目录：

```text
<启动器目录>/logs/launcher-YYYYMMDD.log        启动器日志，保留 7 天
<启动器目录>/logs/instances/<版本名>/latest.log  游戏 stdout/stderr
```

- 开发时 `<启动器目录>` 是项目根目录；导出后是可执行文件所在目录。
- 如果目录不可写，自动回退到 `user://logs`。
- 顶部「打开日志目录」可直接打开。
- 游戏自身还会在运行目录写 `logs/latest.log` 与 `authlib-injector.log`，这些也在启动器目录下。

## 界面

- 底部保留「说明书」「免责声明」「下载器链接」三个按钮；前两个点击弹出独立文档窗口，下载器链接打开 `https://github.com/glgl6688/gl-MC-downloader/`。
- 顶部按钮：添加文件夹、移除当前文件夹、打开日志目录。
- 在版本树中选中一个根文件夹节点时，会在树下方显示该根目录的完整路径，并带复制按钮。
- 所有文件/文件夹选择框使用系统原生弹窗。
- 版本树可折叠，文件夹名与版本文件夹名原样显示。

## 目录结构

```text
project.godot
main.tscn
icon.svg
scripts/
  core/
    config_manager.gd      全局配置 launcher.cfg（Autoload: ConfigManager）
    log_manager.gd         启动器目录日志（Autoload: LogManager）
    error_info.gd          错误对象与中文文案表
    error_reporter.gd      错误上报（Autoload: ErrorReporter）
    file_utils.gd          路径、分块复制、哈希、备份
    thread_task.gd         通用后台线程任务
    version_scanner.gd     多文件夹版本发现
    instance_config.gd     版本目录 gl-instance.json、自动迁移
    java_manager.gd        Java 检测与校验
    version_resolver.gd    版本 JSON 继承、运行库、natives
    auth_helper.gd         离线 UUID / 本地令牌 / PCL 认证配置探测
    online_auth.gd         第三方 Yggdrasil 登录
    microsoft_auth.gd      正版 Microsoft 设备码登录
    game_options.gd        自动中文 / Unicode 字体
    launch_builder.gd      启动参数组装
    process_runner.gd      进程启动、输出写日志
    resource_installer.gd  Mod / 光影 / 材质复制
    mrpack_importer.gd     .mrpack 本地导入
  ui/
    main.gd                主控制器
    version_panel.gd       左侧可折叠版本树
    settings_panel.gd      右侧设置区
    bottom_bar.gd          底部说明书/免责声明/下载器链接按钮
    dialogs.gd             错误框、报告框、原生文件选择、整合包目标
    ui_kit.gd              主题与常用控件
    info_texts.gd          静态文案
tests/
  smoke_test.tscn/gd       核心逻辑冒烟测试
  process_test.tscn/gd     进程输出与日志测试
  ui_test.tscn/gd          界面联动测试
```

数据位置（不再默认使用 AppData）：

```text
<启动器目录>/launcher.cfg                 全局设置（多游戏文件夹、Java、上次选择）
<启动器目录>/auth/premium.json            正版令牌
<启动器目录>/auth/thirdparty.json         第三方令牌
<启动器目录>/logs/...                     启动器与游戏日志
<游戏文件夹>/versions/<版本文件夹>/gl-instance.json   该版本的自动实例设置
```

首次运行会把旧的 `user://launcher.cfg`、`user://auth` 和旧 `user://instances` 配置迁移过来。

## Autoload 注册

`project.godot` 的 `[autoload]` 顺序：

1. `ConfigManager`：创建目录、读写 `launcher.cfg`。
2. `LogManager`：启动器目录日志。
3. `ErrorReporter`：把 ErrorInfo 写入日志并发出 `error_raised`。

## 任务对照（T01-T10）

| 任务 | 主要文件 |
|---|---|
| T01 项目骨架与全局配置 | `project.godot`、`config_manager.gd`、`log_manager.gd`、`error_reporter.gd`、`thread_task.gd` |
| T02 版本发现 | `version_scanner.gd`、`version_panel.gd` |
| T03 版本设置持久化 | `instance_config.gd`、`settings_panel.gd` |
| T04 Java 检测与选择 | `java_manager.gd`、`settings_panel.gd` |
| T05 启动命令与执行 | `version_resolver.gd`、`auth_helper.gd`、`online_auth.gd`、`microsoft_auth.gd`、`launch_builder.gd`、`process_runner.gd` |
| T06 整合包导入 | `mrpack_importer.gd`、`dialogs.gd` |
| T07 本地资源安装 | `resource_installer.gd` |
| T08 错误提示统一层 | `error_info.gd`、`error_reporter.gd`、`dialogs.gd` |
| T09 日志与底部按钮 | `log_manager.gd`、`bottom_bar.gd`、`info_texts.gd` |
| T10 联调与验收 | `tests/*`、本 README |

## 游戏目录

游戏目录固定为 `<游戏文件夹>/versions/<版本文件夹名>`，不再让用户选择实例目录或共享目录。

- 存档：`versions/<版本文件夹>/saves/`
- Mod：`versions/<版本文件夹>/mods/`
- 光影/材质：`shaderpacks/`、`resourcepacks/`
- 游戏设置：`versions/<版本文件夹>/options.txt`
- 启动器设置：`versions/<版本文件夹>/gl-instance.json`

版本文件、运行库与资源始终从对应游戏文件夹读取，启动器不会复制或修改版本 JSON/JAR。

## 组件统计与移出

版本树每行直接显示：

```text
版本文件夹    Mod    光影    材质    存档
```

选中版本后，「版本目录与组件」卡片会显示同样的数量，并提供「管理组件…」。勾选要移出的组件后：

- 移动到 `.minecraft` 外面的 `gl-component-backup/<游戏文件夹>/<版本>/<时间>/`；
- 不会直接删除；
- 完成后弹窗显示备份路径；
- 这是危险操作，所以使用确认对话框。

如果某个版本只有 Mod 而没有原版 JSON/JAR，会显示「缺少原版游戏文件」以及具体组件数量，并提示先安装对应原版版本；Mod 不能单独启动。

诊断会聚合多个原因，不只看 JSON/JAR：缺少 mainClass、父版本、资源索引、运行库或 natives 也会一起列出，避免只提示一个表面原因。

## 整合包导入

`.mrpack` 本质是 zip。启动器会：

1. 读取 `modrinth.index.json`；
2. 复制 `overrides/` 与 `client-overrides/` 到当前游戏目录；
3. 对 `files[]` 条目，只在用户指定的“本地资源来源目录”或目标游戏目录中查找已存在的同名文件，并校验哈希/大小；
4. 缺失文件写入报告，**不会联网下载**。

## 构建 / 导出

1. 在 Godot 编辑器中安装对应平台导出模板。
2. 项目 → 导出 → 添加 Windows Desktop 或 Linux/X11。
3. 设置导出路径后导出。

不依赖任何原生插件或第三方库。

## 测试

核心测试（不需要 Java、不会修改游戏文件）：

```bash
godot --headless --path . res://tests/smoke_test.tscn
godot --headless --path . res://tests/process_test.tscn
godot --headless --path . res://tests/ui_test.tscn
```

测试会使用隔离的 `user://` 测试目录，不会删除或覆盖真实实例、令牌和 `launcher.cfg`。界面测试会临时清空子进程的 `PATH`，以复现“未找到 Java”。

手工冒烟清单：

1. 添加两个游戏文件夹 → 版本树出现两个可折叠父节点；
2. 选版本 → 游戏目录默认「版本文件夹」，能看到该版本已有存档/Mod；
3. 切换游戏目录 → 打开游戏目录按钮打开对应目录；
4. 自动保存 → 版本目录 `gl-instance.json` 生成；
5. 离线启动 → 游戏出现，启动器目录 `logs/instances/<版本名>/latest.log` 增长；
6. 第三方登录 → 令牌写入 `auth/thirdparty.json`，启动参数含 `-javaagent`；
7. 正版登录 → 显示验证码，浏览器完成登录后写入 `auth/premium.json`；
8. 导入 `.mrpack` / 安装 Mod → 文件落到当前游戏目录；
9. 底部有三个按钮：说明书/免责声明/下载器链接；
10. 文件选择框为系统原生窗口。

## 安全与限制

- 第三方登录仅访问用户填写的认证服务器；正版登录仅访问 Microsoft/Xbox 官方服务。
- 第三方密码只用于本次请求，不写入磁盘、不写日志；正版设备码流程不接触 Microsoft 密码。
- 正版登录使用 Microsoft 官方 Live 公共客户端，不需要用户自己的 Azure 应用。
- 只读版本 JSON；不修改版本 JAR/JSON。
- 复制与解压拒绝绝对路径、盘符与 `..` 越界，避免路径穿越。
- 日志中的 `accessToken` 会被隐藏。
- 游戏运行期间建议保持启动器打开：关闭启动器会关闭输出管道，可能影响后续日志采集，但不会主动结束游戏进程。
- `.mrpack` 的 `files` 条目不会下载；只处理本地已有文件。
- 整合包的 `sha512` 无法用 Godot 内置的 `HashingContext` 计算；如果条目只提供 `sha512`，启动器会改用文件大小校验，并在结果中给出警告。
- 第三方/正版登录令牌过期后需重新登录；当前不实现自动刷新。
- 依赖 Godot 的 `OS.execute_with_pipe` 捕获输出；代码在 4.7.2 验证。
- 主界面控制器与两个较大的 UI 面板代码量较大，属于“特殊情况可以”的例外；核心逻辑按职责拆分在 `scripts/core/`。

## 故障排查

| 现象 | 检查 |
|---|---|
| 看不到存档/Mod | 确认游戏目录是 `versions/<版本文件夹>`，存档在 `saves/`；用「管理组件」查看数量 |
| 未发现版本 | 游戏文件夹是否包含 `versions/<id>/<id>.json` 与 `<id>.jar` |
| 版本不可用 | 看原因与建议：可能缺 JSON/JAR、mainClass、父版本、资源索引、运行库或 natives，不再只报一个原因 |
| Java 未找到 | 安装 Java；或用「手动选择」选中 `java.exe` / `java` |
| Java 版本过低 | 按版本 JSON 的 `javaVersion.majorVersion` 安装更高版本 |
| 缺少运行库 | `libraries` 不完整，用本地完整文件补全；启动器不下载 |
| 缺少资源索引 | `assets/indexes` 不完整，用本地完整文件补全 |
| 启动后立刻退出 | 查看 `logs/instances/<版本名>/latest.log` 与启动器日志；检查 Java 版本/内存 |
| 第三方登录失败 | 检查认证地址、邮箱/用户名、密码；确认 `authlib-injector.jar` 存在 |
| 正版登录失败 | 检查网络、验证码是否过期、账号是否拥有 Minecraft；查看 `auth/premium.json` 是否写入 |
| 整合包缺文件 | 报告会列出缺失路径；需自行获取后放入对应目录或来源目录 |

## 上传到 GitHub

仓库地址：<https://github.com/glgl6688/gl-MC-launcher>

在项目目录执行：

```bash
git init -b main
git config user.name "glgl6688"
git config user.email "你的 GitHub 邮箱"
git add .
git status
git commit -m "Initial release: gl启动器 1.0.0"
git remote add origin https://github.com/glgl6688/gl-MC-launcher.git
git push -u origin main
```

提交前检查：

```bash
git status --short
git ls-files
```

确认文件列表中没有 `auth/`、`logs/`、`cache/`、`launcher.cfg`、`authlib-injector.log`。如果出现了，说明 `.gitignore` 没生效，不要提交，先检查。

如果远程仓库已经有 README/初始提交：

```bash
git pull --rebase origin main --allow-unrelated-histories
# 解决冲突后
git push -u origin main
```

GitHub 不再接受账号密码推送，请使用 Personal Access Token 或 Git Credential Manager。

## 许可证

本项目自身代码采用 **MIT License**：

```text
Copyright (c) 2026 glgl6688
```

完整许可证见 [LICENSE](LICENSE)。

第三方说明：

- Godot Engine 采用 MIT License，完整声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
- 本仓库不包含 Minecraft 游戏本体、运行库、资源、Mod、光影、材质或官方 Logo。
- `authlib-injector.jar` 不由本仓库分发，用户自行获取并遵循其许可证。
- 用户导入的游戏文件、Mod、光影、材质、整合包归各自作者所有，请遵守对应许可与服务器规则。

## 不提交的运行期数据

以下文件/目录属于用户本地数据，已由 `.gitignore` 排除：

```text
launcher.cfg
auth/
logs/
cache/
authlib-injector.log
*.log
```

发布前请确认 `git status` 中没有这些内容。
