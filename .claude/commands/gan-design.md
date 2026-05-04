---
description: GAN harness Planner phase — turn a one-line prompt into a full product specification with features, sprints, and evaluation criteria.
---

# /gan-design

GAN-Style Harness の **Planner** フェーズ。1 行プロンプトを 16 機能・複数 Sprint 構成の本格仕様書に展開する。

## 使い方

```
/gan-design <one-line prompt>
```

例:
```
/gan-design 「契約進捗を Slack で確認できる社内 Bot」
```

## 動作

1. プロンプトを Opus に投げる（Planner agent）
2. 以下の構造で `.gan-sessions/<timestamp>/spec.md` を生成:

```markdown
# Product Spec: <name>

## Vision
<1段落>

## Target Users / Personas
<list>

## Features (16+)
### Feature 1: <name>
- User Story: As a ___, I want ___ so that ___
- Acceptance Criteria:
  - [ ] ...

### Feature 2: ...

## Sprints
### Sprint 1: Foundation
Features: 1, 2, 3
Goal: ...

### Sprint 2: Core Flow
...

## Evaluation Criteria
### Design Quality (weight 0.30)
- ...
### Originality (weight 0.20)
- ...
### Craft (weight 0.30)
- ...
### Functionality (weight 0.20)
- ...

## Non-Goals
<list>

## Tech Stack Constraints
<list>
```

3. 生成された spec.md をユーザーに提示・レビュー依頼

## 次のステップ

ユーザーが spec を承認したら:

```
/gan-build .gan-sessions/<timestamp>/spec.md
```

で Generator/Evaluator ループを開始。

## 関連

- skill: `.claude/skills/gan-style-harness/SKILL.md`
- `/gan-build`
