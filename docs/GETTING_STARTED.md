# 安装与构建

## 手机安装

从本项目 GitHub Releases 下载 arm64 APK，核对同页 SHA256SUMS。Android 8 及以上、arm64 架构为本版目标；不需要另装 Node、Termux 或电脑安装工具。

远程模式下，电脑上的 DS Bot 和 Remote Host 仍需运行并在线。使用自己的账号，在手机与电脑选择同一 Remote 服务和账号；首次连接核对主机指纹后再信任。APK 不包含账号、凭据或用户团队数据。

本项目手机适配需要配套的 DS Bot 移动 API 与 Remote Host。源码分别在 `desktop/ds-bot/` 和 `desktop/remote/`；其中的插件构建、受支持安装入口及兼容要求沿各自 README。不要把源码或任意旧 npm 包直接覆盖到在用应用的内部文件。

## 从源码构建 APK

保留源码归档中的依赖锁文件。准备 Flutter 3.47.7 / Dart 3.13.5、JDK 17 和项目要求的 Android SDK/NDK。工具链安装位置可自行选择，不需要维护者的账号、内测 Token 或私钥。

```bash
cd mobile/app
flutter pub get --enforce-lockfile
cd ..
# 准备 runtime/out/arm64-v8a，详见 runtime/ 与 docs/release.md。
# 原构建脚本也支持从源码生成运行时；运行时版本与哈希见固定 pins/manifest。
tooling/build-apk.sh --keep-daemon --release --flavor arm64 --build-name 1.0.12
```

构建脚本使用 PATH 中的 Flutter、Java 和 Android 工具。`--keep-daemon` 避免停止同机其他任务的 Gradle 进程。

发布包应使用自己的签名证书。源码不附带维护者签名密钥；按 Android 工程支持的私有 `key.properties` 配置，或按上游本地构建方式生成独立测试签名。另一把签名不能覆盖现有安装，不要为测试自动卸载有数据的应用。

本项目图标源和生成工具在 `branding/`。替换 `mobile/app/assets/brand/` 的主文件后，从 `mobile/app/` 运行 `python3 tool/make_brand_mark.py` 生成应用内矢量代码。Android 图标的各密度输入和清单见 `branding/README.md`。

## 组件验证

按改动范围运行各组件自带检查：Flutter/Dart 对应包、DS Bot 的 `ds-bot/` 测试与 client 检查、Remote 的相关类型与通道测试。各目录保留原始开发说明。源码和静态检查不替代手机安装、真实网络或真实 Bot 操作的验收。

## 截图测试参考图

公开源码保留测试代码，但不附带自动生成的 UI 对照截图（goldens）。这些图片不是构建 APK 的输入；本次构建和品牌核对所用参考图保留在维护者的本地审计中。运行截图比较前，先用当前源码和自己的测试字体环境，通过 Flutter 的 `--update-goldens` 为对应测试文件生成基线。不要把历史上游品牌截图作为本项目宣传素材。
