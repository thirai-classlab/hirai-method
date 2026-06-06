#!/usr/bin/env node
'use strict';

// hirai-method npx CLI — entry point.
// 外部依存ゼロ (Node 標準のみ)。install.sh をラップし、registry version 比較 (check) を行う。
//
// Subcommands:
//   check            — npm registry の最新版とローカル版を比較 (fail-open)
//   install <dir>    — install.sh <dir> を実行 (初回 install)
//   update <dir>     — install.sh --update <dir> を実行 (増分更新)
//   --version / -v   — ローカル version を出力
//   --help / -h      — usage を出力

const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

// ------------------------------------------------------------
// 定数 / package root 解決
// ------------------------------------------------------------
const PACKAGE_ROOT = path.join(__dirname, '..');
// install.sh path: env override 可 (test 用)。default は同梱 install.sh で本番挙動不変。
const INSTALL_SH =
  process.env.HIRAI_METHOD_INSTALL_SH || path.join(PACKAGE_ROOT, 'install.sh');
const PKG_JSON_PATH = path.join(PACKAGE_ROOT, 'package.json');
const REGISTRY_TIMEOUT_MS = 5000;
const DEFAULT_PKG_NAME = '@takuma-hirai/hirai-method';
// registry base: env override 可 (test 用)。default は npm registry で本番挙動不変。
const REGISTRY_BASE =
  process.env.HIRAI_METHOD_REGISTRY_BASE || 'https://registry.npmjs.org';
// check の registry response body のサイズ上限 (DoS / 暴走防止、超過で fail-open)
const MAX_BODY_BYTES = 1024 * 1024;

// install.sh へ透過する flag (allowlist)
const PASSTHROUGH_FLAGS = new Set([
  '--force',
  '--overwrite-all',
  '--no-mcp',
  '--no-docs',
]);

// ------------------------------------------------------------
// package.json 読み出し (require cache により実 I/O は初回のみ)
// ------------------------------------------------------------
function readPkg() {
  try {
    return require(PKG_JSON_PATH);
  } catch (err) {
    return {};
  }
}

function localVersion() {
  const pkg = readPkg();
  return typeof pkg.version === 'string' && pkg.version.length > 0
    ? pkg.version
    : null;
}

function packageName() {
  const pkg = readPkg();
  return typeof pkg.name === 'string' && pkg.name.length > 0
    ? pkg.name
    : DEFAULT_PKG_NAME;
}

// ------------------------------------------------------------
// usage / help
// ------------------------------------------------------------
function usage() {
  const name = packageName();
  return [
    `${name} — Claude Code harness (HIRAI method) distributor`,
    '',
    'Usage:',
    `  npx ${name} check              registry 最新版とローカル版を比較`,
    `  npx ${name} install <dir>      <dir> に harness を新規 install`,
    `  npx ${name} update <dir>       <dir> の harness を増分更新 (install.sh --update)`,
    `  npx ${name} --version          ローカル version を出力`,
    `  npx ${name} --help             この usage を出力`,
    '',
    'Flags (install / update に透過):',
    '  --force          既存 .claude / CLAUDE.md を backup せず上書き',
    '  --overwrite-all  drift した target を SSoT へ強制リセット (settings.local.json のみ温存)',
    '  --no-mcp         .mcp.json を配置しない',
    '  --no-docs        docs templates 配置を skip',
    '',
    'Note: npx 配布は Unix 系 (bash + rsync) 前提です (Windows 非対応)。',
  ].join('\n');
}

function printUsage(stream) {
  (stream || process.stdout).write(usage() + '\n');
}

// ------------------------------------------------------------
// semver 簡易比較 (依存追加禁止のため自前)
// 戻り値: a > b → 1 / a < b → -1 / a == b → 0
// prerelease / build metadata は無視 (major.minor.patch のみ)
// ------------------------------------------------------------
function parseSemver(v) {
  if (typeof v !== 'string') return null;
  const core = v.trim().replace(/^v/, '').split('+')[0].split('-')[0];
  const parts = core.split('.');
  // major.minor.patch を超える segment 数は不正 (例: "1.2.3.4")
  if (parts.length < 1 || parts.length > 3) return null;
  const nums = [];
  for (let i = 0; i < 3; i++) {
    const seg = parts[i];
    // undefined (segment 不足) は 0 補完 ("1.2" → [1,2,0])
    if (seg === undefined) {
      nums.push(0);
      continue;
    }
    // 非空かつ純数字でない segment は不正 (例: "2.x.0" の "x")
    if (!/^\d+$/.test(seg)) return null;
    nums.push(parseInt(seg, 10));
  }
  return nums;
}

function compareSemver(a, b) {
  const pa = parseSemver(a);
  const pb = parseSemver(b);
  if (!pa || !pb) return null;
  for (let i = 0; i < 3; i++) {
    if (pa[i] > pb[i]) return 1;
    if (pa[i] < pb[i]) return -1;
  }
  return 0;
}

// ------------------------------------------------------------
// 環境チェック: bash / rsync
// ------------------------------------------------------------
function hasCommand(cmd) {
  // cmd を script 本体に埋め込まず positional 引数 ($1) で渡し shell 展開を回避
  const r = spawnSync('bash', ['-c', 'command -v "$1"', '--', cmd], {
    stdio: 'ignore',
  });
  return r.status === 0;
}

function ensureUnixToolchain() {
  const missing = [];
  // bash 自体が無いと spawnSync('bash', ...) も失敗するので個別判定
  const bashCheck = spawnSync('bash', ['-c', 'exit 0'], { stdio: 'ignore' });
  if (bashCheck.error || bashCheck.status !== 0) {
    missing.push('bash');
  }
  if (missing.length === 0 && !hasCommand('rsync')) {
    missing.push('rsync');
  }
  if (missing.length > 0) {
    process.stderr.write(
      `[hirai-method] error: 必須コマンドが見つかりません: ${missing.join(', ')}\n` +
        '[hirai-method] npx 配布は Unix 系 (bash + rsync) 前提です。\n' +
        '[hirai-method] macOS: brew install rsync / Debian: apt install rsync\n',
    );
    return false;
  }
  return true;
}

// ------------------------------------------------------------
// check: registry 最新版を fetch して比較
// ------------------------------------------------------------
function fetchLatestVersion(pkgName) {
  return new Promise((resolve) => {
    // scoped name の "/" を %2F に encode
    const encoded = pkgName.replace('/', '%2F');
    const url = `${REGISTRY_BASE}/${encoded}/latest`;
    // URL scheme で http / https module を選択 (test 用 http server 対応)
    const httpLib = url.startsWith('http://') ? require('http') : require('https');
    let settled = false;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      resolve(result);
    };

    const req = httpLib.get(url, { timeout: REGISTRY_TIMEOUT_MS }, (res) => {
      if (res.statusCode !== 200) {
        res.resume(); // drain
        finish({ ok: false, reason: `HTTP ${res.statusCode}` });
        return;
      }
      let body = '';
      let bytes = 0;
      res.setEncoding('utf8');
      res.on('data', (chunk) => {
        bytes += Buffer.byteLength(chunk, 'utf8');
        if (bytes > MAX_BODY_BYTES) {
          res.destroy();
          finish({ ok: false, reason: `response body too large (> ${MAX_BODY_BYTES} bytes)` });
          return;
        }
        body += chunk;
      });
      res.on('end', () => {
        try {
          const json = JSON.parse(body);
          if (typeof json.version === 'string') {
            finish({ ok: true, version: json.version });
          } else {
            finish({ ok: false, reason: 'no .version in response' });
          }
        } catch (e) {
          finish({ ok: false, reason: `parse error: ${e.message}` });
        }
      });
    });

    req.on('timeout', () => {
      req.destroy();
      finish({ ok: false, reason: `timeout (${REGISTRY_TIMEOUT_MS}ms)` });
    });
    req.on('error', (e) => {
      finish({ ok: false, reason: e.message });
    });
  });
}

async function cmdCheck() {
  const name = packageName();
  const local = localVersion();
  const result = await fetchLatestVersion(name);

  // network fail / timeout / non-200 → fail-open (WARN stderr, exit 0)
  if (!result.ok) {
    process.stderr.write(
      `[hirai-method] WARN: registry 最新版を取得できませんでした (${result.reason})。\n` +
        '[hirai-method] WARN: network 失敗のため check を skip します (fail-open)。\n',
    );
    return 0;
  }

  const latest = result.version;
  if (local === null) {
    process.stdout.write(
      `[hirai-method] registry 最新版: ${latest} (ローカル version 不明、package.json 未設定)\n` +
        `[hirai-method] 最新を取り込むには: npx ${name}@latest update <dir>\n`,
    );
    return 0;
  }

  const cmp = compareSemver(latest, local);
  if (cmp === null) {
    process.stderr.write(
      `[hirai-method] WARN: version 比較不能 (local=${local} / latest=${latest})。fail-open。\n`,
    );
    return 0;
  }

  if (cmp > 0) {
    process.stdout.write(
      `[hirai-method] 新版 ${latest} あり (現 ${local})。\n` +
        `[hirai-method] 更新: npx ${name}@latest update <dir>\n`,
    );
  } else {
    process.stdout.write(`[hirai-method] up to date (${local})\n`);
  }
  return 0;
}

// ------------------------------------------------------------
// install / update: install.sh をラップ
// ------------------------------------------------------------
function runInstall(mode, args) {
  // args = サブコマンド以降 (dir + flags)
  const positional = [];
  const flags = [];
  let endOfOptions = false; // POSIX "--" 以降は全て positional 扱い
  for (const a of args) {
    if (endOfOptions) {
      positional.push(a);
      continue;
    }
    if (a === '--') {
      endOfOptions = true;
      continue;
    }
    if (a.startsWith('-')) {
      if (PASSTHROUGH_FLAGS.has(a)) {
        flags.push(a);
      } else {
        process.stderr.write(`[hirai-method] error: 不明な flag: ${a}\n`);
        return 1;
      }
    } else {
      positional.push(a);
    }
  }

  if (positional.length === 0) {
    process.stderr.write(
      `[hirai-method] error: ${mode} には対象 dir の指定が必須です。\n` +
        `[hirai-method] 例: npx ${packageName()} ${mode} ./my-project\n`,
    );
    return 1;
  }
  if (positional.length > 1) {
    process.stderr.write(
      `[hirai-method] error: dir は 1 つだけ指定してください: ${positional.join(' ')}\n`,
    );
    return 1;
  }

  if (!ensureUnixToolchain()) {
    return 1;
  }

  if (!fs.existsSync(INSTALL_SH)) {
    process.stderr.write(
      `[hirai-method] error: install.sh が見つかりません (${INSTALL_SH})。package 同梱不備の可能性があります。\n`,
    );
    return 1;
  }

  const dir = positional[0];
  // mode=install → install.sh <dir> [flags] / mode=update → install.sh --update <dir> [flags]
  const shArgs =
    mode === 'update'
      ? [INSTALL_SH, '--update', dir, ...flags]
      : [INSTALL_SH, dir, ...flags];

  const r = spawnSync('bash', shArgs, { stdio: 'inherit' });
  if (r.error) {
    process.stderr.write(
      `[hirai-method] error: install.sh の起動に失敗しました: ${r.error.message}\n`,
    );
    return 1;
  }
  // exit code を透過 (null = signal 終了は 1 扱い)
  return typeof r.status === 'number' ? r.status : 1;
}

// ------------------------------------------------------------
// main
// ------------------------------------------------------------
async function main() {
  const argv = process.argv.slice(2);
  const first = argv[0];

  // version / help は最優先
  if (first === '--version' || first === '-v') {
    const local = localVersion();
    if (local === null) {
      process.stderr.write(
        '[hirai-method] error: version が package.json に設定されていません。\n',
      );
      return 1;
    }
    process.stdout.write(local + '\n');
    return 0;
  }

  if (first === '--help' || first === '-h') {
    printUsage(process.stdout);
    return 0;
  }

  if (first === undefined) {
    // 引数なし → usage + exit 1 ではなく exit 0 (help 相当, 引数なしは案内表示)
    printUsage(process.stdout);
    return 0;
  }

  switch (first) {
    case 'check':
      return cmdCheck();
    case 'install':
      return runInstall('install', argv.slice(1));
    case 'update':
      return runInstall('update', argv.slice(1));
    default:
      process.stderr.write(`[hirai-method] error: 不明なサブコマンド: ${first}\n\n`);
      printUsage(process.stderr);
      return 1;
  }
}

// CLI 実行は require.main ガード内のみ。require 時 (test) は実行されず export のみ提供。
if (require.main === module) {
  main()
    .then((code) => {
      process.exitCode = code;
    })
    .catch((err) => {
      process.stderr.write(`[hirai-method] fatal: ${err && err.stack ? err.stack : err}\n`);
      process.exitCode = 1;
    });
}

module.exports = { parseSemver, compareSemver };
