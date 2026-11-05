# DS Bot Go

Continue using your desktop DS Bot team from an Android phone.

DS Bot Go is an independent community derivative of [DSH Go](https://github.com/ccch1mneyyy/dsh-Go), [DS Bot](https://github.com/Fei2411/DS-Bot) and [DS Harness Remote](https://github.com/liguobao/ds-harness-remote), built on [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness). It uses its own Bot artwork and is not an official DeepSeek or upstream release.

[Download](https://github.com/tangchunhao71-hash/DS-Bot-Go/releases/latest) · [中文](README.md) · [Build and install](docs/GETTING_STARTED.md) · [Licensing](docs/LICENSING.md)

The mobile workspace connects to the existing desktop team through authenticated Remote calls and feeds. It includes team and conversation navigation, search, host-scoped layout preferences, avatar handling, and access to existing schedule operations. Available operations depend on the compatible desktop components and their permissions.

Install the arm64 APK on Android 8 or later. Remote mode still requires an online desktop DS Bot Host. The installer does not provide model accounts, API keys or another person's data.

Source is grouped under `mobile/`, `desktop/ds-bot/` and `desktop/remote/`; exact source revisions are listed in `UPSTREAMS.json`. Original artwork and its generator are in `branding/`.

The DSH Go-derived client remains AGPL-3.0. Separate original artwork and release tools are MIT. DS Bot and Remote retain their Apache-2.0 and MIT notices respectively; third-party notices remain in each component. This repository is not a blanket MIT relicensing of the upstream code.

Issues are welcome. External pull requests are not accepted or merged; please describe the problem or proposal in an Issue. This contribution policy does not restrict rights granted by the applicable licenses.
