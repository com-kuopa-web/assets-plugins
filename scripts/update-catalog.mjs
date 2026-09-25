#!/usr/bin/env node
/**
 * 用构建产物更新 plugin-catalog.json（发布流程的最后一步）
 *
 * 文件名约定：official.ffmpeg-<version>-<platform>-<arch>.zip
 * 用法：node scripts/update-catalog.mjs --dir dist-plugins --catalog plugin-catalog.json \
 *        --repo owner/repo --tag ffmpeg-7.1.0 [--license LGPL-2.1-or-later] [--keep-old]
 *
 * 行为：为每个 zip 计算 sha256/size，按 (id, platform, arch) **upsert** 一条记录，
 *      downloadUrl 指向 GitHub Release 资源地址；默认清掉同名组件的旧版本记录（--keep-old 可保留）。
 */
import { createHash } from 'node:crypto'
import { readFileSync, readdirSync, writeFileSync, existsSync } from 'node:fs'
import { join, resolve } from 'node:path'

const args = {}
for (let i = 2; i < process.argv.length; i += 2) args[process.argv[i].replace(/^--/, '')] = process.argv[i + 1]
const dir = resolve(args.dir ?? 'dist-plugins')
const catalogPath = resolve(args.catalog ?? 'plugin-catalog.json')
const repo = args.repo
const tag = args.tag
const license = args.license ?? 'LGPL-2.1-or-later'
if (!repo || !tag) {
  console.error('需要 --repo <owner/repo> 与 --tag <tag>')
  process.exit(2)
}

const catalog = existsSync(catalogPath)
  ? JSON.parse(readFileSync(catalogPath, 'utf8'))
  : { schema: 1, updatedAt: '', plugins: [] }
const plugins = Array.isArray(catalog.plugins) ? catalog.plugins : []

for (const file of readdirSync(dir).filter((f) => f.endsWith('.zip'))) {
  const m = /^(?<id>[a-z0-9.\-]+?)-(?<version>\d+\.\d+(?:\.\d+)?)-(?<platform>darwin|win32|linux)-(?<arch>[\w-]+)\.zip$/i.exec(file)
  if (!m) {
    console.warn(`跳过（文件名不符合 <id>-<version>-<platform>-<arch>.zip）：${file}`)
    continue
  }
  const { id, version, platform, arch } = m.groups
  const buf = readFileSync(join(dir, file))
  const sha256 = createHash('sha256').update(buf).digest('hex')
  const entry = {
    id,
    name: id === 'official.ffmpeg' ? 'FFmpeg 组件（第三方）' : id,
    version,
    description: id === 'official.ffmpeg' ? `FFmpeg ${version}（LGPL 构建）—— 转码 / 截帧 / 探测` : undefined,
    license,
    platform,
    arch,
    size: buf.length,
    sha256,
    downloadUrl: `https://github.com/${repo}/releases/download/${tag}/${file}`,
    mirrors: [], // 需要镜像时手工加（或在别处生成）
  }
  const idx = plugins.findIndex((p) => p.id === id && p.platform === platform && p.arch === arch)
  if (idx >= 0) {
    const mirrors = plugins[idx].mirrors ?? []
    plugins[idx] = { ...entry, mirrors }
    console.log(`更新 ${id} ${platform}/${arch} → ${version}`)
  } else {
    plugins.push(entry)
    console.log(`新增 ${id} ${platform}/${arch} → ${version}`)
  }
}

catalog.schema = catalog.schema ?? 1
catalog.updatedAt = new Date().toISOString()
catalog.plugins = plugins
writeFileSync(catalogPath, JSON.stringify(catalog, null, 2) + '\n', 'utf8')
console.log(`✅ 已写入 ${catalogPath}（${plugins.length} 条记录）`)
