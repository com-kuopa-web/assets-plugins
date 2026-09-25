#!/usr/bin/env bash
# 从 **ffmpeg.org 官方源码** 自建 LGPL 版 ffmpeg
#
# 为什么走源码：官方下载页写明 "FFmpeg only provides source code."
# 第三方预编译产物（gyan/BtbN/evermeet）多为 --enable-gpl，macOS 上几乎没有 LGPL 产物。
# 自建的好处：对应源码最清晰（官方发布包 + 签名）、可精确控制 --disable-gpl/--disable-nonfree。
#
# 用法：
#   bash scripts/build-lgpl-ffmpeg.sh 7.1.5
#   FFMPEG_SRC_SHA256=<已知哈希> bash scripts/build-lgpl-ffmpeg.sh 7.1.5   # 固定源码校验和（推荐）
#   EXTRA_CONFIGURE="--enable-nvenc" bash scripts/build-lgpl-ffmpeg.sh 7.1.5
#
# 依赖：
#   macOS : brew install nasm pkg-config lame opus libass freetype
#   Ubuntu: sudo apt-get install -y nasm pkg-config libmp3lame-dev libopus-dev libass-dev libfreetype6-dev
#
# 产物：
#   .build/out/bin/ffmpeg                  ← 交给 build-ffmpeg-plugin.mjs 打包
#   .build/SOURCE-SHA256.txt               ← 源码包校验和（合规记录）
#   licenses/COPYING.LGPLv2.1              ← 从源码树复制（随组件包分发）
set -euo pipefail

FFMPEG_VERSION="${1:-7.1.5}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${WORKDIR:-$ROOT/.build}"
mkdir -p "$WORKDIR" "$ROOT/licenses"
cd "$WORKDIR"

TARBALL="ffmpeg-${FFMPEG_VERSION}.tar.xz"
URL="https://ffmpeg.org/releases/${TARBALL}"

# ---------- 1) 取官方源码 + 校验 ----------
if [ ! -f "$TARBALL" ]; then
  echo "[1/4] 下载官方源码：$URL"
  curl -fL -o "$TARBALL" "$URL"
  curl -fL -o "${TARBALL}.asc" "${URL}.asc" || echo "  (未取到 .asc 签名文件，跳过 PGP 校验)"
else
  echo "[1/4] 复用已下载的源码包"
fi

SHA="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
echo "$SHA  $TARBALL  (ffmpeg ${FFMPEG_VERSION})" | tee "$WORKDIR/SOURCE-SHA256.txt"

if [ -n "${FFMPEG_SRC_SHA256:-}" ] && [ "$SHA" != "$FFMPEG_SRC_SHA256" ]; then
  echo "✗ 源码校验和不匹配：期望 $FFMPEG_SRC_SHA256，实际 $SHA" >&2
  exit 1
fi

# PGP 校验（能校验就校验，不强求环境具备）
if [ -f "${TARBALL}.asc" ] && command -v gpg >/dev/null 2>&1; then
  if ! gpg --list-keys FFmpeg >/dev/null 2>&1; then
    curl -fsSL https://ffmpeg.org/ffmpeg-devel.asc | gpg --import >/dev/null 2>&1 || true
  fi
  if gpg --verify "${TARBALL}.asc" "$TARBALL" 2>/dev/null; then
    echo "  ✓ PGP 签名校验通过（FFmpeg release signing key）"
  else
    echo "  ⚠️ PGP 校验未通过/不可用 —— 请人工确认；建议用 FFMPEG_SRC_SHA256 固定校验和"
  fi
fi

# ---------- 2) 解开 ----------
if [ ! -d "ffmpeg-${FFMPEG_VERSION}" ]; then
  echo "[2/4] 解压源码"
  tar xf "$TARBALL"
fi
cd "ffmpeg-${FFMPEG_VERSION}"

# 许可证原文随组件分发（LGPL 义务之一）
for f in COPYING.LGPLv2.1 COPYING.LGPLv3 LICENSE.md COPYING.GPLv3; do
  [ -f "$f" ] && cp "$f" "$ROOT/licenses/$f"
done
[ -f "$ROOT/licenses/COPYING.LGPLv2.1" ] || {
  echo "  ⚠️ 源码树里没有 COPYING.LGPLv2.1；请从 https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt 取一份放入 licenses/"
}

# ---------- 3) configure + make ----------
# 关键：--disable-gpl --disable-nonfree ⇒ 产物为 LGPL 构建。
# libmp3lame(LGPL) / libopus(BSD) / libass(ISC) / freetype(FTL) 均与 LGPL 兼容；不启用任何 GPL 组件。
EXTRA=()
if [ "$(uname -s)" = "Darwin" ]; then
  EXTRA+=(--enable-videotoolbox --enable-audiotoolbox)
elif [ "$(uname -s)" = "Linux" ]; then
  # 硬件编码（可选依赖，装了才启用；否则 Linux 上无可用 H.264 编码器 → 只能 -c copy）
  pkg-config --exists libvpl 2>/dev/null && EXTRA+=(--enable-qsv) || true
  [ -d /usr/include/ffnvcodec ] || [ -d /usr/local/include/ffnvcodec ] && EXTRA+=(--enable-nvenc) || true
  [ -d /usr/include/libva ] && EXTRA+=(--enable-vaapi) || true
fi

echo "[3/4] configure（LGPL）${EXTRA[*]:-（无额外开关）}"
./configure \
  --prefix="$WORKDIR/out" \
  --disable-gpl --disable-nonfree \
  --disable-doc --disable-debug --disable-ffplay \
  --enable-libmp3lame --enable-libopus --enable-libass --enable-libfreetype \
  --enable-static --disable-shared \
  ${EXTRA_CONFIGURE:-} "${EXTRA[@]}"

echo "[4/4] 编译（较慢，CI 上约 10~25 分钟）"
make -j"$( (nproc 2>/dev/null || sysctl -n hw.ncpu) )"
make install

echo
echo "✅ 产物：$WORKDIR/out/bin/ffmpeg"
"$WORKDIR/out/bin/ffmpeg" -hide_banner -version | sed -n '1,3p'
echo
echo "⚠️ 请确认上面 configuration 行里 **没有** --enable-gpl / --enable-nonfree"
echo "   源码校验和：$SHA（已记录到 SOURCE-SHA256.txt，写进组件包 build-info.json 便于合规追溯）"
