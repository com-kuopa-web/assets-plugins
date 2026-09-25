# licenses/

许可证原文（LGPL 义务之一：**必须随组件包分发**）。

这些文件**不需要手工维护**：`scripts/build-lgpl-ffmpeg.sh` 会在解压官方源码后，
把 FFmpeg 源码树里的 `COPYING.LGPLv2.1`（LGPL 构建）或 `COPYING.GPLv3`（若改用 GPL 构建）复制到这里，
随后 `scripts/build-ffmpeg-plugin.mjs --license licenses/COPYING.LGPLv2.1` 会把它打进组件包。

若源码树里没有该文件，可从下列地址取一份（与 FFmpeg 自带内容一致）：

- LGPL 2.1：https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt
- GPL 3.0：https://www.gnu.org/licenses/gpl-3.0.txt

> 合规要点见主仓库 `docs/notes/媒体播放/FFmpeg接入与许可证.md`：
> 附许可证原文 + 提供对应源码获取方式 + 允许替换该组件（独立可执行文件天然满足）。
