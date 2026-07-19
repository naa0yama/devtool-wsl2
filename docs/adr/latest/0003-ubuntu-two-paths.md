# 0003. Ubuntu 向けは 2 経路 (golden image + bootstrap)

- Status: Accepted
- Date: 2026-07-19
- Deciders: naa0yama

## Context

PVE VM 上に devtool-wsl2 相当の環境を再現する手段として、以下の選択肢を検討した:

- 経路 A: 構築済み qcow2 golden image を配布し PVE に import する
- 経路 B: まっさらな Ubuntu に bootstrap.sh を流して構築する
- 単一経路: どちらかのみ提供する

## Decision

2 経路を並行して提供する。ただし**経路 A は経路 B の実行結果のキャッシュ**として定義し、
実装を共有することで乖離を原理的に防ぐ。

- 経路 A: Ubuntu cloud image + bootstrap 実行 + finalize.sh → qcow2
- 経路 B: bootstrap.sh 単体での直接実行

検証は経路 B の CI テスト 1 本に集約し、経路 A は finalize 部分のみ追加検証する。

## Consequences

- 「構築済みを使いたい」「スクリプトだけ流用したい」の両ニーズに応えられる
- bootstrap.sh が Single Source of Truth となり、Dockerfile との3消費者構成になる
- finalize.sh の管理コストが追加される

## Alternatives Considered

**経路 A (golden image) のみ**
スクリプト単体での流用ができない。CI での検証コストが高い (KVM 必須)。

**経路 B (bootstrap) のみ**
初回構築時間が長い。ネットワーク環境に依存する。

## History

- 2026-07-19: initial version
