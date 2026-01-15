# devtool-WSL2

WSL2 の開発環境を自動構築するセット\
以前は、 WSL2 に都度コマンドを打って環境構築していたが似たような環境が複数必要になるため自動化し環境構築にかかる時間を省力化した。

> [!IMPORTANT]
> 2025/05/24 に Backup/Restore を実装した。これにより devtool.ps1 を実行時に `/home/user` 配下を一定の条件で tar で固め `%USERPROFILE%/Documents/WSL2/Backups` に吐き出します。 **一時保管ため非圧縮です** Restore は WSL2 のディストリビューション初回起動時に最新の tar ファイルを利用し展開される。 展開後、 `$HOME/.dwsl2-restore.lock` を作成することで次回以降は実施されません

## Software

| Common software                                                 | Latest software version                                                 |
| :-------------------------------------------------------------- | :---------------------------------------------------------------------- |
| [albertony/npiperelay](https://github.com/albertony/npiperelay) | ![GitHub Tag](https://img.shields.io/github/v/tag/albertony/npiperelay) |
| [BusyJay/gpg-bridge](https://github.com/BusyJay/gpg-bridge)     | ![GitHub Tag](https://img.shields.io/github/v/tag/BusyJay/gpg-bridge)   |
| [Docker Engine](https://github.com/moby/moby)                   | ![GitHub Tag](https://img.shields.io/github/v/tag/moby/moby)            |
| [dprint](https://github.com/dprint/dprint)                      | ![GitHub Tag](https://img.shields.io/github/v/tag/dprint/dprint)        |
| [mise](https://github.com/jdx/mise)                             | ![GitHub Tag](https://img.shields.io/github/v/tag/jdx/mise)             |

| mise                                                 |
| :--------------------------------------------------- |
| [aws-cli](https://github.com/aws/aws-cli/)           |
| [aws-sam-cli](https://github.com/aws/aws-sam-cli)    |
| [claude-code](https://code.claude.com/docs/en/setup) |
| [fzf](https://github.com/junegunn/fzf)               |
| [ghq](https://github.com/x-motemen/ghq)              |
| [lefthook](https://github.com/evilmartians/lefthook) |
| [poetry](https://github.com/python-poetry/poetry)    |
| [rust](https://github.com/rust-lang/rust)            |
| [starship](https://github.com/starship/starship)     |
| [Tmux](https://github.com/tmux/tmux)                 |

| Rust Tools                                          | Latest release                                                          |
| :-------------------------------------------------- | :---------------------------------------------------------------------- |
| [dua-cli](https://github.com/Byron/dua-cli)         | ![GitHub Tag](https://img.shields.io/github/v/tag/Byron/dua-cli)        |
| [ripgrep](https://github.com/BurntSushi/ripgrep)    | ![GitHub Tag](https://img.shields.io/github/v/tag/BurntSushi/ripgrep)   |
| [topgrade](https://github.com/topgrade-rs/topgrade) | ![GitHub Tag](https://img.shields.io/github/v/tag/topgrade-rs/topgrade) |

## ssh-agent,gpg-agent との統合

2026/01/11 の更新から WSL2 の初回起動時に Windows 11 側に `npiperelay.exe`, `gpg-bridge.exe`, `yubikey-tool.ps1` のツールを自動ダウンロードし `%USERPROFILE%/.local/bin` に配置するようになりました。 `yubikey-tool.ps1` は自動起動にも設定され `gpg-agent`, `gpg-bridge` の自動起動、タッチ/PIN入力の通知を実施するタスクトレイアプリケーションです。

これにより WSL2 上でも手軽に GPG 鍵を利用でき、 `gpg-bridge` を使うことで SSH 先でも GPG 署名できるようになりました。

## 使い方

`Windows Terminal` などで PowerShell を開き下記のコマンドを投入すると最新の GitHub Releases から WSL2 イメージを取得し WSL に登録します

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/naa0yama/devtool-wsl2/main/devtool.ps1' -OutFile "$env:TEMP/devtool.ps1"
powershell -ExecutionPolicy Unrestricted "$env:TEMP/devtool.ps1"
```

フラグオプションをいくつか用意しています

- `-skipBackupAndRestore`
  - 既存 default 環境の Backup & Restore をスキップします
- `-Tag`
  - Release Tag を指定してダウンロードする場合に指定します。
- `-skipWSLImport`
  - WSL へ `Import` を実施しません。
  - ダウンロードのみを実施し、スクリプト終了時のダウンロードフォルダークリーンアップ処理も実施しません。
- `-skipWSLDefault`
  - WSL へ `Import` した場合に `wsl --set-default <DistributionName>` の実行をしません

> [!IMPORTANT]
>
> - `-ImportForce`
>   - 同じ tag の WSL イメージが登録されている場合、登録解除(`wsl --unregister`)を実施し強制的に更新します
>     WSL イメージは削除されますので注意してください

Import 結果を確認します\
`dwsl2-<tag>` があれば Import 出来ています。

```powershell
wsl -l -v
```

```powershell
> wsl -l -v
  NAME            STATE           VERSION
* Ubuntu-22.04    Running         2
  dwsl2-8718ff1   Stopped         2
  Ubuntu          Stopped         2
```

> [!TIP]
> このスクリプトを使って展開された WSL2 は展開時に以前の default WSL2 環境でバックアップしたデータから自動で書き戻します。
> この機能をオフにする場合 `%USERPROFILE%/Documents/WSL2` に `.restore-skip` というファイルを配置してください。
> これでリストア処理をスキップします。
>
> ```powershell
> New-Item -Path "$env:USERPROFILE/Documents/WSL2/.restore-skip"
> ```

実際に起動してみます。\
このセクションではデフォルトに設定してないためディストリビューション指定で起動します。\
起動出来ると Bash が起動します。

```powershelll
wsl -d dwsl2-8718ff1
user@dead-desk1:~$
```

### デフォルトに設定する場合

この手順では default に設定していないためディストリビューションを指定して起動する必要があります。\
手間を省くために default に設定すると `wsl` コマンドで起動してくる事になります\
下記の例では `dwsl2-8718ff1` を default に設定します。\
`*` の付いている物が default 起動の WSL です。

```powershell
> wsl -l -v
  NAME            STATE           VERSION
* Ubuntu-22.04    Running         2
  dwsl2-8718ff1   Stopped         2
  Ubuntu          Stopped         2

> wsl -s dwsl2-8718ff1
この操作を正しく終了しました。

> wsl -l -v
  NAME            STATE           VERSION
* dwsl2-8718ff1   Stopped         2
  Ubuntu-22.04    Running         2
  Ubuntu          Stopped         2
```

### 登録解除する場合

登録解除の場合は下記で ディストリビューションを停止してから `--unregister` を実施します

```bash
wsl -t dwsl2-8718ff1
wsl --unregister dwsl2-8718ff1
```
