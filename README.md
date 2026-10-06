# install-notification-hooks.ps1

Claude Codeが「確認が必要な時」「通知を送りたい時」「タスクが完了した時」にWindowsのトースト通知を出すようにするセットアップスクリプト。BurntToastの導入からhookの登録まで1本で完結する。

## 対応環境

- Windows
- PowerShell 7 (`pwsh`)。Claude Codeのhookで`"shell": "powershell"`と指定した場合、実際に呼ばれるのはこの`pwsh`である。**レガシーのWindows PowerShell 5.1(`powershell.exe`)ではない**点に注意。実行ポリシーの違いにより、`powershell.exe`経由だとBurntToastの`.psm1`読み込みがブロックされることを確認済み。
- Claude Code(CLIまたはVSCode拡張機能どちらでも可)

## 使い方

```powershell
./install-notification-hooks.ps1
```

### 「デジタル署名されていません」と出て実行できない場合

ZIP等でダウンロードしたスクリプトには「インターネットから取得したファイル」の印(Mark of the Web)が付くため、実行ポリシー(`RemoteSigned`など)によって次のようなエラーでブロックされる。

```text
ファイル ...\install-notification-hooks.ps1 を読み込めません。ファイル ...\install-notification-hooks.ps1 はデジタル署名されていません。
```

以下のどちらかで実行できる。

```powershell
# 方法1(推奨): ブロックを解除してから実行
Unblock-File ./install-notification-hooks.ps1
./install-notification-hooks.ps1

# 方法2: 今回だけ実行ポリシーを回避して実行(システム設定は変更しない)
pwsh -ExecutionPolicy Bypass -File ./install-notification-hooks.ps1
```

方法1でも解消しない場合は、グループポリシーで`AllSigned`等が強制されている可能性がある。`Get-ExecutionPolicy -List`で確認し、方法2を使うこと。

`~/.claude/settings.json`(存在しなければ新規作成)に、以下3つのhookをマージ追加する。既存の設定(他のhookや`permissions`など)はそのまま保持される。

| Hook | 発火タイミング |
|---|---|
| `Notification` | CLI利用時の通知・入力待ちアイドル通知 |
| `Stop` | タスク(ターン)完了時 |
| `PermissionRequest` | Claude Codeが確認・許可を必要としている時 |

実行後、Claude Codeの再起動が必要(VSCode拡張機能を使っている場合はコマンドパレットから「Developer: Reload Window」)。

再実行しても安全(冪等)。BurntToastのコマンドを含むhookが既にある場合はそのイベントをスキップし、重複追加しない。

テスト用に別の設定ファイルへ書き込みたい場合は`-SettingsPath`を指定できる。

```powershell
./install-notification-hooks.ps1 -SettingsPath "C:\path\to\test\settings.json"
```

## BurntToastモジュールについて

トースト通知の表示には[BurntToast](https://github.com/Windos/BurntToast)(作者: Joshua King、オープンソース、PowerShell Gallery配布)を使う。未インストールの場合、スクリプトがPowerShell Galleryから自動でインストールする。

- インストールするバージョンは動作確認済みの`1.1.0`に固定している(`-RequiredVersion`)。`-Force`で信頼されていないリポジトリの確認プロンプトを省略しているため、バージョンを固定しないと未確認の将来のリリースが確認なしで入りうる。バージョンを上げる場合は、動作確認のうえスクリプト冒頭の`$burntToastVersion`を書き換える。
- 同梱のDLLはMicrosoft / .NET Foundationの署名付き。モジュール本体の`.psm1`/`.psd1`は署名なし。
- 通知に表示される画像(トーストの絵)はWindows標準ではなく、BurntToastに同梱されている標準ロゴ(`Images\BurntToast.png`)。BurntToastと一緒にインストールされるので、配布先の環境でも表示される。

## なぜ `Notification` だけでなく `PermissionRequest` も要るのか

Claude CodeのVSCode拡張機能は、確認プロンプトをパネル内のネイティブUIとして表示する。これはCLIが使う「通知送信」の仕組みを経由しないため、**`Notification` hookはVSCode拡張機能の確認プロンプトに対して発火しない**(既知の問題: [anthropics/claude-code#11156](https://github.com/anthropics/claude-code/issues/11156))。

一方`PermissionRequest`は権限チェックの仕組み自体に紐づいたイベントで、UIがどう表示されるかに関係なく発火する。実機(VS Code Insiders)で確認済み。CLIで使う場合は`Notification`だけでも足りるが、VSCode拡張機能を使うなら`PermissionRequest`が要。両方登録しておけばどちらの使い方でも通知が出る。

## モジュールパスをハードコードしない理由

BurntToastのインストール場所は環境によって異なる(OneDriveでリダイレクトされた`ドキュメント`フォルダ配下など、`$env:PSModulePath`に載っていない特殊な場所になっていることもある)。特にVSCodeがhookを実行する際のプロセス環境は、通常のターミナルとは`PSModulePath`が異なることがあり、フルパスをハードコードしていても失敗しうる。

このスクリプトが生成するhookコマンドは、実行のたびに`Get-Module -ListAvailable -Name BurntToast`でインストール場所を動的に解決してから`Import-Module`する。これによりマシンやユーザーが変わっても、BurntToastさえインストールされていれば動く。

## トラブルシューティング

- スクリプト実行時に「デジタル署名されていません」と出る場合は、[「デジタル署名されていません」と出て実行できない場合](#デジタル署名されていませんと出て実行できない場合)を参照。

- 通知が出ない場合、まず`pwsh -NoProfile -Command`経由で該当のhookコマンドを手動実行してエラーが出ないか確認する(`powershell.exe`ではなく`pwsh.exe`で試すこと)。
- BurntToast自体が入っているか: `Get-Module -ListAvailable -Name BurntToast`
- `settings.json`のJSON構文が壊れていないか: `Get-Content ~/.claude/settings.json -Raw | ConvertFrom-Json`
