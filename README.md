# cli-updater

Windows PowerShell から実行することで、インストール済みの **Claude Code CLI** と **Codex CLI** のバージョンを確認し、古い場合は最新版を自動でインストールするスクリプトです。

## 特徴

- **ワンショット実行** — `.\Update-CLIs.ps1` を叩くだけで両 CLI のチェック・更新が完了
- **べき等** — 既に最新の場合はスキップ（`-Force` で強制再インストール可）
- **環境差を吸収** — Claude Code が PATH に無い場合もネイティブインストーラの既定パスを順に探索
- **見やすい出力** — 色分けされたログと結果サマリ表
- **CI 連携向けの終了コード** — 成功 / 前提不足 / 更新失敗 で異なる exit code

## 動作フロー

`Update-CLIs.ps1` を実行すると、各 CLI に対して以下を順に行います。

1. ローカルにインストールされている CLI のバージョンを取得
2. 公開されている最新バージョンを取得
3. 古ければ最新版へ更新（最新ならスキップ）
4. 更新後のバージョンを再取得して検証
5. すべての結果をサマリ表で表示

## 対象 CLI と更新方法

| CLI | 検出パス | 最新版取得元 | 更新コマンド |
| --- | --- | --- | --- |
| Claude Code CLI | `PATH` → `~/.local/bin/claude.exe` → `~/.claude/local/claude.exe` → `%LOCALAPPDATA%\Programs\claude\claude.exe` | `npm view @anthropic-ai/claude-code version` | `claude update`（未インストール時は `https://claude.ai/install.ps1` を実行） |
| Codex CLI | `PATH` 上の `codex`（通常 `%APPDATA%\npm\codex.ps1`） | `npm view @openai/codex version` | `npm install -g @openai/codex@latest` |

> Claude Code のネイティブビルドは npm パッケージとして配布されているわけではありませんが、最新バージョン番号は npm レジストリのメタデータが最も新鮮なため、バージョン比較用途で `npm view` を使用しています。実体の更新は組み込みの `claude update` コマンドが行います。

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

### 更新が必要なケース

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

### 既に最新のケース

```
============================================================
 Claude Code CLI
============================================================
[INFO ] 現在のバージョン : 2.1.145
[INFO ] 最新バージョン   : 2.1.145
[ OK  ] Claude Code CLI は最新です。更新は不要です。
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

## トラブルシューティング

### `claude` コマンドが見つからない

ネイティブインストーラで Claude Code を入れた場合、`%USERPROFILE%\.local\bin` が PATH に登録されていないことがあります。本スクリプトは絶対パス経由で動作するので実行自体には影響しませんが、シェルから `claude` を直接呼びたい場合は以下を実施してください。

1. **設定 → システム → バージョン情報 → システムの詳細設定** を開く
2. **環境変数** → ユーザー環境変数の **Path** を編集
3. **新規** で `%USERPROFILE%\.local\bin` を追加
4. ターミナルを再起動

### `npm` がプロキシ環境で失敗する

```powershell
npm config set proxy http://your-proxy:port
npm config set https-proxy http://your-proxy:port
```

### 文字化けする

スクリプトは UTF-8 BOM 付きで保存されています。Windows PowerShell 5.1 / PowerShell 7 のいずれでも日本語が正しく表示されます。もし化ける場合は保存し直す際に BOM が外れていないか確認してください。

## ファイル構成

```
cli-updater/
├── .gitignore
├── README.md          # 本ファイル
└── Update-CLIs.ps1    # 更新スクリプト本体
```

## ライセンス

MIT
