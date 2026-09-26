# licenses/

许可证原文。**构建脚本会自动从 FFmpeg 源码树把这些文件复制过来**（`build-lgpl-ffmpeg.sh`），
再由 `build-ffmpeg-plugin.mjs --license …` 决定哪些进插件包。

## 哪份适用于我们的插件？

| 文件 | 是否适用本插件 | 说明 |
|---|---|---|
| `COPYING.LGPLv2.1` | ✅ **适用（治理许可证）** | 我们的 configure 是 `--disable-gpl --disable-nonfree`，产物为 **LGPL-2.1-or-later** |
| `LICENSE.md` | ✅ 适用（**范围说明**） | FFmpeg 官方文档：哪些文件 LGPL、哪些是"可选 GPL 部分"、启用 `--enable-gpl` 后整体变 GPL |
| `COPYING.LGPLv3` | ⚠️ 仅当启用 `--enable-version3` 才相关 | 我们没启用；"LGPL v2.1 or later" 里的 "or later" 是给下游的选择权 |
| `COPYING.GPLv3` | ❌ **不适用** | GPL 部分未启用；且 FFmpeg 的 GPL 部分用的是 GPLv2+（其 `LICENSE.md` 引用 `COPYING.GPLv2`） |

> **注意**：多放一份许可文本本身不违法，但会让人误以为"这个二进制是 GPL"。
> 所以**插件包只打 LGPLv2.1 + LICENSE.md**（见 `scripts/build-local.sh`），
> 仓库里保留全部原文只是"源码树原料"，不是"声明"。

## 合规三件套（随插件分发）

| 材料 | 作用 |
|---|---|
| `licenses/COPYING.LGPLv2.1` | 许可证原文 |
| `licenses/LICENSE.md` | 许可证**范围**说明（防止误读） |
| `THIRD-PARTY-NOTICES.md`（打包时生成） | 版本 / configure 行 / 源码获取方式 / 如何替换 |
| `build-info.json`（打包时生成） | 上述事实的**机器可验证证据**（含源码包 sha256） |

义务清单与背景：`web/notes/许可证/` 与 `notes/本体/媒体播放/FFmpeg接入与许可证.md`。
