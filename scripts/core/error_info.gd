class_name ErrorInfo
extends RefCounted
## 统一错误对象与中文文案表。
## 每个错误：code / title / message / path / fix_hint。
## 命令与后台线程只负责构造错误，UI 层负责展示与复制路径。

const TEXTS := {
	"UNKNOWN": {
		"title": "启动器错误",
		"message": "发生未预期的错误：{detail}",
		"fix_hint": "请查看启动器目录下的 logs 文件夹；如果问题重复出现，请带上日志反馈。",
	},
	"NO_VERSIONS_DIR": {
		"title": "未找到版本目录",
		"message": "所选游戏根目录下没有 versions 文件夹。\n当前检查路径：{path}",
		"fix_hint": "请点击顶部「添加游戏文件夹」，选择包含 versions 文件夹的目录（通常是 .minecraft）。本启动器只读取本地文件，不会下载游戏。",
	},
	"VERSIONS_DIR_UNREADABLE": {
		"title": "无法读取版本目录",
		"message": "versions 文件夹存在，但启动器没有读取权限。\n路径：{path}\n原因：{reason}",
		"fix_hint": "请检查该文件夹的访问权限，或把游戏根目录移动到当前用户可读的位置后重新选择。",
	},
	"VERSION_LIST_EMPTY": {
		"title": "未发现版本",
		"message": "versions 文件夹中没有子文件夹。\n路径：{path}",
		"fix_hint": "请把本地已有的版本文件夹（包含 <版本id>.json 与 <版本id>.jar）放入 versions 目录，然后点击「重新扫描」。",
	},
	"VERSION_JSON_MISSING": {
		"title": "版本文件缺失",
		"message": "版本 {name} 缺少 JSON 描述文件：\n{path}",
		"fix_hint": "请用本地已有的完整版本文件补全该目录，或在版本列表中改用其他可用版本。本启动器不会补全或下载游戏文件。",
	},
	"VERSION_JAR_MISSING": {
		"title": "版本文件缺失",
		"message": "版本 {name} 缺少客户端 JAR 文件：\n{path}",
		"fix_hint": "请用本地已有的完整版本文件补全该目录，或在版本列表中改用其他可用版本。本启动器不会补全或下载游戏文件。",
	},
	"VERSION_VANILLA_MISSING": {
		"title": "缺少原版游戏文件",
		"message": "版本文件夹 {name} 里只有 Mod/配置，没有原版版本 JSON 和客户端 JAR。\n路径：{path}\n组件：{reason}",
		"fix_hint": "这不是一个完整的游戏版本，Mod 不能单独启动。请先安装对应的原版游戏（或把原版 <版本名>.json 与 <版本名>.jar 放入该文件夹），再安装 Fabric/Forge；启动器不下载游戏本体。",
	},
	"VERSION_FILES_MISSING": {
		"title": "缺少原版游戏文件",
		"message": "版本文件夹 {name} 缺少原版版本 JSON 与客户端 JAR。\n路径：{path}\n组件：{reason}",
		"fix_hint": "请先用官方启动器或 PCL 安装该原版版本，确认 versions/<版本名>/ 下同时存在 .json 与 .jar；再回到启动器重新扫描。",
	},
	"VERSION_PARENT_MISSING": {
		"title": "缺少依赖的原版版本",
		"message": "版本 {name} 通过 inheritsFrom 依赖 {reason}，但父版本的 JSON 不存在。\n路径：{path}",
		"fix_hint": "请先安装 {reason} 原版版本，或把父版本文件夹补到同一 versions 目录；Mod/Fabric 版本不能脱离父版本启动。",
	},
	"VERSION_JSON_INVALID": {
		"title": "版本描述文件无法解析",
		"message": "版本 {name} 的 JSON 文件格式不正确：\n{path}\n原因：{reason}",
		"fix_hint": "请检查该 JSON 是否为完整文件（可用文本编辑器打开确认），或改用其他可用版本。",
	},
	"VERSION_UNUSABLE": {
		"title": "该版本不可用",
		"message": "版本 {name} 当前不可启动。\n原因：{reason}\n版本目录：{path}",
		"fix_hint": "请补全该版本的 JSON 与 JAR 文件，或选择列表中的其他可用版本。",
	},
	"VERSION_MAIN_CLASS_MISSING": {
		"title": "版本配置不完整",
		"message": "版本 {name} 的 JSON 中没有 mainClass 字段，无法确定游戏入口。\n文件：{path}",
		"fix_hint": "请确认该版本 JSON 完整；整合包或模组加载器的版本文件应由对应安装器在本地生成。",
	},
	"LAUNCH_CONFIG_INVALID": {
		"title": "版本配置错误",
		"message": "版本 {name} 的配置无法用于启动：{reason}",
		"fix_hint": "请检查本地版本 JSON；如果该版本来自整合包，请确认加载器已正确安装。",
	},
	"INSTANCE_NAME_INVALID": {
		"title": "实例名不可用",
		"message": "实例名“{name}”不符合要求：{reason}",
		"fix_hint": "请使用 1-64 个字符，且不要包含 / \\ : * ? \" < > | 等文件名保留字符，也不要使用 . 或 ..。",
	},
	"INSTANCE_EXISTS": {
		"title": "实例目录已存在",
		"message": "目标实例目录已存在，无法重命名到该名称：\n{path}",
		"fix_hint": "请换一个实例名，或先备份并移除已存在的实例目录。",
	},
	"INSTANCE_RENAME_FAILED": {
		"title": "实例目录重命名失败",
		"message": "无法把实例目录重命名为：\n{path}\n原因：{reason}",
		"fix_hint": "请确认没有其他程序占用该目录，并检查磁盘权限后重试。",
	},
	"INSTANCE_SAVE_FAILED": {
		"title": "设置保存失败",
		"message": "无法写入实例配置文件：\n{path}\n原因：{reason}",
		"fix_hint": "请检查实例目录是否存在且可写；也可以换一个实例名重试。",
	},
	"INSTANCE_CONFIG_INVALID": {
		"title": "实例配置损坏",
		"message": "实例配置文件无法解析，已按默认值载入：\n{path}\n原因：{reason}",
		"fix_hint": "请检查该 JSON 文件，或删除它让启动器重新生成默认设置。",
	},
	"JAVA_NOT_FOUND": {
		"title": "未找到可用的 Java",
		"message": "启动器没有在 PATH、JAVA_HOME 或常见安装目录中找到 Java 可执行文件。\n已检查的建议安装位置：\n{hint}",
		"fix_hint": "请安装对应版本的 Java 运行时，然后点击「手动选择 java 可执行文件」选中它。Windows 常见位置：C:/Program Files/Java 或 C:/Program Files/Eclipse Adoptium；Linux 常见位置：/usr/lib/jvm。",
	},
	"JAVA_NOT_RUNNABLE": {
		"title": "Java 无法运行",
		"message": "无法执行该 Java 程序：\n{path}\n原因：{detail}",
		"fix_hint": "请确认路径指向真正的 java 可执行文件（Windows 为 java.exe），并检查文件是否损坏、是否有执行权限。",
	},
	"JAVA_VERSION_UNKNOWN": {
		"title": "无法识别 Java 版本",
		"message": "Java 已启动，但没有输出可识别的版本信息：\n{path}\n输出：{detail}",
		"fix_hint": "请确认这是一个标准的 Java 运行时；必要时重新安装 Java 后再次检测。",
	},
	"JAVA_TOO_OLD": {
		"title": "Java 版本过低",
		"message": "当前 Java 版本为 {detected}，但该游戏版本至少需要 Java {required}。\nJava 路径：{path}",
		"fix_hint": "请安装 Java {required} 或更高版本，然后在「Java 设置」中点击「手动选择 java 可执行文件」。",
	},
	"JAVA_REQUIRED_UNKNOWN": {
		"title": "Java 版本要求未知",
		"message": "版本 {name} 的 JSON 没有声明 Java 版本要求，启动器按 Java 8 处理。",
		"fix_hint": "如果启动失败并提示类版本错误，请手动选择游戏实际需要的 Java 版本。",
	},
	"ACCOUNT_INVALID": {
		"title": "账户信息不完整",
		"message": "当前启动模式的用户名无效：{reason}",
		"fix_hint": "请在「启动模式」中填写 1-16 个字符、且不含空格的用户名。离线模式仅适合单人游戏或允许离线登录的服务器。",
	},
	"TOKEN_MISSING": {
		"title": "缺少本地令牌文件",
		"message": "当前账户模式需要本地令牌文件：\n{path}\n原因：{reason}",
		"fix_hint": "请自行准备该 JSON 文件，至少包含 accessToken、uuid、name 三个字段；第三方账号也可点击「登录第三方」生成令牌。启动器不会替你获取正版令牌。",
	},
	"LIBRARY_MISSING": {
		"title": "缺少运行库文件",
		"message": "启动前检查发现 {count} 个运行库文件缺失，例如：\n{detail}\n运行库目录：{path}",
		"fix_hint": "请使用本地已安装的完整游戏文件补全 libraries 目录（例如先用官方启动器启动一次），或改用文件完整的版本。本启动器不下载运行库。",
	},
	"ASSET_INDEX_MISSING": {
		"title": "缺少资源索引",
		"message": "版本需要的资源索引不存在：\n{path}",
		"fix_hint": "请使用本地完整的 assets 目录，或先用官方启动器启动一次以补齐资源文件。本启动器不下载资源。",
	},
	"NATIVES_EXTRACT_FAILED": {
		"title": "本地库解压失败",
		"message": "无法把本地运行库中的原生文件解压到：\n{path}\n原因：{reason}",
		"fix_hint": "请确认实例目录可写且磁盘空间充足；如果该运行库文件损坏，请用完整文件替换它。",
	},
	"LAUNCH_FAILED": {
		"title": "游戏进程启动失败",
		"message": "无法启动 Java 进程。\nJava：{path}\n原因：{reason}",
		"fix_hint": "请确认 Java 路径有效、内存设置合理，并检查启动器日志与实例日志。可尝试重新选择 Java 或降低最大内存。",
	},
	"LAUNCH_BUSY": {
		"title": "游戏已在运行",
		"message": "当前已有一个由本启动器启动的游戏进程。",
		"fix_hint": "请先关闭正在运行的游戏，或等待进程结束后再启动。",
	},
	"COPY_FAILED": {
		"title": "文件复制失败",
		"message": "无法复制文件：\n{source}\n到：\n{target}\n原因：{reason}",
		"fix_hint": "请检查源文件是否存在、目标目录是否可写、磁盘空间是否充足；关闭可能占用目标文件的程序后重试。",
	},
	"RESOURCE_EXTENSION_INVALID": {
		"title": "文件类型不正确",
		"message": "文件 {name} 的扩展名与目标类型不匹配：{reason}",
		"fix_hint": "Mod 请选择 .jar；光影与材质请选择 .zip。",
	},
	"MRPACK_INVALID_ZIP": {
		"title": "整合包无法打开",
		"message": "所选文件不是可读取的 .mrpack 压缩包：\n{path}\n原因：{reason}",
		"fix_hint": "请确认文件完整且扩展名为 .mrpack；如果文件损坏，请重新获取。",
	},
	"MRPACK_INDEX_MISSING": {
		"title": "整合包缺少索引",
		"message": "整合包内没有 modrinth.index.json：\n{path}",
		"fix_hint": "请确认这是标准的 Modrinth 整合包文件，或改用其他整合包。",
	},
	"MRPACK_INDEX_INVALID": {
		"title": "整合包索引无法解析",
		"message": "整合包内的 modrinth.index.json 格式不正确：\n{path}\n原因：{reason}",
		"fix_hint": "请确认整合包文件完整；必要时重新获取该整合包。",
	},
	"MRPACK_TARGET_MISSING": {
		"title": "没有可用的导入目标",
		"message": "启动器还没有任何实例，无法确定整合包要导入到哪个实例。",
		"fix_hint": "请先选择一个可用版本并保存设置，至少生成一个实例后再导入整合包。",
	},
	"MRPACK_IMPORT_FAILED": {
		"title": "整合包导入失败",
		"message": "导入整合包时发生错误：{reason}",
		"fix_hint": "请查看启动器目录下的 logs 与整合包内容；确认目标游戏目录可写、磁盘空间充足后重试。",
	},
	"MS_LOGIN_FAILED": {
		"title": "正版登录失败",
		"message": "Microsoft 登录未完成：{reason}",
		"fix_hint": "请重新点击「登录正版」，按浏览器提示输入验证码；确认账号已拥有 Minecraft，且网络可访问 Microsoft/Xbox 服务。",
	},
	"MS_NETWORK_ERROR": {
		"title": "无法连接 Microsoft 登录服务",
		"message": "请求 Microsoft/Xbox 服务失败：\n{path}\n原因：{reason}",
		"fix_hint": "请检查网络、代理与系统时间；确认可以访问 login.microsoftonline.com、xboxlive.com 与 api.minecraftservices.com。",
	},
	"MS_BAD_RESPONSE": {
		"title": "Microsoft 登录响应格式错误",
		"message": "无法解析登录服务响应：{reason}",
		"fix_hint": "请稍后重试；如果持续出现，检查代理是否篡改了 HTTPS 响应。",
	},
	"MS_NO_MINECRAFT": {
		"title": "该账号没有 Minecraft",
		"message": "Microsoft 登录成功，但该账号没有可用的 Minecraft Java 版角色。",
		"fix_hint": "请确认登录的是已购买 Minecraft Java 版的 Microsoft 账号；Xbox Game Pass 也需要先兑换/开通。",
	},
	"MS_TOKEN_SAVE_FAILED": {
		"title": "正版令牌保存失败",
		"message": "无法写入正版令牌文件：\n{path}\n原因：{reason}",
		"fix_hint": "请检查 user://auth 目录的写入权限与磁盘空间后重试。",
	},
	"AUTH_SERVER_REQUIRED": {		"title": "缺少第三方认证地址",
		"message": "第三方登录需要填写 Yggdrasil 认证服务器根地址。\n当前地址：{path}",
		"fix_hint": "请填写类似 https://littleskin.cn/api/yggdrasil 的地址，或让启动器自动读取实例 PCL/Setup.ini 中的认证服务器。",
	},
	"AUTH_PASSWORD_REQUIRED": {
		"title": "请输入第三方密码",
		"message": "用户名或密码为空。",
		"fix_hint": "密码只用于本次登录请求，不会写入磁盘或日志。",
	},
	"AUTH_INJECTOR_REQUIRED": {
		"title": "缺少 authlib-injector",
		"message": "第三方 Yggdrasil 登录需要在启动时注入 authlib-injector.jar。\n当前文件：{path}",
		"fix_hint": "点击第三方登录区域的「选择 authlib-injector.jar」，选中本地已有文件（例如 PCL 目录下的 authlib-injector.jar）。本启动器不分发该文件。",
	},
	"AUTH_LOGIN_FAILED": {
		"title": "第三方登录失败",
		"message": "认证服务器返回错误：{reason}",
		"fix_hint": "请检查邮箱/用户名、密码与认证服务器地址；确认该账号已在对应网站注册并完成邮箱验证/2FA，且允许使用 Yggdrasil 登录。",
	},
	"AUTH_NETWORK_ERROR": {
		"title": "无法连接认证服务器",
		"message": "请求认证服务器失败：\n{path}\n原因：{reason}",
		"fix_hint": "请检查网络、代理与系统时间；确认认证地址可访问且使用 https。",
	},
	"AUTH_INSECURE_SERVER": {
		"title": "认证地址不安全",
		"message": "该认证地址使用 HTTP，密码会以明文发送：\n{path}",
		"fix_hint": "请使用 https 地址；只有本机 localhost 调试地址允许使用 HTTP。",
	},
	"AUTH_TOKEN_SAVE_FAILED": {
		"title": "登录令牌保存失败",
		"message": "无法写入本地令牌文件：\n{path}\n原因：{reason}",
		"fix_hint": "请检查 user://auth 目录的写入权限与磁盘空间后重试。",
	},
	"AUTH_BAD_RESPONSE": {
		"title": "认证服务器返回格式错误",
		"message": "无法解析认证服务器响应：{reason}",
		"fix_hint": "请确认认证地址指向 Yggdrasil API 根路径，而不是网页首页。",
	},
	"THREAD_START_FAILED": {
		"title": "无法启动后台任务",
		"message": "创建后台线程失败。",
		"fix_hint": "请重启启动器后重试。",
	},
}


static func make(code: String, ctx: Dictionary = {}) -> Dictionary:
	var text: Dictionary = TEXTS.get(code, TEXTS["UNKNOWN"])
	var data := {
		"path": "",
		"name": "",
		"reason": "",
		"detail": "",
		"required": "",
		"detected": "",
		"target": "",
		"source": "",
		"count": "0",
		"hint": "",
	}
	data.merge(ctx, true)
	var out := {
		"code": code,
		"title": _format(str(text.get("title", "启动器错误")), data),
		"message": _format(str(text.get("message", "")), data),
		"path": str(data.get("path", "")),
		"fix_hint": _format(str(text.get("fix_hint", "")), data),
	}
	return out


static func _format(template: String, data: Dictionary) -> String:
	if template.is_empty() or not template.contains("{"):
		return template
	return template.format(data)
