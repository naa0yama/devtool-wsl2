# 0004. 固定ユーザー焼き込み方式 (uid:1100 gid:1100)

- Status: Accepted
- Date: 2026-07-19
- Deciders: naa0yama

## Context

qcow2 golden image においてユーザー環境をどう扱うかを決定する必要がある。

候補:

1. **固定ユーザー焼き込み方式**: uid:1100, gid:1100 のユーザーを system 層で焼き込む
2. **遅延実行方式**: mise バイナリのみ system 層に配置し、`mise install` は初回ログイン時に実行

現行 Dockerfile は `DEFAULT_UID=1100 DEFAULT_GID=1100` を ARG 化しており、
provision スクリプトへ最小コストで移植可能である。

devcontainer の `~/.claude` マウントは数値 UID/GID の一致が必要であり、
uid:1100 の維持が要件となっている。

## Decision

固定ユーザー焼き込み方式を採用する。

- uid:1100, gid:1100 のユーザーを system 層 (`50-user.sh`) で作成
- cloud-init は username 変更 / SSH 鍵注入のみ担当
  (`users:` に `no-create-home: true` + `uid: 1100` を指定して整合)
- mise install 済みの状態でイメージを配布するため、初回ログインが速い

## Consequences

- 現行 Dockerfile 構造との距離が近く、移植コストが低い
- devcontainer UID/GID 整合要件 (uid:1100) を維持可能
- 初回ログインが速い (mise install 済み)
- cloud-init でのユーザー名変更が必要 (PVE 利用者は cloud-init 設定必須)

## Alternatives Considered

**遅延実行方式**
cloud-init 標準流儀 (ユーザーは初回起動時に生成) に沿うが、初回ログインが重く、
現行 Dockerfile 構造との距離が遠い。

## History

- 2026-07-19: initial version
