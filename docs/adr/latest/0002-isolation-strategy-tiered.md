# 0002. 隔離戦略は段階制 (devcontainer=日常, VM=自律エージェント)

- Status: Accepted
- Date: 2026-07-19
- Deciders: naa0yama

## Context

Claude Code auto mode (`--dangerously-skip-permissions`) の公式推奨は
egress 制限付きコンテナ (init-firewall.sh 相当) である。ただし公式ドキュメントが
明言する通り、コンテナ内の `~/.claude` 認証情報を含む「持ち込んだ秘密」の
持ち出しはコンテナでは防げない。

devcontainer (mount 制御) は「エージェントの過失によるホスト FS 破壊」に有効だが、
長時間・高自律のエージェント実行に対してはネットワーク境界が弱い。

## Decision

隔離戦略を以下の2段階に分ける:

1. **日常作業**: devcontainer (現行運用を変更しない)
2. **自律エージェント (長時間・高自律)**: PVE 上の使い捨て agent VM

agent VM のネットワークポリシーは PVE ファイアウォール (vNIC 単位、
ゲスト内 root でも無効化不可) で強制する。カーネル境界が必要なため LXC ではなく VM。

auto mode 用 devcontainer プロファイルを別途定義する:
egress allowlist、credential 分離 (スコープを絞った token / deploy key)、
docker.sock 非マウント (ソケットがあると任意ホストパスをマウントしたコンテナを
起こせるため mount 制御が無効化される)。

## Consequences

- agent VM 用の PVE VM 管理フローが追加で必要になる
- PVE ファイアウォールの設定・維持コストが発生する
- 日常 devcontainer の運用は変わらない

## Alternatives Considered

**devcontainer 単一層での全処理**
credential 持ち出し防止ができない。長時間エージェントの egress 制御も弱い。

**LXC での agent 隔離**
カーネル共有のため、カーネルレベルの隔離が必要な用途には不十分。

## History

- 2026-07-19: initial version
