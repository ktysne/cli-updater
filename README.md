# cli-updater

Windows PowerShell から実行することで、インストール済みの **Claude Code CLI** と **Codex CLI** のバージョンを確認し、古い場合は最新版を自動でインストールするスクリプトです。

## 概要

`Update-CLIs.ps1` を実行すると、以下の処理を順に行います。

1. ローカルにインストールされている各 CLI のバージョンを取得
2. 公開されている最新バージョンを取得
3. 古ければ最新版へ更新（最新ならスキップ）
4. 更新後のバージョンを再取得し、結果サマリを表示

## 対象 CLI と更新方法

| CLI | 検出パス | 最新版取得元 | 更新コマンド |
| --- | --- | --- | --- |
| Claude Code CLI | `PATH` → `~/.local/bin/claude.exe` → `~/.claude/local/claude.exe` → `%LOCALAPPDATA%\Programs\claude\claude.exe` | `npm view @anthropic-ai/claude-code version` | `claude update`（未インストール時は `https://claude.ai/install.ps1` を実行） |
| Codex CLI | `PATH` 上の `codex` | `npm view @openai/codex version` | `npm install -g @openai/codex@latest` |

> Claude Code のネイティブビルドの最新バージョンは npm 上のメタデータが最も新鮮なため、npm レジストリ経由で取得します。実体は npm パッケージとしてではなく `claude update` で更新されます。

## 必要要件

- Windows 10 / 11
- Windows PowerShell 5.1 または PowerShell 7+
- Node.js（`npm` コマンドが PATH 上にあること）
- インターネット接続

## 使い方

### 通常実行（差分があれば更新）

```powershell
.\Update-CLIs.ps1
```

### 強制再インストール（最新でも再インストール）

```powershell
.\Update-CLIs.ps1 -Force
```

### 実行ポリシーで弾かれる場合

セッション内のみ実行を許可してから実行します。

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Update-CLIs.ps1
```

## 出力例

```
============================================================
 Claude Code CLI
============================================================
[INFO ] 現在のバージョン : 2.1.144
[INFO ] 最新バージョン   : 2.1.145
[INFO ] claude update を実行します...
[ OK  ] Claude Code CLI を 2.1.145 に更新しました。

============================================================
 Codex CLI
============================================================
[INFO ] 現在のバージョン : 0.130.0
[INFO ] 最新バージョン   : 0.132.0
[INFO ] npm install -g @openai/codex@latest を実行します...
[ OK  ] Codex CLI を 0.132.0 に更新しました。

============================================================
 結果サマリ
============================================================
Name            Installed Latest  Action
----            --------- ------  ------
Claude Code CLI 2.1.145   2.1.145 updated
Codex CLI       0.132.0   0.132.0 updated
```

## 終了コード

| Code | 意味 |
| --- | --- |
| 0 | 全 CLI が最新、または更新に成功した |
| 1 | `npm` が見つからない等、前提条件を満たしていない |
| 2 | いずれかの CLI の更新中にエラーが発生、または更新後の検証に失敗 |

## 結果サマリの Action 値

| Action | 意味 |
| --- | --- |
| `up-to-date` | 既に最新版 |
| `updated` | 更新に成功した |
| `failed` | 更新コマンドが失敗した |
| `verification-failed` | 更新後のバージョン確認で最新を確認できなかった |
| `skipped` | 最新バージョンの取得に失敗（ネットワーク／npm を確認） |

## 仕組み（内部処理）

- `ConvertTo-VersionObject` — `2.1.145` / `codex-cli 0.130.0` のような文字列から正規表現で `x.y.z` を抜き出し `[version]` 型に変換し、`-lt` / `-ge` で安全に比較できるようにしています。
- `Resolve-ClaudePath` — `claude` が PATH に無くてもネイティブインストーラの既定パスを順にチェックします。
- `Invoke-CliCheck` — 各 CLI に対して「現バージョン取得 → 最新取得 → 比較 → 更新 → 再検証」を共通フローで実行します。

## 既知の注意点

- Claude Code のネイティブビルドが `~/.local/bin` に入っている場合、初回はそのパスが `PATH` に登録されていない可能性があります。`claude update` 自体は絶対パスで実行できますが、シェルから `claude` コマンドを直接叩きたい場合は環境変数 `PATH` に `%USERPROFILE%\.local\bin` を追加してください（システムのプロパティ → 環境変数 → ユーザー環境変数の Path を編集）。
- `npm` がプロキシ下にある環境では、`npm config set proxy` などの設定が事前に必要です。

## ファイル構成

```
cli-updater/
├── Update-CLIs.ps1   # 更新スクリプト本体
└── README.md         # 本ファイル
```
