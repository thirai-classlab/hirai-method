---
name: create
description: "コマンド/スキル/サブエージェント/Hook作成 - 対話形式で新しいコンポーネントを生成"
category: meta
complexity: enhanced
model: sonnet
mcp-servers: []
---

# /create - コンポーネント作成コマンド

## 概要

コマンド、スキル、サブエージェント、Hookを対話形式で作成するメタコマンド。
ヒアリング → 構成提案 → 仕様確認 → ファイル生成 → 一覧更新 の流れで実行します。

## 使用方法

```bash
# タイプを指定して作成
/create command     # 新しいワークフローコマンドを作成
/create skill       # 新しいスキルを作成
/create subagent    # 新しいサブエージェントを作成
/create hook        # 新しいHookを作成

# 対話形式でタイプを選択
/create
```

## 作成可能なタイプ

| タイプ | 配置先 | 説明 |
|--------|--------|------|
| `command` | `.claude/commands/` | ワークフローコマンド（/requirement, /design等） |
| `skill` | `.claude/commands/` | ヘルパースキル（/context-fetch, /notification等） |
| `subagent` | `.claude/agents/` | 特化型サブエージェント |
| `hook` | `.claude/hooks/` | Pre/Post/Notification Hook |

## 実行フロー

```
/create [type]
  ↓
Phase 1: タイプ選択
  ↓
Phase 2: ヒアリング
  ↓
Phase 3: 構成提案
  ↓
Phase 4: 依存コンポーネント作成  ← コマンド作成時のみ
  ↓
Phase 5: 仕様確認
  ↓
Phase 6: ファイル生成（コマンド + 依存コンポーネント一括）
  ↓
Phase 7: 一覧更新
```

### Phase 1: タイプ選択
タイプが指定されていない場合、以下から選択を促す：
- command: ワークフローを定義するコマンド
- skill: 他のコマンドから呼び出されるヘルパー
- subagent: 特定ドメインに特化したエージェント
- hook: ツール実行前後に自動実行される処理

### Phase 2: ヒアリング

#### 共通項目
1. **名前**: コマンド/スキル/エージェント/Hook名（英小文字、ハイフン区切り）
2. **説明**: 日本語での簡潔な説明
3. **目的・ユースケース**: 何を解決するか、どんな場面で使うか

#### コマンド/スキル固有
4. **カテゴリ**: workflow / skill / utility
5. **複雑度**: basic / enhanced
6. **MCP連携**: asana / slack / github / salesforce / context7 / なし
7. **入力**: 必要なパラメータ
8. **出力**: 生成されるファイルや結果

#### サブエージェント固有
4. **専門領域**: どの分野に特化するか
5. **使用ツール**: どのツールを主に使用するか
6. **呼び出し元**: どのコマンドから呼ばれるか

#### Hook固有
4. **Hookタイプ**: PreToolUse / PostToolUse / Notification / Stop
5. **トリガー条件**: どのツール/イベントで発火するか
6. **実行内容**: 何を行うか

### Phase 3: 構成提案

ヒアリング結果に基づき、以下を提案：
- ファイル構造
- 関連する既存コマンド/スキルとの連携
- 推奨するMCP連携
- テンプレート選択
- **必要な依存コンポーネント（新規作成が必要なサブエージェント/スキル）**

```markdown
## 構成提案

### ファイル構造
.claude/
├── commands/
│   └── {command-name}.md
├── agents/
│   └── {subagent-name}.md      # 新規作成
└── commands/
    └── {skill-name}.md         # 新規作成

### 連携コンポーネント
#### 既存（再利用）
- /context-fetch: 情報収集に利用
- /notification: 通知送信に利用

#### 新規作成が必要
- subagent: {subagent-name} - {説明}
- skill: {skill-name} - {説明}

### MCP連携
- asana: タスク管理
- slack: 通知
```

### Phase 4: 依存コンポーネント作成（コマンド作成時のみ）

コマンド作成時に、依存するサブエージェント/スキルの作成を行う。

#### 4-1: 依存コンポーネント確認
```
このコマンドで使用する新規コンポーネントを作成しますか？

提案された新規コンポーネント:
1. [subagent] salesforce-validator - Salesforceメタデータの検証を行う
2. [skill] coverage-check - テストカバレッジをチェックする

選択肢:
- すべて作成する
- 選択して作成する（番号指定）
- スキップ（既存のみ使用）
```

#### 4-2: サブエージェント作成フロー
新規サブエージェントが必要な場合、以下をヒアリング：
1. **専門領域**: どの分野に特化するか
2. **責務**: 何を担当するか
3. **使用ツール**: どのツールを主に使用するか
4. **入出力**: 何を受け取り、何を返すか

#### 4-3: スキル作成フロー
新規スキルが必要な場合、以下をヒアリング：
1. **機能**: 何をするスキルか
2. **入力**: 必要なパラメータ
3. **出力**: 返却する結果
4. **MCP連携**: 使用するMCPサーバー

#### 4-4: Hook作成フロー（必要な場合）
コマンド実行前後にHookが必要な場合、以下をヒアリング：
1. **Hookタイプ**: Pre/Post/Notification
2. **トリガー**: いつ発火するか
3. **実行内容**: 何を行うか

### Phase 5: 仕様確認

提案内容（コマンド + 依存コンポーネント）をユーザーに確認し、必要に応じて修正。

```markdown
## 作成予定ファイル一覧

| タイプ | 名前 | 配置先 |
|--------|------|--------|
| command | deploy-check | .claude/commands/deploy-check.md |
| subagent | salesforce-validator | .claude/agents/salesforce-validator.md |
| skill | coverage-check | .claude/commands/coverage-check.md |

この内容でよろしいですか？
```

### Phase 6: ファイル生成

確定した仕様に基づきファイルを生成。

#### コマンド/スキル テンプレート

```markdown
---
name: {name}
description: "{description}"
category: {category}
complexity: {complexity}
mcp-servers: [{mcp-servers}]
---

# /{name} - {title}

## 概要

{overview}

## トリガー

- {trigger1}
- {trigger2}

## 使用方法

\`\`\`
/{name} [引数]
\`\`\`

## 実行フロー

### Step 1: {step1_title}
{step1_content}

### Step 2: {step2_title}
{step2_content}

## 出力物

{outputs}

## MCP連携

| MCP | 用途 |
|-----|------|
| {mcp1} | {usage1} |

## 注意事項

- {note1}
- {note2}

## 次のステップ

{next_steps}
```

#### サブエージェント テンプレート

```markdown
---
name: {name}
description: "{description}"
type: subagent
domain: {domain}
tools: [{tools}]
---

# {name} - サブエージェント

## 専門領域

{domain_description}

## 責務

- {responsibility1}
- {responsibility2}

## 使用ツール

| ツール | 用途 |
|--------|------|
| {tool1} | {usage1} |

## 呼び出しパターン

\`\`\`
PM Agent → {name} → [処理] → 結果返却
\`\`\`

## 入出力

### 入力
{inputs}

### 出力
{outputs}

## 制約事項

- {constraint1}
- {constraint2}
```

#### Hook テンプレート

```markdown
---
name: {name}
description: "{description}"
type: hook
hook_type: {PreToolUse|PostToolUse|Notification|Stop}
triggers: [{triggers}]
---

# {name} - Hook

## Hookタイプ

{hook_type}: {hook_type_description}

## トリガー条件

- ツール: {tool_name}
- 条件: {condition}

## 実行内容

\`\`\`bash
{script_content}
\`\`\`

## 設定例

`.claude/settings.json` への追加:

\`\`\`json
{
  "hooks": {
    "{hook_type}": [
      {
        "matcher": "{matcher}",
        "hooks": ["{hook_command}"]
      }
    ]
  }
}
\`\`\`

## 注意事項

- {note1}
- {note2}
```

### Phase 7: 一覧更新

以下のファイルを自動更新：
- `doc/manual/COMMAND-REFERENCE.md` - コマンド一覧に追加（コマンド + 依存コンポーネント全て）

## 出力物

```
.claude/
├── commands/
│   ├── {command-name}.md   # メインコマンド
│   └── {skill-name}.md     # 依存スキル（新規作成時）
├── agents/
│   └── {subagent-name}.md  # 依存サブエージェント（新規作成時）
└── hooks/
    └── {hook-name}.md      # 依存Hook（新規作成時）

doc/manual/
└── COMMAND-REFERENCE.md    # 一覧更新（全コンポーネント）
```

## 使用例

### 例1: 新しいワークフローコマンドを作成（依存コンポーネント含む）

```
User: /create command

AI: 新しいコマンドを作成します。以下の項目を教えてください。

    1. コマンド名は何にしますか？
User: deploy-check

AI: 2. このコマンドの説明を教えてください。
User: デプロイ前の検証を自動実行する

AI: 3. 目的・ユースケースを教えてください。
User: PRマージ前にApexテスト、静的解析、カバレッジチェックを一括実行したい

AI: 4. MCP連携は必要ですか？
User: github, salesforce

AI: 構成を提案します...

## 構成提案

### ファイル構造
.claude/
├── commands/
│   └── deploy-check.md
├── agents/
│   └── salesforce-validator.md    # 新規作成提案
└── commands/
    └── coverage-check.md          # 新規作成提案

### 連携コンポーネント
#### 既存（再利用）
- /notification: 結果通知に利用

#### 新規作成が必要
- subagent: salesforce-validator - Salesforceメタデータの検証を行う
- skill: coverage-check - テストカバレッジをチェックする

AI: このコマンドで使用する新規コンポーネントを作成しますか？

    提案された新規コンポーネント:
    1. [subagent] salesforce-validator - Salesforceメタデータの検証
    2. [skill] coverage-check - テストカバレッジのチェック

    選択肢:
    - すべて作成する
    - 選択して作成する（番号指定）
    - スキップ（既存のみ使用）

User: すべて作成する

AI: サブエージェント「salesforce-validator」について教えてください。
    1. 主な責務は何ですか？
User: Apexクラスのコンパイル検証、メタデータ整合性チェック

AI: 2. 使用するツールは？
User: salesforce MCP

AI: スキル「coverage-check」について教えてください。
    1. どのような出力を返しますか？
User: カバレッジ率、未カバー行のリスト

AI: 作成予定ファイル一覧:

| タイプ | 名前 | 配置先 |
|--------|------|--------|
| command | deploy-check | .claude/commands/deploy-check.md |
| subagent | salesforce-validator | .claude/agents/salesforce-validator.md |
| skill | coverage-check | .claude/commands/coverage-check.md |

この内容でよろしいですか？
User: はい

AI: ファイルを生成しました。
    - .claude/commands/deploy-check.md
    - .claude/agents/salesforce-validator.md
    - .claude/commands/coverage-check.md
    - doc/manual/COMMAND-REFERENCE.md を更新
```

### 例2: 新しいHookを作成

```
User: /create hook

AI: 新しいHookを作成します。以下の項目を教えてください。

    1. Hook名は何にしますか？
User: commit-message-validator

AI: 2. Hookタイプを選択してください。
    - PreToolUse: ツール実行前
    - PostToolUse: ツール実行後
    - Notification: 通知時
    - Stop: 停止時
User: PreToolUse

AI: 3. どのツールで発火しますか？
User: Bash(git commit*)

AI: 4. 実行内容を教えてください。
User: コミットメッセージがConventional Commits形式か検証する

AI: 構成を提案します...
[構成提案を表示]

AI: この内容でよろしいですか？
User: はい

AI: ファイルを生成しました。
    - .claude/hooks/commit-message-validator.md
    - .claude/settings.json を更新
    - doc/manual/COMMAND-REFERENCE.md を更新
```

## 関連コマンド

- `/requirement` - 要件定義フェーズ
- `/design` - 設計フェーズ
- `/build` - 構築フェーズ

## 注意事項

- コマンド名は英小文字とハイフンのみ使用可能
- 既存のコマンド名と重複しないよう注意
- Hook作成時は `.claude/settings.json` も更新される
- 作成後は必ず動作確認を行う

## 次のステップ

コマンド作成後:
1. 動作確認
2. 必要に応じてテスト作成
3. チームへの共有