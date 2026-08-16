# BlurFollow

**ぼかしが、ウインドウについてくる。**<br>
*Blur that follows your window.*

BlurFollowは、macOSの画面へぼかし・モザイク・不透明カバーを置くオープンソースアプリです。画面上の位置へ固定する **Display Pin** と、選択したウインドウの移動・リサイズに合わせて相対位置を更新する **Window Pin** を備えます。

> [!IMPORTANT]
> BlurFollowの通常マスクは、対象アプリとは別のオーバーレイウインドウです。Chromeを含むブラウザの**タブ共有**や、アプリの**単一ウインドウ共有**には外部オーバーレイが入りません。その場合は **Share Preview（共有用プレビュー）** を作り、元のChrome窓やタブではなく **BlurFollow Share Preview** を会議アプリで選びます。

BlurFollowは位置合わせと確認を助ける視覚的補助であり、security controlではありません。共有前にShare Previewと会議アプリ側の共有プレビューを必ず目視し、見せたくない領域が覆われていることを利用者自身で確認してください。

現在は **0.1.0のプレリリース**です。機密性の高い本番共有へ投入する前に、利用するmacOS、会議アプリ、共有方式、画面構成で実機確認してください。

## 特徴

- **Display Pin** — 選んだディスプレイ内の割合座標へマスクを固定します。
- **Window Pin** — Appleのシステムピッカーで選んだウインドウ内の割合座標へマスクを置き、移動・リサイズに合わせて表示位置を更新します。
- **3つのマスク表現** — Frost（ぼかし）、Mosaic（モザイク）、Redact（不透明カバー）。StrengthはFrostの見え方とMosaicの粒の大きさ・濃さへ反映され、Redactは不透明のままです。
- **Move** — Masksの「Move…」から画面上のマスク本体をドラッグし、既存マスクの位置を調整できます。
- **ツールバー／メニューバー操作** — Display PinとWindow Pinを一覧し、メインウインドウのツールバーまたはメニューバーから、マスクごとにOn/Offを切り替えられます。「Show Masks」はデスクトップ上の通常マスクの全体スイッチで、Offの場合は個別設定がOnでも通常マスクを表示しません。
- **Last-position cover** — 対象窓の位置情報が取れなくなった場合、appが保持している最後の利用可能位置を不透明に覆います。再起動後はWindow Pin作成時の保存位置を使う場合があります。
- **Share Preview** — 選んだ1ウインドウをScreenCaptureKitで端末内処理し、対応するWindow Pinをフレームへ合成した確認用ウインドウを作ります。マスク編集やキャプチャ状態の変化に応じて表示と確認状態を更新します。
- **Share Guide** — ディスプレイ共有、単一窓共有、タブ共有の違いと、選ぶべきBlurFollow側の表示方法を案内します。
- **Reconnect** — 対象窓を閉じた、作り直した、または再接続が曖昧な場合に、Appleのピッカーで対象を選び直せます。
- **Local-first** — 画面フレームのファイル保存、音声取得、録画、分析SDK、広告SDK、BlurFollowからのフレーム送信を行いません。

## どれを共有するか

| 会議アプリで選ぶ対象 | 通常マスクの扱い | 操作 |
|---|---|---|
| ディスプレイ全体 | 外部オーバーレイも画面の一部として見える想定 | 通常のDisplay Pin / Window Pinを確認してディスプレイを共有 |
| Chromeなどの単一ウインドウ | 外部オーバーレイは共有映像に含まれない | Share Previewを作り、**BlurFollow Share Preview**を共有 |
| Chrome / Safariなどのブラウザタブ | デスクトップ上の外部オーバーレイは含まれない | タブ共有を使わず、ブラウザ窓から作ったShare Previewを共有 |
| BlurFollow Share Preview | Window Pinをフレーム内へ合成 | マスク位置を確認し、このプレビューを共有 |

Share Previewは合成結果を見せるための通常のmacOSウインドウです。元窓、BlurFollow側のプレビュー、会議アプリ側のプレビューは別の表示経路です。共有を開始した後も、会議アプリ側のプレビューを確認してください。

## 動作環境と権限

- macOS 14.0以降
- Xcode 16以降を推奨
- Apple Silicon / Intel Mac

### macOS 15.2以降

Window PinとShare Previewは、Appleのシステムピッカーで利用者が選んだ窓ごとに認可されます。

### macOS 14〜15.1

選択した窓のidentityを解決するため、広域の「画面収録」許可が必要です。許可後はBlurFollowを終了して再起動してください。拒否した場合、Window PinとShare Previewは開始しません。Display Pinはこの権限なしで利用できます。

権限の目的とOS差分は [互換性](Docs/COMPATIBILITY.md) と [脅威・制約モデル](Docs/THREAT_MODEL.md) に記載しています。

## 使い方

### Display Pin — 画面へ固定

1. Homeで「画面に固定」を選びます。
2. 対象ディスプレイ上でドラッグし、マスク範囲を決めます。
3. Masksで名前、Frost / Mosaic / Redact、Frost / MosaicのStrength、有効／無効を調整します。
4. 共有に使うディスプレイと会議アプリのプレビューで位置を確認します。

Display Pinはディスプレイ内の割合座標です。解像度、拡大率、ディスプレイ配置、主画面の変更後は位置を再確認してください。保存したdisplay UUIDが見つからない場合、そのマスクは表示されません。

### Window Pin — ウインドウへ追従

1. Homeで「ウインドウに追従」を選びます。
2. Appleのシステムピッカーで対象窓を選びます。
3. 対象窓上でドラッグし、隠したい範囲を決めます。
4. 対象窓を移動・リサイズし、マスク位置を目視確認します。

Window Pinはウインドウ内の**割合座標**を追います。DOM要素、文字列、フォーム項目などの意味を認識しません。ページのレイアウト、ツールバー、サイドバー、ズーム倍率が変わると、隠したい情報とマスクの関係も変わり得ます。

対象窓を閉じて作り直した、タイトルが変わった、または状態が「Select again／選び直す」になった場合は、Masksの「Reconnect…」で正しい窓を選び直してください。再接続後もマスク位置を必ず確認します。

### Masks — 見た目、位置、On/Offを調整

1. Masksで対象マスクを開き、Frost / Mosaic / RedactとStrengthを調整します。StrengthはFrostとMosaicの見え方へ反映されます。RedactはStrengthにかかわらず不透明です。
2. 位置を変える場合は「Move…」を押し、画面上のマスク本体をドラッグします。マウスまたはトラックパッドを離すと新しい割合座標が保存されます。保存前にEscまたは「Cancel Move」を使うと取り消せます。「Move…」は全体と対象マスクがOnで、位置を取得できている場合に使えます。
3. メインウインドウのツールバー、またはメニューバーのBlurFollowアイコンを開くと、各マスクを個別にOn/Offできます。「Show Masks」はデスクトップ上の通常マスクをまとめて切り替えます。Share Previewは個別にOnのWindow Pinを使うため、別に表示を確認してください。
4. Strength、位置、On/Offを変えた後は、通常表示と利用中のShare Preview、会議アプリ側のプレビューをもう一度確認します。

### Share Preview — 単一窓／タブ共有の代替

1. Share GuideまたはHomeで「Share Preview」を開始します。
2. Appleのシステムピッカーで元のウインドウを選びます。
3. **BlurFollow Share Preview**内に、想定したWindow Pinがすべて合成されていることを確認します。
4. 画面内の「位置を確認しました」に同意します。
5. Google Meet、Zoom、Teamsなどで、元の窓やタブではなく **BlurFollow Share Preview** を単一ウインドウ共有します。
6. 会議アプリ側のプレビューでも、範囲、子ウインドウ、メニュー、スクロール後の表示を確認します。
7. 終了時は「停止」を押すか、Share Previewウインドウを閉じます。

Share Previewへ合成されるのはWindow Pinだけです。Display Pinは合成されません。対応するWindow Pinがない、保存データに復旧警告がある、mask座標やcapture metadataを処理できない、といった場合は全面を不透明にして「Preview paused」と表示します。これは誤った映像を見せないための表示上の挙動であり、共有内容の正しさを保証するものではありません。

対応するWindow Pinの位置、表現、Strength、On/OffやShare Previewのキャプチャ状態が変わると、Share Previewは表示を更新し、必要に応じて直前の表示を消すか覆います。「位置を確認しました」が解除された場合は、現在の合成結果が表示されるまで待ち、すべてのマスクを確認し直してください。表示更新そのものは、遅延ゼロや移動中の完全な位置一致、マスク位置や共有内容の正しさを保証しません。

## 状態の読み方

| 表示 | 意味 | 利用者の操作 |
|---|---|---|
| Following / Placed | 現在の窓またはディスプレイ位置を取得し、その座標でマスクを描画中 | 共有前に実際のマスク位置を確認 |
| Checking position / Finding window | 表示位置を確認中、または対象窓を探索中 | 現在位置とLast-position coverの表示を確認 |
| Select again | 対象窓を特定できず、再接続が必要 | Reconnectで選び直し、位置を確認 |
| Last-position cover | 最後に取得した窓位置を全体カバーで表示 | 現在位置とは限らないため、共有を止めて再接続 |
| Preview active | Share Previewへ合成frameを表示中 | 全マスクを確認し、会議アプリ側でも再確認 |
| Preview paused | 合成条件を満たさず全面カバーまたは空表示 | 共有せず、警告、source、Window Pinを確認 |

色だけで状態を判断しないでください。「Following」や「Placed」は座標を取得できたという技術状態であり、隠したい情報とマスクが一致しているという判定ではありません。

## 保存データ

保存するもの:

- マスク名、mode、style、強度、角丸、割合座標
- 対象ディスプレイUUID
- 対象アプリ名、bundle ID、窓タイトル、窓identityの再接続情報
- アプリ設定

保存しないもの:

- 画面ピクセル
- Share Previewの映像frame
- 音声、録画
- 利用分析

設定はApplication Support配下のJSONへatomic writeし、検証済みの直前snapshotをbackupとして保持します。破損からbackupを復元した場合は警告を出し、全マスクの確認を求めます。「Delete All Masks」はprimaryとbackupの双方を削除対象にします。

マスク名とウインドウタイトル自体が機密情報になり得ます。設定JSONをIssueへ添付する前に内容を確認してください。Share PreviewをZoomやMeetなどへ共有した後の映像送信・保存は、その第三者サービスの処理です。BlurFollowがframeを送信しないことと、会議アプリが共有映像を送信することは別です。

詳細は [プライバシー方針](PRIVACY.md) を参照してください。

## 既知の制約

- BlurFollowは視覚的補助であり、security control、DLP、アクセス制御、暗号化、法令準拠機能ではありません。
- 通常オーバーレイは単一ウインドウ共有やブラウザタブ共有へ入りません。Share Previewと会議アプリ側のプレビューを確認してください。
- FrostとMosaicは元情報を不可逆に消去する処理ではありません。Redactも表示経路や位置選択の誤りまでは検出しません。
- Last-position coverはappが保持する最後の利用可能位置だけを覆います。再起動後はWindow Pin作成時の古い保存位置を使う場合があり、現在位置との一致は確認できません。
- Window Pinは幾何学的な割合追従です。ページ内の意味的なUI要素には追従しません。
- 窓を閉じて作り直した場合、自動再接続は同一アプリと保存タイトルの候補が厳密に1つのときだけ試みます。同名窓、無題窓、タイトル変更では再選択が必要です。
- 複数ディスプレイ、異なるDPI、Spaces、フルスクリーン、主画面変更では、利用環境ごとの確認が必要です。
- 子ウインドウ取り込みはmacOS 14.2以降で有効です。メニュー、シート、DRM対象コンテンツなどは元アプリ／macOS側の制約を受けます。
- アプリ、macOS、会議サービスの更新によりcapture挙動は変わり得ます。

## 開発

### 依存ツール

- Swift tools 5.10 / Swift 5.10 language mode
- Xcode 16+を推奨
- XcodeGen（Xcode projectを再生成する場合）

### ビルドとテスト

    cd /path/to/BlurFollow
    swift test
    ./build.sh
    ./Scripts/check-release.sh

Xcode projectを再生成する場合:

    xcodegen generate
    open BlurFollow.xcodeproj

build.shはad-hoc署名したローカル開発用app bundleをdistへ作ります。公開用buildは、review済みのsemantic-version tagからXcode Cloudが作成し、App Store Connectへ送ります。

### 文書

- [アーキテクチャ](Docs/ARCHITECTURE.md)
- [互換性](Docs/COMPATIBILITY.md)
- [リリース手順](Docs/RELEASE.md)
- [脅威・制約モデル](Docs/THREAT_MODEL.md)
- [依存関係](DEPENDENCIES.md)
- [第三者通知](THIRD_PARTY_NOTICES.md)
- [セキュリティポリシー](SECURITY.md)
- [商標方針](TRADEMARKS.md)
- [ブランド素材の由来](Brand/PROVENANCE.md)
- [App Store提出素材](StoreAssets/README.md)

## ライセンスと商用利用

コードとプロジェクト独自の通常文書は、特記がない限り [Apache License 2.0](LICENSE) の下で公開します。条件を満たす限り、利用・改変・再配布・商用販売が可能です。再配布時はLICENSE、必要なNOTICE、変更表示、帰属、patent terminationなどを確認してください。

次はApache-2.0の対象外です。

- DCOなど、出典と条件を個別に示す第三者の法的文面
- Brand配下およびAssets.xcassets内のロゴ・アイコン画像
- BlurFollowの名称、ロゴ、商標上の使用

詳細は [NOTICE](NOTICE)、[第三者通知](THIRD_PARTY_NOTICES.md)、[商標方針](TRADEMARKS.md)、[ブランド素材の由来](Brand/PROVENANCE.md) を確認してください。

Apache-2.0上の商用販売可否と、公式名称・ロゴを用いた販売可否は別問題です。公式版として公開・課金する前に、権利主体、素材provenance、名称・称呼のclearance、Apple契約、App Review、プライバシー表示、適用法令を専門家と確認してください。未完了なら公式公開・課金を行いません。

## コントリビューション

[CONTRIBUTING.md](CONTRIBUTING.md)、[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)、[DCO](DCO) を確認してください。脆弱性に関する報告は公開Issueではなく [SECURITY.md](SECURITY.md) の非公開窓口を使ってください。
