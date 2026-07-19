# 0001. NixOS へは移行しない (当面)

- Status: Accepted
- Date: 2026-07-19
- Deciders: naa0yama

## Context

devtool-wsl2 をマルチターゲット化する検討において、ホスト環境の宣言的管理として
NixOS への移行が候補として挙がった。

ホスト必須ツール (age, awscli, bats, chezmoi, devcontainer-cli, dprint, ghq,
gh, gitleaks, lazygit, node, pnpm, ripgrep, shellcheck, starship, tmux, uv,
yazi 等) はほぼ全て nixpkgs 収録済みであり、技術的には移行可能である。
自作ツール (graft, chezmage) も各リポジトリへの flake.nix 追加で対応可能。

## Decision

NixOS への移行は行わない (当面)。Ubuntu ベース構成をマルチターゲット化する方針とする。

将来の全振り時は、本設計の「層1 (プロビジョニング)」の差し替えのみで済む退路を確保する。

## Consequences

- Ubuntu ベースの provision スクリプト群が Single Source of Truth になる
- NixOS 固有の宣言的管理の恩恵 (rollback, reproducibility) は得られない
- 将来の NixOS 移行の選択肢は閉じない

## Alternatives Considered

**NixOS 全面移行**
devcontainer 隔離モデルを維持する限り、mise は devcontainer 内で現状維持となり、
NixOS 化の追加価値は「ホストの宣言的管理」に限定される。

**mise をホストに残したまま NixOS 化する中間案**
nix-ld によるライブラリキュレーションという恒久コストを伴い、労力対効果が最も悪い。

## History

- 2026-07-19: initial version
