# Tests

Provision スクリプトの冪等性・shellcheck 適合を検証する bats テストスイート。

## Prerequisites

- [bats-core](https://github.com/bats-core/bats-core) — `mise install` で導入
- [shellcheck](https://www.shellcheck.net/) — `mise install` で導入
- bats-support / bats-assert — 下記セットアップ手順で取得

## Setup

### bats-support / bats-assert のセットアップ

```bash
bash tests/helpers/setup-bats-libs.sh
```

`tests/bats/test_helper/bats-support` と `tests/bats/test_helper/bats-assert` を clone する。
CI では毎回このスクリプトを実行すること。

## Running tests

```bash
# 全テスト実行
bats tests/bats/

# 特定ファイル
bats tests/bats/provision-system.bats
```

## Test structure

```
tests/
  bats/
    provision-system.bats    # system layer 冪等性・shebang・shellcheck
    test_helper/             # bats-support / bats-assert (setup スクリプトで clone)
  helpers/
    common.bash              # 共通ロード・setup/teardown
    setup-bats-libs.sh       # bats ライブラリ取得スクリプト
```

## What is tested

| Test                                                    | Description                                    |
| ------------------------------------------------------- | ---------------------------------------------- |
| system scripts have valid shebang                       | 全 system/*.sh が `#!/usr/bin/env bash` を持つ |
| system scripts are executable                           | 全 system/*.sh が実行可能                      |
| system scripts pass shellcheck                          | shellcheck エラーゼロ                          |
| 10-apt-base runs idempotently with DRY_RUN              | DRY_RUN=1 で 2 回連続 exit 0                   |
| 60-wsl-conf skips wsl.conf when DEVTOOL_ENV is not wsl2 | DEVTOOL_ENV=vm で wsl.conf スキップ            |
