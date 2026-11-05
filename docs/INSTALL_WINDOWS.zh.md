# DS Bot Go 安装教程（Windows + Android）

适用版本：**DS Bot Go 1.0.12**。下载入口：[v1.0.12 发布页](https://github.com/tangchunhao71-hash/DS-Bot-Go/releases/tag/v1.0.12)。

**手机只需要安装 DS Bot Go，不需要先装 DSH Go。要使用电脑里的 DS Bot 团队，电脑端还需要配套的 DS Bot 和 Remote 插件。**

1.0.12 已提供手机 APK；电脑端兼容改动目前以源码提供，尚未提供独立的一键安装器。仅安装上游原版 DS Bot 桌面端和普通 Remote 插件，不能保证具备本项目所需的全部接口。

## 需要安装什么

| 组件 | 是否需要 | 说明 |
| --- | --- | --- |
| 手机 DS Bot Go APK | 必需 | Android 8.0 及以上、ARM64 手机 |
| 手机 DSH Go | 不需要 | DS Bot Go 已包含衍生客户端和所需运行环境 |
| 电脑端 DS Bot | 必需 | 需要本项目配套改版，负责运行团队、Bot 和会话 |
| DeepSeek Harness Desktop | 不必另装 | 下述源码启动路线会准备 DS Bot 所需的 DSH 依赖 |
| 电脑端 Remote 插件 | 必需 | 使用本项目配套版本，负责手机与电脑连接 |
| Node.js | 电脑源码安装时需要 | 手机不需要安装 |
| Remote 服务账号 | 必需 | 手机和电脑使用同一个服务、同一个账号 |
| Termux、Root、Flutter、Android Studio | 手机安装不需要 | 使用已发布的 APK，无需自行编译 |

如果电脑已经安装本项目兼容层，并且此前能在手机看到团队，可直接从[手机安装](#手机安装)开始。

如果是从零安装，按下面的 Windows 源码路线操作。**这条路线创建独立团队，不会自动迁移已安装桌面版的旧团队。** 复用旧团队需要针对原安装做兼容升级；不要把示例的数据目录直接改成旧团队路径。

以下命令已按 1.0.12 的固定源码核对；全新 Windows 电脑上的完整安装流程和该最终 APK 的手机实装尚未完成验证。

## Windows 电脑从零安装

### 1. 准备 Node.js

从 [Node.js 官方下载页](https://nodejs.org/en/download)选择 **24.x LTS、Windows Installer** 并安装。项目源码启动器要求 Node.js 22.19 或以上，本教程采用 24.x。

安装后重新打开 PowerShell：

~~~powershell
node --version
npm.cmd --version
~~~

两条命令都能显示版本号后再继续。手机不用做这一步。

### 2. 下载并解压配套源码

从 [1.0.12 发布页](https://github.com/tangchunhao71-hash/DS-Bot-Go/releases/tag/v1.0.12)下载：

~~~text
DS-Bot-Go-1.0.12-source.tar.gz
~~~

同页提供 SHA256SUMS，可核对下载文件的 SHA256。PowerShell 查询命令为：

~~~powershell
Get-FileHash -LiteralPath "$env:USERPROFILE\Downloads\DS-Bot-Go-1.0.12-source.tar.gz" -Algorithm SHA256
~~~

假设文件保存在“下载”文件夹，首次安装执行：

~~~powershell
$archive = Join-Path $env:USERPROFILE 'Downloads\DS-Bot-Go-1.0.12-source.tar.gz'
$project = Join-Path $env:USERPROFILE 'DS-Bot-Go-1.0.12'

if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    throw '找不到源码压缩包，请修改 $archive 为实际下载路径。'
}
if (Test-Path -LiteralPath $project) {
    throw '目标目录已存在。已有安装请跳过解压步骤，不要覆盖已有源码或数据。'
}

tar -xzf $archive -C $env:USERPROFILE
if ($LASTEXITCODE -ne 0) {
    throw '源码解压失败，请保留报错，先不要继续。'
}
~~~

如果下载位置不同，修改 $archive。源码目录需要长期保留，不要当成安装后可删除的临时目录。

### 3. 首次启动配套桌面端

在 PowerShell 中执行：

~~~powershell
$project = Join-Path $env:USERPROFILE 'DS-Bot-Go-1.0.12'
$desktop = Join-Path $project 'desktop\ds-bot'

Set-Location $desktop
powershell -NoProfile -ExecutionPolicy Bypass -File .\start.ps1
~~~

启动器会安装依赖、构建本项目的 DS Bot 插件、准备 Electron，并打开桌面窗口。首次运行需要下载依赖，后续会复用。

ExecutionPolicy Bypass 只对这次启动的 PowerShell 进程生效，不要求永久更改系统策略。启动器细节见[桌面源码启动说明](../desktop/ds-bot/app/README.md#run-from-source-windows)。

在电脑端设置模型提供商和自己的账号/API Key，创建一个 Bot，先确认桌面界面正常。

数据保存在：

~~~text
DS-Bot-Go-1.0.12\desktop\ds-bot\.ds-bot-local\
~~~

其中 data/ 保存团队、会话和配置，workspace/ 保存 Bot 工作文件，shell/ 保存窗口与浏览器状态。删除或移动整个源码目录前，应先备份这部分数据。

安装 Remote 前，从 Windows 托盘菜单中**彻底退出 DS Bot**。只关闭窗口可能仍会留在后台。

### 4. 安装本项目配套的 Remote

在 PowerShell 中执行：

~~~powershell
$project = Join-Path $env:USERPROFILE 'DS-Bot-Go-1.0.12'
$remote = Join-Path $project 'desktop\remote'
$appDir = Join-Path $project 'desktop\ds-bot\app'

Set-Location $remote
npm.cmd pack --ignore-scripts
if ($LASTEXITCODE -ne 0) {
    throw 'Remote 打包失败，请保留报错，先不要继续。'
}
~~~

成功后，当前目录生成 ds-harness-remote-0.6.2.tgz。1.0.12 源码归档中已包含配套 Remote 的构建产物，因此这一步无需另装 pnpm 或自行重编译 Remote。

这里打包的是**本项目源码归档中包含兼容改动的 Remote**，不能仅凭相同的 0.6.2 版本号换成上游 npm 原包。公开入口与打包范围见 [Remote package.json](../desktop/remote/package.json) 和 [Remote 插件说明](../desktop/remote/packages/plugin/README.md)。

确认 DS Bot 已彻底退出，再将这个包安装到上一步的独立数据目录：

~~~powershell
$project = Join-Path $env:USERPROFILE 'DS-Bot-Go-1.0.12'
$remote = Join-Path $project 'desktop\remote'
$appDir = Join-Path $project 'desktop\ds-bot\app'

$dshCli = Join-Path $appDir 'node_modules\.bin\dsh.cmd'
$pnpmCli = Join-Path $appDir 'node_modules\.bin\pnpm.cmd'
$remotePackage = Join-Path $remote 'ds-harness-remote-0.6.2.tgz'
$profileManifest = Join-Path $project 'desktop\ds-bot\.ds-bot-local\data\profiles\ds-bot\package.json'

foreach ($required in @($dshCli, $pnpmCli, $remotePackage, $profileManifest)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "缺少文件：$required。请先完成桌面端首次启动及 Remote 打包。"
    }
}

$savedDshHome = $env:DSH_HOME
$savedPath = $env:PATH

try {
    $env:DSH_HOME = Join-Path $project 'desktop\ds-bot\.ds-bot-local\data'
    $env:PATH = (Join-Path $appDir 'node_modules\.bin') + ';' + $savedPath

    & $dshCli plugin --profile ds-bot add -w $remotePackage --ignore-scripts --config.auto-install-peers=false

    if ($LASTEXITCODE -ne 0) {
        throw 'Remote 安装失败，请保留报错，先不要继续启动。'
    }
}
finally {
    $env:DSH_HOME = $savedDshHome
    $env:PATH = $savedPath
}
~~~

DSH_HOME 表示这套桌面端的运行数据目录。命令使用 app 自带的 DSH CLI 与 pnpm，结束后恢复当前终端原有的环境变量，不需要全局安装另一个 DSH 或 pnpm。

这组命令仅对应本教程的默认源码目录和默认 DataRoot。如果自己调整了启动器的 DataRoot，安装 Remote 时也必须使用同一个数据目录。不要用此示例升级正在使用的其他团队。

### 5. 配置电脑端 Remote

重新启动：

~~~powershell
$project = Join-Path $env:USERPROFILE 'DS-Bot-Go-1.0.12'
Set-Location (Join-Path $project 'desktop\ds-bot')
powershell -NoProfile -ExecutionPolicy Bypass -File .\start.ps1
~~~

在桌面端进入 Remote 页面：

1. 选择作为 Host／主机运行。
2. 填写要使用的 Remote Server 地址。
3. 登录自己的 Remote 账号。
4. 开启“允许控制当前设备”。
5. 等待电脑显示为在线。

配套代码默认使用 https://dsh.r2049.cn；使用自建服务时，填写自己的地址。若服务要求邀请码，需要先完成该服务的账号申请。具体登录入口以所选服务为准。

**Remote 账号用于连接设备，模型账号/API Key 用于调用模型，这是两套配置。**

## 手机安装

从 [1.0.12 发布页](https://github.com/tangchunhao71-hash/DS-Bot-Go/releases/tag/v1.0.12)下载：

~~~text
DS-Bot-Go-1.0.12-arm64.apk
~~~

1. 保存到手机。
2. 在文件管理器中点开 APK。
3. 如果系统提示，允许这次所用的浏览器或文件管理器安装应用，再返回安装页继续。
4. 确认名称为 DS Bot Go，完成安装并打开。

适用设备为 Android 8.0 及以上的 ARM64 手机。手机只需要这个 APK，无需另装 DSH Go、Node.js 或 Termux。

已有本项目同签名兼容测试版时，可以覆盖更新。若提示签名冲突，先核对安装包和发行说明中的签名，不要直接卸载有数据的旧版。

## 手机连接电脑

打开 DS Bot Go，进入管理远程主机／远程连接入口，选择 DSH Remote：

1. 填写与电脑端完全相同的 Remote Server 地址。
2. 选择与电脑端相同的登录方式、同一个账号。
3. 在主机列表中选择已经在线的电脑。
4. 首次连接时，对照电脑端显示的信息确认主机指纹。
5. 连接成功后进入 DS Bot 工作区，查看团队、Bot 和会话。

查看远程 DS Bot 不需要先开启手机的无障碍、悬浮窗或手机操控功能。

连接此前已完成兼容配置的电脑时，应看到那套电脑对应的团队。采用本教程全新源码路线时，看到的是新建的独立团队。

## 日常启动和数据保留

以后继续从同一个目录运行 start.ps1，即可使用原来的数据，无需重复解压源码或打包安装 Remote。

电脑需要开机、联网，DS Bot 与 Remote Host 保持运行。关闭窗口留在托盘通常还能继续运行；从托盘退出程序、电脑关机或进入睡眠会影响远程连接。

## 常见问题

| 现象 | 优先检查 |
| --- | --- |
| 手机找不到电脑 | 两端 Server 地址、登录方式和账号是否一致；电脑是否显示在线 |
| 找到电脑但连接被拒绝 | 电脑是否开启“允许控制当前设备”；首次指纹是否完成确认 |
| 能连接，但 DS Bot 页面提示不支持或需要升级 | 电脑是否仍在运行上游原版 DS Bot，或安装了普通 Remote 原包 |
| 看不到原来的团队 | 是否启动了新的 .ds-bot-local 数据目录，而非原先配好的实例 |
| 定时任务页面不可用 | 手机、DS Bot 移动 API、Remote 是否为配套版本 |
| 手机安装失败或打不开应用 | Android 版本、ARM64 架构、文件完整性与签名是否符合要求 |
| 源码解压提示目录存在 | 已有源码安装不必重复解压；先确认原目录用途和数据归属 |
| 电脑安装依赖或 Remote 时报错 | 保留报错并停止后续步骤，先解决失败，不要覆盖旧团队目录 |

## 相关资料

- [安装与 APK 构建](GETTING_STARTED.md)
- [桌面源码启动说明](../desktop/ds-bot/app/README.md)
- [Remote 插件说明](../desktop/remote/packages/plugin/README.md)
- [来源与许可](LICENSING.md)
