#!/usr/bin/env node
/**
 * Shell 脚本体检：**变量展开后紧跟非 ASCII 字符**会导致 bash 在 UTF-8 locale 下把它吃进变量名。
 *
 * 真实的坑（2026-09-25 实测）：
 *   echo "自建 $VERSION（平台 $PLATFORM）"
 *   → bash: build-local.sh: line 39: VERSION（: unbound variable      # 「（」被当成变量名的一部分
 * 但在 LC_ALL=C 下却正常，所以本地不报、别人一跑就挂。
 *
 * 规则：`$VAR` 后面紧跟非 ASCII（中文/全角标点等）→ 必须写成 `${VAR}`（建议再加一个空格）。
 * 用法：node scripts/check-shell-expansions.mjs [目录…]（默认扫 scripts/）
 */
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, resolve } from 'node:path'

const roots = process.argv.slice(2).length ? process.argv.slice(2).map((p) => resolve(p)) : [resolve('scripts')]
const files = []
for (const root of roots) {
  const walk = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name)
      if (e.isDirectory()) walk(p)
      else if (/\.(sh|bash)$/.test(e.name)) files.push(p)
    }
  }
  if (statSync(root).isDirectory()) walk(root)
  else files.push(root)
}

const BAD = /\$([A-Za-z_][A-Za-z0-9_]*)(?=[^\x00-\x7F])/g
let bad = 0
for (const f of files) {
  readFileSync(f, 'utf8')
    .split('\n')
    .forEach((line, i) => {
      for (const m of line.matchAll(BAD)) {
        bad++
        console.error(`${f}:${i + 1}  $${m[1]} 后面紧跟非 ASCII 字符 → 改成 \${${m[1]}}（建议加空格）`)
        console.error(`    ${line.trim().slice(0, 110)}`)
      }
    })
}

if (bad) {
  console.error(`\n✗ [check-shell-expansions] 发现 ${bad} 处：UTF-8 locale 下 bash 会把它当成变量名的一部分（unbound variable）`)
  process.exit(1)
}
console.log(`[check-shell-expansions] 体检通过（${files.length} 个脚本）✓`)
