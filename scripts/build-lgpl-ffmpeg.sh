#!/usr/bin/env bash
# 从 **ffmpeg.org 官方源码** 自建 LGPL 版 ffmpeg（macOS / Linux / Windows(MSYS2) 通用）
#
# 为什么走源码：官方下载页写明 “FFmpeg only provides source code.”
# 第三方预编译产物（gyan / BtbN / evermeet / Homebrew）多为 --enable-gpl，macOS 上几乎没有 LGPL 产物。
#
# 默认是 **最小构建**：只用 FFmpeg 自带编解码器 +（macOS）VideoToolbox /（Windows）NVENC·QSV 等硬件编码，
# 不链接任何外部库 —— 依赖最少、编译最快、产物最小，且完全满足本项目的需要
# （截帧/探测靠解码，转码优先硬件编码，音轨用 `-c:a copy`）。
# 需要 libmp3lame/libopus/libass/freetype 时用 FULL=1（编译更慢、依赖更多）。
#
# 用法：
#   bash scripts/build-lgpl-ffmpeg.sh                 # 默认版本见下
#   bash scripts/build-lgpl-ffmpeg.sh 8.1.3           # 指定版本
#   FULL=1 bash scripts/build-lgpl-ffmpeg.sh 7.1.5    # 额外链接 lame/opus/ass/freetype
#   FFMPEG_SRC_SHA256=<已知哈希> bash scripts/build-lgpl-ffmpeg.sh   # 锁定源码校验和（推荐）
#   FFMPEG_SRC_URL=<镜像或 GitHub 归档地址> bash scripts/build-lgpl-ffmpeg.sh   # 官方源太慢/不稳时换源
#     （下载支持断点续传：中断后重跑同一命令会从断点继续）
#
# 依赖：
#   macOS  : xcode 命令行工具 + brew install nasm pkg-config        （最小构建仅此两项）
#   Ubuntu : sudo apt-get install -y nasm pkg-config
#   Windows: MSYS2 MINGW64 —— pacman -S --needed make nasm pkgconf diffutils
#   （FULL=1 再加 lame/opus/libass/freetype 的开发包）
#
# 产物：
#   .build/out/bin/ffmpeg[.exe]      ← 交给 scripts/build-ffmpeg-plugin.mjs 打包
#   .build/SOURCE-SHA256.txt         ← 源码包校验和（合规记录）
#   licenses/COPYING.LGPLv2.1        ← 从源码树复制（随组件包分发，LGPL 义务之一）
set -euo pipefail

FFMPEG_VERSION="${1:-7.1.5}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${WORKDIR:-$ROOT/.build}"
mkdir -p "$WORKDIR" "$ROOT/licenses"
cd "$WORKDIR"

case "$(uname -s)" in
  Darwin)                       PLATFORM=macos ;;
  Linux)                        PLATFORM=linux ;;
  MINGW*|MSYS*|CYGWIN*)         PLATFORM=windows ;;
  *)                            PLATFORM=unknown ;;
esac

# ---------- 1) 官方源码：可断点续传的下载 + 完整性校验 + 自愈 ----------
# 注意：网络中断会留下"半截 tar.xz"，若只用"文件存在"判断复用，下一次会解压失败。
# 所以这里：① 下到 .part 再改名；② 复用前先做完整性校验；③ 校验不过就删掉重下。
TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"
SRC_URL="${FFMPEG_SRC_URL:-https://ffmpeg.org/releases/${TARBALL}}"
ASC_URL="${FFMPEG_SRC_URL:+}${FFMPEG_SRC_URL:-https://ffmpeg.org/releases/${TARBALL}}.asc"

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}

# 用 tar 读一遍归档来校验完整性（macOS 自带 bsdtar 支持 xz，无需额外装 xz）
verify_tarball() {
  [ -f "$1" ] && tar -tf "$1" >/dev/null 2>&1
}

# curl 的续传/重试参数（--retry-all-errors 在旧版 curl 上不存在，探测后再加）
CURL_ARGS=(-fL --retry 5 --retry-delay 3 --retry-connrefused -C -)
if curl --help all 2>/dev/null | grep -q -- '--retry-all-errors'; then CURL_ARGS+=(--retry-all-errors); fi
# 空数组安全展开（见下方 configure 处的说明）

MARKER="$WORKDIR/.unpacked-${FFMPEG_VERSION}"   # 解压完整性标记

if [ -f "$TARBALL" ] && ! verify_tarball "$TARBALL"; then
  echo "⚠️ 已存在的源码包不完整/损坏（很可能是上次下载中断留下的半截文件）→ 删除后重下"
  rm -f "$TARBALL" "$TARBALL.asc" "$WORKDIR/SOURCE-SHA256.txt" "$MARKER"   # 源码换了 → 解压缓存一并失效
fi

if [ ! -f "$TARBALL" ]; then
  echo "[1/4] 下载官方源码：$SRC_URL"
  echo "      （支持断点续传：网络中断后**重跑本脚本**会从断点继续）"
  if ! curl "${CURL_ARGS[@]}" -o "${TARBALL}.part" "$SRC_URL"; then
    echo "✗ 下载失败（已保留 ${TARBALL}.part，重跑本脚本会继续下载）" >&2
    echo "  若 ffmpeg.org 在你所在网络很慢/不稳，可用镜像或 GitHub 归档覆盖源地址：" >&2
    echo "    FFMPEG_SRC_URL=https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n${FFMPEG_VERSION}.tar.gz \\" >&2
    echo "      bash scripts/build-lgpl-ffmpeg.sh ${FFMPEG_VERSION}" >&2
    exit 1
  fi
  mv -f "${TARBALL}.part" "$TARBALL"
  rm -f "$MARKER"   # 新下载的源码 → 旧解压结果作废
else
  echo "[1/4] 复用已下载的源码包（已通过完整性校验）"
fi

if ! verify_tarball "$TARBALL"; then
  echo "✗ 源码包校验失败（tar 无法读取）：$TARBALL" >&2
  echo "  删掉后重跑：rm -f $WORKDIR/$TARBALL && bash scripts/build-lgpl-ffmpeg.sh ${FFMPEG_VERSION}" >&2
  exit 1
fi

# 只有校验通过的包才记录哈希（避免把半截文件的哈希写进合规记录）
SHA="$(sha256_of "$TARBALL")"
echo "$SHA  $TARBALL  (ffmpeg ${FFMPEG_VERSION})  $SRC_URL" | tee "$WORKDIR/SOURCE-SHA256.txt"

if [ -n "${FFMPEG_SRC_SHA256:-}" ] && [ "$SHA" != "$FFMPEG_SRC_SHA256" ]; then
  echo "✗ 源码校验和不匹配：期望 ${FFMPEG_SRC_SHA256} ，实际 ${SHA}" >&2
  exit 1
fi

# PGP 校验（仅官方源有 .asc；能校验就校验）
if [ -z "${FFMPEG_SRC_URL:-}" ] && command -v gpg >/dev/null 2>&1; then
  curl -fsSL --retry 3 -o "${TARBALL}.asc" "${ASC_URL}" || true
  if [ -f "${TARBALL}.asc" ]; then
    gpg --list-keys FFmpeg >/dev/null 2>&1 || curl -fsSL https://ffmpeg.org/ffmpeg-devel.asc | gpg --import >/dev/null 2>&1 || true
    if gpg --verify "${TARBALL}.asc" "$TARBALL" 2>/dev/null; then
      echo "  ✓ PGP 签名校验通过（FFmpeg release signing key）"
    else
      echo "  ⚠️ PGP 校验不可用/未通过 —— 建议用 FFMPEG_SRC_SHA256 固定校验和"
    fi
  fi
fi

# ---------- 2) 解压：原子化 + 完整性判断 + 取许可证原文 ----------
# 为什么不能只看 configure 是否存在：上一次"解压中断"留下的半个目录里**通常已经有 configure**，
# 于是会被误判为完整 → make 阶段才报 `ffbuild/common.mak: No such file or directory`。
# 这里做三件事：① 逐个检查关键文件；② 解压到临时目录再原子改名；③ 成功后打完整性标记。
REQUIRED_TREE="configure ffbuild/common.mak fftools/Makefile libavcodec/Makefile libavformat/Makefile"
tree_ok() {
  local d="ffmpeg-${FFMPEG_VERSION}"
  [ -d "$d" ] || return 1
  for f in $REQUIRED_TREE; do [ -f "$d/$f" ] || return 1; done
  return 0
}

if [ -f "$MARKER" ] && tree_ok; then
  echo "[2/4] 复用已解压的源码（完整性标记存在）"
else
  if [ -d "ffmpeg-${FFMPEG_VERSION}" ]; then
    echo "⚠️ 上一次解压不完整（或源码包已更新）→ 清理后重新解压"
  fi
  echo "[2/4] 解压源码（先解到临时目录，成功后再原子改名）"
  rm -rf "ffmpeg-${FFMPEG_VERSION}" "$MARKER"
  UNPACK_TMP="$WORKDIR/.unpack-$$"
  rm -rf "$UNPACK_TMP"; mkdir -p "$UNPACK_TMP"
  if ! tar xf "$TARBALL" -C "$UNPACK_TMP"; then
    rm -rf "$UNPACK_TMP"
    echo "✗ 解压失败（源码包很可能损坏：先 rm -f $WORKDIR/$TARBALL 再重跑）" >&2
    exit 1
  fi
  if [ ! -d "$UNPACK_TMP/ffmpeg-${FFMPEG_VERSION}" ]; then
    rm -rf "$UNPACK_TMP"
    echo "✗ 解压结果里没有 ffmpeg-${FFMPEG_VERSION} 目录，源码包异常" >&2
    exit 1
  fi
  mv "$UNPACK_TMP/ffmpeg-${FFMPEG_VERSION}" "ffmpeg-${FFMPEG_VERSION}"
  rmdir "$UNPACK_TMP" 2>/dev/null || true
  tree_ok || { echo "✗ 解压后仍缺关键文件（${REQUIRED_TREE} ），源码包异常" >&2; exit 1; }
  touch "$MARKER"
fi

cd "ffmpeg-${FFMPEG_VERSION}"
for f in COPYING.LGPLv2.1 COPYING.LGPLv3 COPYING.GPLv3 LICENSE.md; do
  [ -f "$f" ] && cp "$f" "$ROOT/licenses/$f"
done
[ -f "$ROOT/licenses/COPYING.LGPLv2.1" ] && echo "  ✓ 许可证原文已复制到 licenses/" || echo "  ⚠️ 源码树里没有 COPYING.LGPLv2.1，请手动放一份到 licenses/"

# ---------- 3) configure ----------
# 关键：--disable-gpl --disable-nonfree ⇒ 产物是 LGPL；绝不启用 libx264/libx265/fdk-aac 等。
#
# 硬件编码开关速查（依据 FFmpeg 7.x 自己的 configure 声明，别凭 pkg-config 名字猜！）：
#   nvenc          开关 --enable-nvenc      依赖 pkg-config `ffnvcodec`（**只要头文件**，
#                                            运行期 dlopen NVIDIA 驱动）→ 产物仍单文件
#   amf            开关 --enable-amf        依赖 `amf_deps_any="libdl LoadLibrary"`（**无 pkg-config**，
#                                            只要头文件，运行期 dlopen amfrt64.dll）→ 仍单文件
#   videotoolbox   开关 --enable-videotoolbox  依赖 macOS 系统框架 → 仍单文件
#   qsv            ❗**没有 `--enable-qsv`**：用 --enable-libvpl（oneVPL）或 --enable-libmfx（旧 MediaSDK）
#                  → 需要**链接** libvpl/libmfx，产物会依赖运行库（DLL/SO）→ 默认关闭
#   vaapi          开关 --enable-vaapi      需要链接 libva → 同上，默认关闭
#
# 因此默认只启用"仅头文件 + 运行期动态加载"的编码器，保证产物是**单个可执行文件**（组件包只发 bin/ffmpeg）。
# 需要 QSV/VAAPI 时用 ENABLE_QSV=1 / ENABLE_VAAPI=1 显式开启（会带来运行库依赖，脚本会警告）。
HW=()
add_hw() {
  for x in ${HW[@]+"${HW[@]}"}; do [ "$x" = "$1" ] && return; done   # 去重（此前 --enable-nvenc 会被加两次）
  HW+=("$1")
}
have_pc() { pkg-config --exists "$1" 2>/dev/null; }
have_hdr() { [ -d "/mingw64/include/$1" ] || [ -d "/usr/include/$1" ] || [ -d "/usr/local/include/$1" ]; }

EXTRA=()
if [ "$PLATFORM" = "macos" ]; then
  add_hw --enable-videotoolbox
  add_hw --enable-audiotoolbox
fi
if [ "$PLATFORM" = "windows" ]; then
  # 便携性：静态链接 exe，避免用户机器缺 DLL（对"仅头文件"的 nvenc/amf 无副作用）
  EXTRA+=(--pkg-config-flags=--static --extra-ldexeflags=-static)
fi
if [ "$PLATFORM" = "windows" ] || [ "$PLATFORM" = "linux" ]; then
  if have_pc ffnvcodec || have_hdr ffnvcodec; then add_hw --enable-nvenc; fi
fi
if [ "$PLATFORM" = "windows" ]; then
  if have_hdr AMF || have_hdr amf; then add_hw --enable-amf; fi
fi
if [ "${ENABLE_QSV:-0}" = "1" ]; then
  if have_pc vpl || have_pc libvpl; then
    add_hw --enable-libvpl
    echo "  ⚠️ ENABLE_QSV=1：产物会依赖 oneVPL 运行库（Windows 需 libvpl-2.dll）→ 不再是单文件"
  else
    echo "  ⚠️ ENABLE_QSV=1 但找不到 oneVPL（pkg-config: vpl / libvpl）→ 跳过 QSV"
  fi
fi
if [ "${ENABLE_VAAPI:-0}" = "1" ] && [ "$PLATFORM" = "linux" ]; then
  if have_pc libva; then
    add_hw --enable-vaapi
    echo "  ⚠️ ENABLE_VAAPI=1：产物会依赖 libva → 不再是单文件"
  else
    echo "  ⚠️ ENABLE_VAAPI=1 但找不到 libva → 跳过 VAAPI"
  fi
fi

FULL_LIBS=()
FULL_LABEL=""
if [ "${FULL:-0}" = "1" ]; then
  FULL_LIBS=(--enable-libmp3lame --enable-libopus --enable-libass --enable-libfreetype)
  FULL_LABEL=" / FULL"
  echo "  ℹ️ FULL=1：额外链接 libmp3lame / libopus / libass / freetype（需对应开发包）"
fi

echo "[3/4] configure（LGPL${FULL_LABEL}）"
echo "  平台开关：${EXTRA[*]:-（无）}"
echo "  硬件编码：${HW[*]:-（无——将只能 -c copy 直通）}"
if [ ${#HW[@]} -eq 0 ]; then
  echo "  ⚠️ 没有可用的硬件编码器：本构建无法转码（LGPL 构建没有 libx264）。"
  echo "     常见原因：缺 ffnvcodec 头文件（NVENC）/ AMF 头文件（AMD）/ 非 macOS 平台。"
fi
# 说明：数组用 ${arr[@]+"${arr[@]}"} 展开 —— macOS 自带 bash 3.2 下，
# `set -u` + 空数组的 "${arr[@]}" 会报 unbound variable（bash 4.4 才修）。
# shellcheck disable=SC2086
./configure \
  --prefix="$WORKDIR/out" \
  --disable-gpl --disable-nonfree \
  --disable-doc --disable-debug --disable-ffplay --disable-sdl2 \
  --enable-static --disable-shared \
  ${EXTRA_CONFIGURE:-} ${EXTRA[@]+"${EXTRA[@]}"} ${HW[@]+"${HW[@]}"} ${FULL_LIBS[@]+"${FULL_LIBS[@]}"}

# ---------- 4) 编译 ----------
JOBS="$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4) )"
echo "[4/4] 编译（-j${JOBS} ；首次在 CI 上约 10~25 分钟）"
make -j"$JOBS"
make install

EXE="$WORKDIR/out/bin/ffmpeg"
[ -f "$EXE.exe" ] && EXE="$EXE.exe"
echo
echo "✅ 产物：$EXE"
"$EXE" -hide_banner -version | sed -n '1,3p'
echo
if "$EXE" -hide_banner -version | grep -qE -- '--enable-(gpl|nonfree)'; then
  echo "✗✗ configuration 行里出现了 --enable-gpl/--enable-nonfree：这不是 LGPL 构建，禁止分发！" >&2
  exit 1
fi
echo "✓ 已确认 configuration 行不含 --enable-gpl / --enable-nonfree（LGPL 构建）"
echo "  源码校验和：${SHA} （记录在 SOURCE-SHA256.txt）"
echo
echo "下一步：bash scripts/build-local.sh --skip-build   # 或直接 node scripts/build-ffmpeg-plugin.mjs --bin $EXE --license licenses/COPYING.LGPLv2.1 --version $FFMPEG_VERSION"
