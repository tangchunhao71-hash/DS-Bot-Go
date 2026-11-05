# DS Bot Go 原创图标交接

用户已确认采用自有名称/素材独立发布，并要求图标风格参考 DS Bot，且明确要求把图标提交给打包聊天。

## 设计与归属

参考只取蓝白色、圆润体块、简洁双眼和低对比立体层次。新主体为带天线、耳部和移动短线的 Bot，不使用 DS Bot 或 DSH Go 的鲸鱼轮廓、像素宠物、标识路径或源素材。图标、SVG、原始几何和生成脚本均为本次新作，按本目录 MIT LICENSE 使用。

这份图标授权只覆盖本目录原创素材，不改变 DSH Go 应用的 AGPL 或其他上游许可。

## 可直接接入

- `app/android/app/src/main/res/`：完整资源覆盖清单，含 4 套 launcher 配色、方形/圆形旧版 PNG、自适应 foreground、背景与 themed monochrome；保留现有资源名，方便所有 Launcher 别名一起更新。
- `app/assets/brand/glyph-light.svg`、`glyph-dark.svg`、`tile.svg`：应用内品牌主文件。兼容原 `app/tool/make_brand_mark.py` 的路径/渐变输入协议；替换后运行该生成器，提交生成的 `app/lib/ui/shell/brand_glyph.g.dart`。
- `icon.svg`、`icon-1024.png`、`icon-512.png`：仓库与宣传使用的浅色版；深色版本见同目录。
- `preview.png`：浅色、深色、圆形裁切和 24/32/48/64/96px 可见预览。
- `MANIFEST.json`：相对路径、字节数、SHA256。接入前后请逐项读回。

主图形所有着色路径均限制在 Android 108dp 网格中心半径 32.5dp 内，留在 66dp 安全圆内。单色主题图标的双眼为透明挖空；保持白色图形相同透明度会丢失双眼，应沿用提供的非零环绕矢量。

`generate-branding.mjs` 从原创几何生成 SVG/Android XML，再调用 Windows System.Drawing 将同一组路径栅格化；`render-branding.ps1` 支持重新生成全部密度。未调用外部图像模型或网络服务。

## 接入边界

只从本目录复制明确列出的 `app/` 文件。不要覆盖包名、签名、账号数据、已有功能、依赖或运行时。此图标包不自动处理 DSH Go 另外受限的 Deepy/鲸娘/whale/star 美术：公开发行前仍需换成原创素材；保留桌宠功能可用新的原创纹理替换，不把原测试包当作已完成公开发行检查。

打包完成后请在本地交接记录写明最终源码提交、APK 路径与 SHA256、图标清单核对结果。无需向本聊天发消息即可由我读回该记录；用户对本次交接的授权不扩大到真实 Bot 消息、手机安装或上游发布。
