# devtool-WSL2

WSL2 の開発環境を自動構築するセット  
以前は、 WSL2 に都度コマンドを打って環境構築していたが似たような環境が複数必要になるため自動化し環境構築にかかる時間を省力化した。

## Software

* CLI commands
  * bash
  * ca-certificates
  * curl
  * git
  * gpg-agent
  * man
  * mtr
  * nano
  * sudo
  * tcpdump
  * traceroute
  * unzip
  * vim
  * wget

| Common software                                               | Latest software version                                                  |
| :------------------------------------------------------------ | :----------------------------------------------------------------------- |
| [Docker Engine](https://gitub.com/moby/moby)                  | ![GitHub Tag](https://img.shields.io/github/v/tag/moby/moby)             |
| [fish-shell](https://github.com/fish-shell/fish-shell)        | ![GitHub Tag](https://img.shields.io/github/v/tag/fish-shell/fish-shell) |
| [asdf](https://github.com/asdf-vm/asdf)                       | ![GitHub Tag](https://img.shields.io/github/v/tag/asdf-vm/asdf)          |
| [mame/wsl2-ssh-agent](https://github.com/mame/wsl2-ssh-agent) | ![GitHub Tag](https://img.shields.io/github/v/tag/mame/wsl2-ssh-agent)   |

| asdf Plugins                                        | asdf Plugin URL                                                                   | Latest software version                                                 |
| :-------------------------------------------------- | :-------------------------------------------------------------------------------- | :---------------------------------------------------------------------- |
| [assh](https://github.com/moul/assh)                | [zekker6/asdf-assh](https://github.com/zekker6/asdf-assh)                         | ![GitHub Tag](https://img.shields.io/github/v/tag/moul/assh)            |
| [aws-cli](https://github.com/aws/aws-cli/)          | [MetricMike/asdf-awscli](https://github.com/MetricMike/asdf-awscli)               | ![GitHub Tag](https://img.shields.io/github/v/tag/aws/aws-cli)          |
| [fzf](https://github.com/junegunn/fzf)              | [asdf-fzf](https://github.com/kompiro/asdf-fzf)                                   | ![GitHub Tag](https://img.shields.io/github/v/tag/junegunn/fzf)         |
| [ghq](https://github.com/x-motemen/ghq)             | [kajisha/asdf-ghq](https://github.com/kajisha/asdf-ghq)                           | ![GitHub Tag](https://img.shields.io/github/v/tag/x-motemen/ghq)        |
| [poetry](https://github.com/python-poetry/poetry)   | [asdf-community/asdf-poetry](https://github.com/asdf-community/asdf-poetry)       | ![GitHub Tag](https://img.shields.io/github/v/tag/python-poetry/poetry) |
| [python](https://github.com/python/cpython)         | [danhper/asdf-python](https://github.com/danhper/asdf-python)                     | ![GitHub Tag](https://img.shields.io/github/v/tag/python/cpython)       |
| [rust](https://github.com/rust-lang/rust)           | [code-lever/asdf-rust](https://github.com/code-lever/asdf-rust)                   | ![GitHub Tag](https://img.shields.io/github/v/tag/rust-lang/rust)       |
| [aws-sam-cli](https://github.com/aws/aws-sam-cli)   | [amrox/asdf-pyapp](https://github.com/amrox/asdf-pyapp)                           | ![GitHub Tag](https://img.shields.io/github/v/tag/aws/aws-sam-cli)      |
| [starship](https://github.com/starship/starship)    | [gr1m0h/asdf-starship](https://github.com/gr1m0h/asdf-starship)                   | ![GitHub Tag](https://img.shields.io/github/v/tag/starship/starship)    |
| [Terraform](https://github.com/hashicorp/terraform) | [asdf-community/asdf-hashicorp](https://github.com/asdf-community/asdf-hashicorp) | ![GitHub Tag](https://img.shields.io/github/v/tag/hashicorp/terraform)  |
| [Tmux](https://github.com/tmux/tmux)                | [aphecetche/asdf-tmux](https://github.com/aphecetche/asdf-tmux)                   | ![GitHub Tag](https://img.shields.io/github/v/tag/tmux/tmux)            |

| Rust Tools                                       | Latest release                                                          |
| :----------------------------------------------- | :---------------------------------------------------------------------- |
| [dua-cli](https://github.com/Byron/dua-cli)      | ![GitHub Tag](https://img.shields.io/github/v/tag/Byron/dua-cli)        |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | ![GitHub Tag](https://img.shields.io/github/v/tag/BurntSushi/ripgrep)   |
| [topgrade](https:topgrade-rs/topgrade)           | ![GitHub Tag](https://img.shields.io/github/v/tag/topgrade-rs/topgrade) |

## 使い方

[Releases · naa0yama/devtool-wsl2](https://github.com/naa0yama/devtool-wsl2/releases) から tar.gz をダウンロードします。

Windows の場合はこちらで問題ないはず。  

```powershell
cmd.exe /C "copy /b devtool-wsl2-*.tar.gz.part* devtool-wsl2.tar.gz"

```

### 展開

WSL2 はデフォルトだと `$Env:USERPROFILE\AppData\Local\Packages\CanonicalGroupLimited.Ubuntu22.04LTS_<RANDOM>\LocalState` にあります。  
これだと扱いづらいため `$Env:USERPROFILE\Documents\WSL2` に展開する事にします。  
ディストリビューション名 `Ubuntu-2204` とします。

こちらは PowerShell で作業とします

```powershell
mkdir $Env:USERPROFILE\Documents\WSL2\Ubuntu-2204

```

Import の準備が出来たのでインポートします

```powershell
wsl --import Ubuntu-2204 $Env:USERPROFILE\Documents\WSL2\Ubuntu-2204 $Env:USERPROFILE\Downloads\devtool-wsl2.tar.gz

```

Import 結果を確認します  
`Ubuntu-2204` があれば Import 出来ています。

```powershell
wsl -l -v

```

```powershell
> wsl -l -v
  NAME            STATE           VERSION
* Ubuntu-22.04    Running         2
  Ubuntu-2204     Stopped         2
  Ubuntu          Stopped         2

```

実際に起動してみます。  
このセクションではデフォルトに設定してないためディストリビューション指定で起動します。  
起動出来ると Bash が起動します。

```powershelll
wsl -d Ubuntu-2204
user@dead-desk1:~$

```

asdf が使えるか確認しておきましょう。  
`asdf current` で確認出来ます。

```powershelll
> asdf current
assh            2.16.0          /home/user/.tool-versions
aws-sam-cli     1.115.0         /home/user/.tool-versions
awscli          2.15.19         /home/user/.tool-versions
fzf             0.50.0          /home/user/.tool-versions
ghq             1.6.1           /home/user/.tool-versions
poetry          1.7.1           /home/user/.tool-versions
python          3.10.12         /home/user/.tool-versions
rust            stable          /home/user/.tool-versions
starship        1.18.2          /home/user/.tool-versions
terraform       1.1.3           /home/user/.tool-versions
tmux            3.4             /home/user/.tool-versions
```

### デフォルトに設定する場合

この手順では default に設定していないためディストリビューションを指定して起動する必要があります。  
手間を省くために defualt に設定すると `wsl` コマンドで起動してくる事になります  
下記の例では `Ubuntu-2204` を defualt に設定します。  
`*` の付いている物が default 起動の WSL です。

```powershell
> wsl -l -v
  NAME            STATE           VERSION
* Ubuntu-22.04    Running         2
  Ubuntu-2204     Stopped         2
  Ubuntu          Stopped         2

> wsl -s Ubuntu-2204
この操作を正しく終了しました。

> wsl -l -v
  NAME            STATE           VERSION
* Ubuntu-2204     Stopped         2
  Ubuntu-22.04    Running         2
  Ubuntu          Stopped         2

```

### 登録解除する場合

登録解除の場合は下記で ディストリビューションを停止してから `--unregister` を実施します

```bash
wsl -t Ubuntu-2204
wsl --unregister Ubuntu-2204

```
