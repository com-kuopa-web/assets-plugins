# assets-plugins —— AssetsHelper 官方资产组件（插件）分发仓库

本仓库是 **公开的组件分发源**：App（AssetsHelper）在「设置 → 播放 → FFmpeg → 组件源」里指向本仓库的
`plugin-catalog.json`，即可按需下载/校验/安装组件。

> 仓库只做两件事：
> 1. **放清单** `plugin-catalog.json`（几 KB，告诉 App「有哪些组件、在哪下、sha256 是多少、镜像有哪些」）；
> 2. **放 CI** 与构建脚本（把 FFmpeg 之类的第三方二进制打包成合规组件包，作为 **Release 资源**上传）。
>
> ⚠️ **二进制不进仓库**：40~80MB 的文件会让 clone 变慢、仓库膨胀；Release 资源有独立 CDN、单文件可到 2GB。
> 且 GitHub 限制单个仓库 2GB、raw 有速率限制。

## 目录

```
assets-plugins/
├── plugin-catalog.json                     # ★ App 拉取的清单（CI 自动更新）
├── .github/workflows/release-ffmpeg.yml    # 打 tag 即发布：构建 → 打包 → 上传 Release → 更新清单
├── scripts/
│   ├── build-ffmpeg-plugin.mjs             # 组件打包器（从主仓库 AssetsHelper 同步）
│   ├── build-lgpl-ffmpeg.sh                # 从 ffmpeg.org **官方源码** 自建 LGPL 版并记录校验和
│   └── update-catalog.mjs                  # 用产物自动更新清单（sha256/size/downloadUrl）
└── licenses/                               # 许可证原文（构建时从 FFmpeg 源码树复制进组件包）
```

## 为什么是"从源码自建"

ffmpeg.org 的官方下载页写明：**“FFmpeg only provides source code.”**
它给出的预编译产物链接（gyan.dev / BtbN / evermeet.cx）都是**第三方**，且大多是 `--enable-gpl` 甚至 `--enable-nonfree` 构建
（后者按官方说明**不可再分发**）。

自建的好处：
- 只用官方源码 + 我们自己的 configure 行 → **"对应源码"这条义务最好满足**（就是 ffmpeg.org 的发布包，签名可验证）；
- 可以明确禁用 GPL/nonfree，产物是**LGPL**，义务最轻；
- macOS 本来也几乎没有现成的 LGPL 预编译产物。

代价：LGPL 构建**没有 libx264**（软件 H.264 编码），只能硬件编码（VideoToolbox / NVENC / QSV / AMF）或 `-c copy` 直通。

## 发布一个版本

```bash
git tag ffmpeg-7.1.5 && git push origin ffmpeg-7.1.5
```

CI 会：下载官方源码（校验 PGP 签名 / 记录 sha256）→ 自建 LGPL ffmpeg → 打包（`--require-lgpl` 强制）
→ 上传各平台 zip 到 Release → 更新并提交 `plugin-catalog.json`。

## App 端怎么用

设置 → 播放 → FFmpeg：
- 「组件源」留空 = 用内置官方源（指向本仓库）；
- 也可填镜像/内网地址（网络受限时换源，无需重新发版）；
- 首次启动会**后台自动扫描**本机已有的 ffmpeg，扫描不到时才需要下载或导入组件包。

## 许可证

- 本仓库的**脚本与清单**：随主项目授权；
- Release 中的 **FFmpeg 二进制**：由 FFmpeg 项目提供，按对应构建的许可证（本仓库默认 **LGPL-2.1-or-later**）分发；
  每个组件包内带 `licenses/`（来自 FFmpeg 源码树）与 `THIRD-PARTY-NOTICES.md`（版本、configure 行、源码获取方式、替换方法）。
- 源码获取：`https://ffmpeg.org/releases/ffmpeg-<version>.tar.xz`（清单/组件包里的 `build-info.json` 记录了版本、configure 行与源码包 sha256）。
