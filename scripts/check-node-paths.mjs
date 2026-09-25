#!/usr/bin/env node
/**
 * Node 脚本体检：**禁止 `new URL(import.meta.url).pathname`**
 *
 * 为什么：`URL.pathname` 返回的是 **URL 语义的路径**，不是文件系统路径。
 * 在 Windows 上它长这样（注意前导斜杠 + 盘符）：
 *
 *     new URL('file:///D:/a/proj/scripts/x.mjs').pathname   →  '/D:/a/proj/scripts/x.mjs'
 *     path.resolve(path.dirname('/D:/a/proj/scripts'), '..') →  'D:\\D:\\a\\proj'   ← 盘符被补了两次
 *
 * 于是 `mkdirSync('D:\\D:\\a\\…')` 直接 ENOENT：
 *     Error: ENOENT: no such file or directory, mkdir 'D:\D:\a\…\dist-plugins\…'
 *
 * 正确写法（macOS/Linux 上也一样正确）：
 *
 *     import { fileURLToPath } from 'node:url'
 *     const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
 *
 * `fileURLToPath()` 是 URL→文件路径 的**唯一规范转换**：处理 Windows 盘符、`%20` 等转义、UNC 路径。
 *
 * 用法：node scripts/check-node-paths.mjs [目录…]（默认扫 scripts/ 与仓库根下的 *.mjs/*.cjs/*.js）
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, resolve } from 'node:path'

const roots = process.argv.slice(2).length ? process.argv.slice(2).map((p) => resolve(p)) : [resolve('scripts'), resolve('.')]
const SKIP_DIRS = new Set(['node_modules', '.git', '.build', 'dist-plugins', 'dist', 'out'])

const files = []
const walk = (dir, depth = 0) => {
  if (depth > 3) return
  let entries
  try {
    entries = readdirSync(dir, { withFileTypes: true })
  } catch {
    return
  }
  for (const e of entries) {
    if (e.isDirectory()) {
      if (!SKIP_DIRS.has(e.name)) walk(join(dir, e.name), depth + 1)
    } else if (/\.(mjs|cjs|js)$/.test(e.name)) {
      files.push(join(dir, e.name))
    }
  }
}
for (const r of roots) {
  try {
    if (statSync(r).isDirectory()) walk(r)
    else files.push(r)
  } catch {
    /* 不存在就跳过 */
  }
}

const BAD = /new URL\(\s*import\.meta\.url\s*\)\.pathname/
let bad = 0
const SELF = 'check-node-paths.mjs'
for (const f of new Set(files)) {
  if (f.endsWith(SELF)) continue   // 本文件里必然写着这条规则的说明，跳过自身
  readFileSync(f, 'utf8')
    .split('\n')
    .forEach((rawLine, i) => {
      // 只检查“像代码”的行：去掉 // 注释，跳过 JSDoc 块内以 * 开头的行
      const trimmed = rawLine.trim()
      if (trimmed.startsWith('*') || trimmed.startsWith('/*') || trimmed.startsWith('//')) return
      const line = rawLine.replace(/\/\/.*$/, '')
      if (!BAD.test(line)) return
      bad++
      console.error(`${f}:${i + 1}  用了 new URL(import.meta.url).pathname → 改成 fileURLToPath(import.meta.url)`)
      console.error(`    ${line.trim().slice(0, 110)}`)
    })
}

if (bad) {
  console.error(`\n✗ [check-node-paths] 发现 ${bad} 处：URL 语义路径不是文件系统路径，Windows 上会得到 \`D:\\D:\\a\\…\``)
  process.exit(1)
}
console.log(`[check-node-paths] 体检通过（${new Set(files).size} 个脚本）✓`)
