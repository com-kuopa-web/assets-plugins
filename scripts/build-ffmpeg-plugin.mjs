#!/usr/bin/env node
/**
 * 构建 `official.ffmpeg` 组件包（F2）
 *
 * 产出：
 *   <out>/official.ffmpeg-<version>/
 *     ├── manifest.json            插件清单（provides: capability=ffmpeg）
 *     ├── bin/ffmpeg               可执行文件
 *     ├── licenses/…               许可证原文（必须随组件分发）
 *     ├── THIRD-PARTY-NOTICES.md   来源 / 源码获取方式 / 如何替换
 *     └── build-info.json          configure 行 + 版本 + sha256
 *   <out>/official.ffmpeg-<version>.zip        （有 zip 命令时）
 *   <out>/official.ffmpeg-<version>.sha256     分发包校验和（写进清单源用）
 *   <out>/catalog-entry.json                  可直接粘进 plugin-catalog 的片段
 *
 * 用法：
 *   node scripts/build-ffmpeg-plugin.mjs --bin /path/to/lgpl/ffmpeg \
 *        [--license /path/to/COPYING.LGPLv2.1] [--out dist-plugins] [--version 6.1]
 *
 * 许可证红线（脚本会强制）：
 *   · 含 `--enable-nonfree` 的构建 **不可再分发** → 直接拒绝；
 *   · GPL 构建允许但要提醒"需提供对应源码"；
 *   · 推荐用 **LGPL 构建**（见 docs/notes/媒体播放/FFmpeg接入与许可证.md）。
 */

import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync, rmSync } from 'node:fs'
import { basename, dirname, join, resolve } from 'node:path'

/* ---------------- 参数 ---------------- */
function parseArgs(argv) {
  const out = {
    bin: null,
    license: null,
    out: 'dist-plugins',
    version: null,
    id: 'official.ffmpeg',
    name: 'FFmpeg 组件（第三方）',
    author: 'FFmpeg project',
    requireLgpl: false,
  }
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a === '--bin') out.bin = argv[++i]
    else if (a === '--license') out.license = argv[++i]
    else if (a === '--out') out.out = argv[++i]
    else if (a === '--version') out.version = argv[++i]
    else if (a === '--id') out.id = argv[++i]
    else if (a === '--name') out.name = argv[++i]
    else if (a === '--author') out.author = argv[++i]
    else if (a === '--require-lgpl') out.requireLgpl = true
    else if (a === '-h' || a === '--help') out.help = true
    else {
      console.error(`未知参数：${a}`)
      process.exit(2)
    }
  }
  return out
}

const args = parseArgs(process.argv.slice(2))
if (args.help || !args.bin) {
  console.log(readFileSync(new URL(import.meta.url), 'utf8').split('*/')[0].replace(/^#!.*\n/, ''))
  process.exit(args.help ? 0 : 2)
}

const root = resolve(dirname(new URL(import.meta.url).pathname), '..')
const binPath = resolve(args.bin)
if (!existsSync(binPath)) {
  console.error(`✗ 找不到：${binPath}`)
  process.exit(1)
}

/* ---------------- 探测（与宿主同一套判定） ---------------- */
function run(bin, ffArgs) {
  return execFileSync(bin, ['-hide_banner', ...ffArgs], { encoding: 'utf8', timeout: 8000, maxBuffer: 16 * 1024 * 1024 })
}

console.log(`[build-ffmpeg-plugin] 探测 ${binPath}`)
let versionOut
try {
  versionOut = run(binPath, ['-version'])
} catch (error) {
  console.error(`✗ 这份二进制跑不起来：${error instanceof Error ? error.message : String(error)}`)
  process.exit(1)
}
const version = args.version ?? /ffmpeg version (\S+)/.exec(versionOut)?.[1] ?? 'unknown'
const configuration = /configuration:\s*(.*)/.exec(versionOut)?.[1]?.trim() ?? ''
const encoders = Array.from(run(binPath, ['-encoders']).matchAll(/^\s*[A-Z.]{6}\s+(\S+)/gm)).map((m) => m[1])

const license = /--enable-nonfree\b/.test(configuration)
  ? 'nonfree'
  : /--enable-gpl\b/.test(configuration)
    ? 'GPL'
    : configuration
      ? 'LGPL'
      : 'unknown'

console.log(`  版本 ${version} · 许可证 ${license} · 编码器 ${encoders.length} 个`)

/* ---------------- 许可证红线 ---------------- */
if (license === 'nonfree') {
  console.error(
    '\n✗ 这份构建含 `--enable-nonfree`，按 FFmpeg 官方说明**不可再分发**，不能做成分发包。' +
      '\n  请改用 LGPL 构建（或用户在设置里自行指定路径，由用户自担）。' +
      '\n  参考：docs/notes/媒体播放/FFmpeg接入与许可证.md',
  )
  process.exit(1)
}
if (license === 'GPL' && args.requireLgpl) {
  console.error(
    '\n✗ --require-lgpl：这份是 GPL 构建，CI 要求必须用 LGPL。' +
      '\n  换用 LGPL 构建（scripts/build-lgpl-ffmpeg.sh），或去掉 --require-lgpl 自行承担 GPL 义务。',
  )
  process.exit(1)
}
if (license === 'GPL') {
  console.warn(
    '\n⚠️ 这是 GPL 构建：可以分发，但必须随组件提供许可证原文，并提供/承诺提供**对应源码**。' +
      '\n   想减义务请换 LGPL 构建（代价：没有 libx264 软编，只能硬件编码）。',
  )
}
if (!encoders.some((e) => /h264_(videotoolbox|nvenc|qsv|amf)|libx264/.test(e))) {
  console.warn('⚠️ 这份构建里没找到可用的 H.264 编码器：转码功能会不可用（截帧/探测仍可用）。')
}

/* ---------------- 组装包 ---------------- */
const outDir = resolve(root, args.out)
const pkgDir = join(outDir, `${args.id}-${version}`)
rmSync(pkgDir, { recursive: true, force: true })
mkdirSync(join(pkgDir, 'bin'), { recursive: true })
mkdirSync(join(pkgDir, 'licenses'), { recursive: true })

const exe = process.platform === 'win32' ? 'ffmpeg.exe' : 'ffmpeg'
const destBin = join(pkgDir, 'bin', exe)
copyFileSync(binPath, destBin)
if (process.platform !== 'win32') execFileSync('chmod', ['755', destBin])

/** 许可证文件：显式指定 > 二进制同目录里的 COPYING/LICENSE/NOTICE */
const licenseFiles = []
if (args.license) {
  licenseFiles.push({ name: basename(args.license), path: resolve(args.license) })
} else {
  for (const f of readdirSync(dirname(binPath))) {
    if (/^(copying|license|notice)/i.test(f) && statSync(join(dirname(binPath), f)).isFile()) {
      licenseFiles.push({ name: f, path: join(dirname(binPath), f) })
    }
  }
}
for (const l of licenseFiles) copyFileSync(l.path, join(pkgDir, 'licenses', l.name))
if (licenseFiles.length === 0) {
  writeFileSync(
    join(pkgDir, 'licenses', 'MISSING.txt'),
    [
      `未随包提供许可证原文（构建时没在 ${dirname(binPath)} 找到 COPYING/LICENSE/NOTICE，也没传 --license）。`,
      '',
      license === 'GPL'
        ? 'GPL 构建必须提供许可证原文（COPYING.GPLv3）+ 对应源码获取方式。'
        : 'LGPL 构建必须提供 COPYING.LGPLv2.1（或 v3）+ 对应源码获取方式。',
      '补齐后重新构建：node scripts/build-ffmpeg-plugin.mjs --bin … --license /path/to/COPYING…',
      '',
    ].join('\n'),
    'utf8',
  )
  console.warn('⚠️ 没有找到许可证文件：已在 licenses/MISSING.txt 留下提醒（发布前必须补齐）')
}

const sha256 = createHash('sha256').update(readFileSync(destBin)).digest('hex')

writeFileSync(
  join(pkgDir, 'manifest.json'),
  JSON.stringify(
    {
      id: args.id,
      name: args.name,
      version,
      apiVersion: 1,
      description: `FFmpeg ${version}（${license} 构建）—— 为音视频模块提供转码 / 截帧 / 探测能力`,
      author: args.author,
      official: false,
      kind: 'capability-provider',
      provides: [{ capability: 'ffmpeg', version, license, encoders: encoders.filter((e) => /^(h264|hevc|aac|libx264|libx265)/.test(e)) }],
      permissions: [],
      entry: { host: `bin/${exe}` },
    },
    null,
    2,
  ) + '\n',
  'utf8',
)

writeFileSync(
  join(pkgDir, 'build-info.json'),
  JSON.stringify({ id: args.id, version, license, configuration, sha256, builtAt: new Date().toISOString(), ffmpegVersionOutput: versionOut }, null, 2) + '\n',
  'utf8',
)

writeFileSync(
  join(pkgDir, 'THIRD-PARTY-NOTICES.md'),
  `# 第三方组件声明：FFmpeg ${version}

| 项 | 值 |
|---|---|
| 组件 | FFmpeg（\`ffmpeg\` 可执行文件） |
| 版本 | ${version} |
| 构建许可证 | **${license}** |
| 来源 | ${binPath} |
| SHA-256 | \`${sha256}\` |

## 许可证原文

见 \`licenses/\` 目录（${licenseFiles.map((l) => l.name).join('、') || '⚠️ 缺失，见 licenses/MISSING.txt'}）。

## 对应源码

${version}

- 官方源码：https://ffmpeg.org/download.html （按上面版本号取对应 tag，如 \`n${version.replace(/\./g, '.')}\`）
- 构建配置（configure 行）：

\`\`\`
${configuration || '(未记录)'}
\`\`\`

> 若本组件由第三方预编译产物构建，请一并说明其构建脚本来源。

## 如何替换本组件

本组件是**独立可执行文件**，用户可随时替换：

1. 打开「设置 → 视频 → FFmpeg」；
2. 点「自动扫描本机」选择系统里已有的 FFmpeg，或「手动选择…」指定任意一份；
3. 也可以「导入组件包…」重新导入另一份构建。

替换后立即生效（无需重启）。

## 说明

- 本组件**不随主程序安装包分发**，由用户按需获取；
- 转码优先使用硬件编码（VideoToolbox / NVENC / QSV / AMF）；
  ${
    license === 'LGPL'
      ? 'LGPL 构建不含 libx264，因此**没有软件 H.264 编码**。'
      : '当前为 GPL 构建：如无必要，建议改用 LGPL 构建以减义务。'
  }
`,
  'utf8',
)

console.log(`✅ 组件包目录：${pkgDir}`)

/* ---------------- 打包 zip + 校验和 + 清单片段 ---------------- */
const zipName = `${args.id}-${version}.zip`
const zipPath = join(outDir, zipName)
let zipped = false
try {
  rmSync(zipPath, { force: true })
  // macOS / Linux 自带 zip；Windows 走 PowerShell Compress-Archive（下面 catch 里兜底）
  execFileSync('zip', ['-qr', zipPath, basename(pkgDir)], { cwd: outDir })
  zipped = true
} catch {
  try {
    execFileSync('powershell', ['-NoProfile', '-Command', `Compress-Archive -Path '${pkgDir}' -DestinationPath '${zipPath}' -Force`], { stdio: 'ignore' })
    zipped = true
  } catch {
    console.warn('⚠️ 没找到 zip / PowerShell：已产出目录，可手动压缩后再分发')
  }
}

if (zipped) {
  const zipSha = createHash('sha256').update(readFileSync(zipPath)).digest('hex')
  const size = statSync(zipPath).size
  writeFileSync(`${zipPath}.sha256`, `${zipSha}  ${zipName}\n`, 'utf8')
  writeFileSync(
    join(outDir, 'catalog-entry.json'),
    JSON.stringify(
      {
        id: args.id,
        name: args.name,
        version,
        description: `FFmpeg ${version}（${license}）`,
        license,
        size,
        sha256: zipSha,
        downloadUrl: `https://example.invalid/plugins/${zipName}`,
      },
      null,
      2,
    ) + '\n',
    'utf8',
  )
  console.log(`✅ 分发包：${zipPath}（${(size / 1024 / 1024).toFixed(1)} MB）`)
  console.log(`   sha256：${zipSha}`)
  console.log(`   清单片段：${join(outDir, 'catalog-entry.json')}（记得把 downloadUrl 换成真实地址）`)
}

console.log('\n下一步：用户在「设置 → 视频 → FFmpeg → 导入组件包…」选中解压后的目录即可启用。')
