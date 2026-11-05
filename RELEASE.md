# DS Bot Go 1.0.12

本版是 DS Bot Go 的首个独立发行版。手机端基于 DSH Go，配套桌面 DS Bot 移动 API 与 Remote Host 适配，使用本项目原创 Bot 图标和动画素材。

发行下载与对应源码：[v1.0.12](https://github.com/tangchunhao71-hash/DS-Bot-Go/releases/tag/v1.0.12)。安装与构建见 [GETTING_STARTED.md](docs/GETTING_STARTED.md)，来源与许可见 [LICENSING.md](docs/LICENSING.md)。

## 固定输入

| 组件 | 修改后源码提交 |
| --- | --- |
| 手机端 | b8cb1b957b6ecfb461df4996500d91f7a18fbe57 |
| 桌面 DS Bot | 2d20dd39513e8d4a0efbd9e36a4886f1fd44ad36 |
| Remote Host | 62a39d405895bb556e392d1f5854e85ea393f3ee |

这些是形成公开源码树前的组件输入提交；上游基线与准确文件散列见 UPSTREAMS.json 和 SOURCE_MANIFEST.json。发行源码只省略不参与 APK 构建的上游宣传/原美术输入与生成式测试截图，保留构建代码、锁文件、测试代码和本版素材源。

## Android 安装包

- 文件：DS-Bot-Go-1.0.12-arm64.apk
- 版本：1.0.12+11051725；194686811 字节
- SHA256：39f434c82e2920fb7b664e4a4bdf6461ce10ece037c7ecdd686b6cdd7d8bc543
- Android 8.0+，arm64；单 APK，含运行环境
- 包名：io.github.ccch1mneyyy.dsh_app.qicancompat
- 证书 SHA256：219035d0205cacbce3b016e18972c64d77433704f00f18b300e393c53f38e841

APK 使用 release 构建，并保留兼容测试版证书以支持覆盖更新；证书主题为 Android Debug。签名密钥不在源码中。远程操作仍需要电脑端 DS Bot 与配套 Remote Host 在线；本次不另发桌面安装器，上游 npm 原包不保证包含这些适配。

已核对固定源码、APK v2 签名、单包结构、16 KB 对齐、原运行环境，以及包内 52 个素材/许可文件与公开源码一致。此最终版未进行手机实装，不将较早兼容版的反馈当作本版实装结论。

手机端保留 AGPL-3.0，DS Bot 保留 Apache-2.0 与 NOTICE，Remote 保留 MIT；原创图标和素材用 MIT，第三方声明保留。欢迎 Issue，当前不接收或合并外部 PR。上游来源、贡献归属与许可证条件不因独立发行而改变。
