# 品牌与吉祥物素材

## DS Bot Go 派生版

本派生版的安装名称是 **DS Bot Go**。当前 APK 中的桌面图标、`app/assets/brand/` 主文件及生成的品牌代码，和 `app/assets/pets/`、`app/assets/whale/`、`app/assets/star/` 的纹理已换为 DS Bot Go 原创机器人美术，按 MIT 许可提供，见 `app/assets/licenses/ds-bot-go-artwork.txt`。旧资源目录与宠物 ID 仅为兼容已保存的设置而保留，动画状态映射与时序沿用原 AGPL 代码和元数据。

下文描述原上游素材的权利范围，适用于尚保留的上游原始美术与文档展示材料，不是对本次原创 Bot 美术的权利声明。公开发布对应源码前仍须核对这些未打入 APK 的原始素材。

## 原上游素材说明

DSH Go 的源码以 AGPL-3.0 发布（见 [LICENSE](LICENSE)），但下面这些品牌和美术素材**不在 AGPL-3.0 授权范围内**。它们的版权归 ccch1mneyyy（DSH-TUI）所有，保留所有权利。

你可以为了构建、测试和运行本仓库而使用它们。如果你以修改版或衍生作品的身份再发布，请换成自己的名称和素材。

| 素材 | 位置 | 来源 |
|---|---|---|
| DSH Go 品牌标识（鱼尾与气泡） | `app/assets/brand/`；由它生成的 `app/lib/ui/shell/brand_glyph.g.dart`、启动图标 `app/android/app/src/main/res/mipmap-*/`、`drawable/ic_launcher_*` | DSH Go 自己的品牌图形 |
| Deepy 小鲸鱼（像素鲸鱼桌宠） | 源文件 `app/tool/pet_src/deepy-whale/`；宠物包 `app/assets/pets/deepy-whale/` | DSH-TUI 的吉祥物。源文件按 [Clawd on Desk](https://github.com/rullerzhou-afk/clawd-on-desk) 的主题包格式制作，只沿用了它的格式 |
| 鲸娘（像素鲸鱼娘表情） | 源文件 `app/tool/pet_src/whale-girl/`（`index.html` 是 https://dshtui.com/pets/whale-girl-emoji/ 原页面，里面有事件对应关系和逐帧时长）；宠物包 `app/assets/pets/whale-girl/`；求 Star 弹窗的贴纸 `app/assets/star/star_whale.webp` | DSH-TUI 的吉祥物，最初发布在 dshtui.com |

鲸鱼尾巴图形（`app/assets/whale/`，源文件 `app/tool/whale_src/`）：其中一个是 DeepSeek 的官方图标，版权和商标归 DeepSeek 所有，仅用于表明本应用连接的是 DeepSeek 服务；其余几张是基于它的二创。它们同样不在 AGPL-3.0 授权范围内。如果权利人提出要求，我们会替换。

这些鲸鱼形象是 DSH-TUI 自己的非官方形象，和 DeepSeek 没有关系，也不代表 DeepSeek。

go.dshtui.com 首页（`site/home/`）由社区开发者 ClayGao233 / 采云师烧饼制作，网页本身的来源和使用条件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。其中的 `dist/assets/dsh-go.svg`（`app/assets/brand/tile.svg` 的副本）、`dist/assets/dsh-go-pop.svg`（由品牌图形改出的立体版）和功能展示图里的品牌图形、鲸娘形象同样适用本页的条件。

仓库首页 README 用到的展示素材 `docs/assets/`（首图、社交预览图、桌宠动图、社群二维码）同样适用本页的条件：可以随本仓库一起查看和转载介绍，不要用在你自己发布的产品上。

宠物包由 `app/tool/make_pet_pack.py` 从 `app/tool/pet_src/` 生成，品牌图形的代码由 `app/tool/make_brand_mark.py` 从 `app/assets/brand/` 生成。工具脚本本身和其他源码一样，以 AGPL-3.0 发布。

第三方的代码、字体、图标和运行时组件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
