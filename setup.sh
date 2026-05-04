#!/usr/bin/env bash
# 平井メソッド (hirai-method) — install harness into a project
#
# Usage: ./setup.sh <target-project-dir>
#
# 上書きを避けるため既存 .claude / CLAUDE.md は .bak に退避する。

set -euo pipefail

TARGET="${1:-}"
if [[ -z "${TARGET}" ]]; then
  echo "usage: ./setup.sh <target-project-dir>" >&2
  exit 64
fi

if [[ ! -d "${TARGET}" ]]; then
  echo "[setup] error: '${TARGET}' is not a directory" >&2
  exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 既存 .claude を退避
if [[ -d "${TARGET}/.claude" ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  echo "[setup] existing .claude detected → backing up to .claude.bak.${STAMP}"
  mv "${TARGET}/.claude" "${TARGET}/.claude.bak.${STAMP}"
fi

# 既存 CLAUDE.md を退避
if [[ -f "${TARGET}/CLAUDE.md" ]]; then
  STAMP="$(date +%Y%m%d-%H%M%S)"
  echo "[setup] existing CLAUDE.md detected → backing up to CLAUDE.md.bak.${STAMP}"
  mv "${TARGET}/CLAUDE.md" "${TARGET}/CLAUDE.md.bak.${STAMP}"
fi

# .claude をコピー
echo "[setup] copying .claude/ → ${TARGET}/.claude/"
cp -R "${SCRIPT_DIR}/.claude" "${TARGET}/.claude"

# CLAUDE.md テンプレートをコピー（テンプレートとして残す）
echo "[setup] copying CLAUDE.md → ${TARGET}/CLAUDE.md (edit placeholders)"
cp "${SCRIPT_DIR}/CLAUDE.md" "${TARGET}/CLAUDE.md"

# 実行権限を hook に付与
echo "[setup] chmod +x .claude/hooks/*.sh .claude/hooks/lib/*.sh"
find "${TARGET}/.claude/hooks" -type f -name '*.sh' -exec chmod +x {} +
find "${TARGET}/.claude/scripts" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null || true

echo ""
echo "[setup] DONE."
echo ""
echo "Next steps:"
echo "  1. Edit ${TARGET}/.claude/harness-config.yml  (protected_paths / task_dir / ...)"
echo "  2. Edit ${TARGET}/.claude/bash-whitelist.txt  (your package manager / CLI tools)"
echo "  3. Edit ${TARGET}/CLAUDE.md                   (replace <...> placeholders)"
echo "  4. Read docs/PORTABILITY.md and docs/SELF_IMPROVEMENT.md"
