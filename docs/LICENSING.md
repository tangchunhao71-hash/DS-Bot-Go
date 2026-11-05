# 来源与许可范围

DS Bot Go 是独立维护的衍生增强项目。上游名称仅用于说明来源、兼容关系和贡献归属，不表示上游认可或联合发行。

## 组件范围

| 范围 | 许可和声明 |
| --- | --- |
| `mobile/` 的 DSH Go 衍生客户端 | 保留 `mobile/LICENSE` 的 AGPL-3.0；本项目以 AGPL-3.0 公开该客户端的完整修改源码。独立新增内容的额外许可不取消完整衍生客户端的 AGPL 条件。 |
| `desktop/ds-bot/` | 保留 Apache-2.0、NOTICE 和上游署名；本项目的移动 API 修改在 MODIFICATIONS.md 和源码中说明。 |
| `desktop/remote/` | 保留上游 MIT 正文及其他第三方许可。 |
| `branding/` | 本项目原创图形和生成脚本，MIT；没有采用上游受限的品牌和吉祥物美术。 |
| `tools/` | 本项目原创发布辅助工具，MIT；不会改变被构建软件的许可。 |

仓库根 LICENSE 为 AGPL-3.0，表示主客户端的衍生发行许可；上表单独标明的独立组件仍保留其本身的许可。第三方依赖、字体、图标、WebRTC 和 Linux 运行时还应阅读 `mobile/THIRD_PARTY_NOTICES.md`、各组件许可文件及运行时内的声明。

## 对应源码

每个 APK 发行版同时提供对应的源代码归档与固定仓库提交。归档保留构建脚本、依赖锁文件、源代码和本项目素材生成输入；发行说明标明构建版本、源码提交和 SHA256。构建入口见 GETTING_STARTED.md。

重新分发修改版时，继续保留适用许可、署名、修改说明和所需的对应源码。主客户端的 AGPL 要求不能用“原创部分 MIT”覆盖；单独聚合的独立作品各自适用其许可。

## 品牌与素材

DSH Go 的源码许可与其品牌素材使用条件分开。其 [ASSETS.md](https://github.com/ccch1mneyyy/dsh-Go/blob/main/ASSETS.md) 要求修改版、衍生版重新发布时替换原品牌和受限吉祥物。本项目采用 DS Bot Go 名称与原创 Bot 素材；不把原版的 Deepy、鲸娘、品牌标识或官网宣传页当作自己的产品素材。

上游测试和文档中的历史名称是来源记录，不表示本项目改变了它们的版权归属。不要从源码、历史基线或第三方页面另行提取受限素材用于自己的发行。

## 原始项目

- DSH Go — https://github.com/ccch1mneyyy/dsh-Go
- DS Bot — https://github.com/Fei2411/DS-Bot
- DS Harness Remote — https://github.com/liguobao/ds-harness-remote
- DeepSeek Harness — https://github.com/deepseek-ai/deepseek-harness

版本与本地修改来源见仓库根 UPSTREAMS.json。项目没有取得更改上游许可证或代表上游授权品牌素材的权利。
