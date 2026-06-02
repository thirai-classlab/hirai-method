# `.claude/archive/` — 退避済 action space

> **作成日**: 2026-06-02 / **起源**: task-72 Step 3 (action space 削減、user 選択分の退避)

## これは何か

Claude Code が起動時に discover する action space (`.claude/agents/**/*.md` の subagent と `.claude/skills/<name>/SKILL.md` の skill) のうち、**本 repo (hirai-method) では日常的に使わない** ものをここへ退避した。

- **削除ではなく移動**。git 履歴は保持され、いつでも復帰できる。
- `.claude/archive/` 配下は Claude Code の **discover 対象外** (`.claude/agents/` 直下と `.claude/skills/<name>/SKILL.md` のみが discover される)。よってここに入れた時点で action space から外れる。
- `.claude/archive/` は `install.sh` / rsync で consuming repo へ**配布される**が、discover されないため action space を膨らませない (`.claude/rules-details/` と同型の「配布されるが startup load されない」設計)。

## 退避一覧

### agent category (4 / whole dir、計 68 agent)

| category | agent 数 |
|---|---|
| `02-language-specialists` | 30 |
| `05-data-ai` | 13 |
| `07-specialized-domains` | 13 |
| `08-business-product` | 12 |

> **残した category (6)**: `01-core-development` / `03-infrastructure` / `04-quality-security` / `06-developer-experience` / `09-meta-orchestration` / `10-research-analysis` は `.claude/agents/` に維持。keep-9 agent (qa-expert / test-automator / code-reviewer / refactoring-specialist / architect-reviewer / ui-designer / api-designer / security-auditor / debugger) も維持。

### skill (11)

`document-docx` / `document-pdf` / `document-pptx` / `document-xlsx` / `image-enhancer` / `slack-gif-creator` / `video-downloader` / `competitive-ads-extractor` / `twitter-algorithm-optimizer` / `developer-growth-analysis` / `meeting-insights-analyzer`

## 復帰コマンド

退避を取り消して discover 対象に戻す (git 履歴保持):

```bash
# agent category の復帰例
git mv .claude/archive/agents/02-language-specialists .claude/agents/
git mv .claude/archive/agents/05-data-ai            .claude/agents/
git mv .claude/archive/agents/07-specialized-domains .claude/agents/
git mv .claude/archive/agents/08-business-product   .claude/agents/

# skill の復帰例
git mv .claude/archive/skills/document-docx .claude/skills/
git mv .claude/archive/skills/image-enhancer .claude/skills/
# …他 skill も同様
```

復帰後は `bash .claude/tests/action-space-count-smoke.sh` の退避 assert が落ちるので、不要になった場合は smoke 側も更新すること。
