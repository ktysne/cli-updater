## AI 相互レビュー（Claude ↔ Codex）

相互レビューの手順の正本は [docs/cross-review.md](docs/cross-review.md)（vendored）と、
グローバル SKILL `~/.claude/skills/cross-review/SKILL.md` です。
このリポジトリ固有のレビュー観点は `.cross-review.md` にあります。

### 検証コマンド
- 構文解析: PowerShell 5.1 と 7 のそれぞれのセッションで、リポジトリのルートから次を実行し、何も出力されないこと
  - `$e=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile("$PWD\Update-CLIs.ps1",[ref]$null,[ref]$e); $e`
- 自動テストはありません。更新処理は実機で `.\Update-CLIs.ps1` を実行して確かめます

### 基盤の更新
`node tools/cross-review.sync.js`（検査は `node tools/cross-review.sync.js --check`）で上流から取り込みます。
更新手順は「同期 → 表示された移行ノートの作業 → 上の検証コマンド」の順です。
package.json が無いので、レビューは `node tools/cross-review.js codex` のように直接実行します。

### レビューの起点
既定のレビュアーは実装者と別のベンダーです。実装を一区切りしたら 3 択を `AskUserQuestion` で提示します（詳細は SKILL）。
