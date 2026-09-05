# BlurFollow

**ぼかしが、ウインドウについてくる。**<br>
*Blur that follows your window.*

BlurFollowは、macOSの画面へぼかし・モザイク・不透明カバーを置くオープンソースアプリです。画面上の位置へ固定する **Display Pin**、選択したウインドウの移動・リサイズに合わせて相対位置を更新する **Window Pin**、完全一致・前方一致・部分一致（Contains）・正規表現で見つけた文字ブロックを自動でモザイクする独立機能 **Text Follow (Beta)／文字追従（ベータ）** を備えます。

> [!IMPORTANT]
> BlurFollowの通常マスクは、対象アプリとは別のオーバーレイウインドウです。Chromeを含むブラウザの**タブ共有**や、アプリの**単一ウインドウ共有**には外部オーバーレイが入りません。その場合は **Share Preview（共有用プレビュー）** を作り、元のChrome窓やタブではなく **BlurFollow Share Preview** を会議アプリで選びます。Share Previewは、選択sourceに対応するWindow Pinと、接続済みText Followルールの完了済み認識結果をフレーム内へ合成します。

BlurFollowは位置合わせと確認を助ける視覚的補助であり、security controlではありません。共有前にShare Previewと会議アプリ側の共有プレビューを必ず目視し、見せたくない領域が覆われていることを利用者自身で確認してください。

現在は **0.2.0のプレリリース**です。機密性の高い本番共有へ投入する前に、利用するmacOS、会議アプリ、共有方式、画面構成で実機確認してください。

## 特徴

- **Display Pin** — 選んだディスプレイ内の割合座標へマスクを固定します。
- **Window Pin** — Appleのシステムピッカーで選んだウインドウ内の割合座標へマスクを置き、移動・リサイズに合わせて表示位置を更新します。
- **Text Follow (Beta)／文字追従（ベータ）** — 選択したウインドウを端末内OCRし、完全一致・前方一致・部分一致（Contains）・正規表現に一致するすべての文字ブロックへモザイクを追従表示します。Containsは大文字・小文字を区別し、一致した部分だけではなくVisionが返した認識ブロック全体を覆います。同じパターンが同時に複数箇所へ一致しても、保存ルールと無料枠の消費は1件です。
- **文字認識中の保護方式** — 既定の厳格安全モードでは、接続中、画面遷移・スクロール後の認識中、取得失敗、ウインドウ情報の一時的な欠落中に加え、OCRが0件を返したときも、現在または最後に確認できた対象ウインドウ全体を一時モザイクします。Settingsでオフにすると直前に完了した一致マスクだけを保って全面フラッシュを避けられますが、OCRの見逃し、移動した文字、新しく現れた文字への漏れ耐性は下がります。
- **3つのマスク表現** — Frost（ぼかし）、Mosaic（モザイク）、Redact（不透明カバー）。FrostとMosaicは効果の強さ、粒度、色味、枠線を個別に調整でき、Redactは不透明のままです。デスクトップ上のMosaicは公開Core Imageフィルタ`CIPixellate`で実際の背面をピクセル化し、フィルタを利用できない場合は読み取れる元表示を残さず不透明表示へfallbackします。
- **Move** — Masksまたはメインウインドウのツールバーから「Move…」を選び、画面上のマスク本体をドラッグして既存マスクの位置を調整できます。
- **ツールバー／メニューバー操作** — Display PinとWindow Pinを一覧し、メインウインドウのツールバーからマスクごとのOn/OffとMove、メニューバーからOn/Offを操作できます。「Show Masks」はデスクトップ上の通常マスクの全体スイッチで、Offの場合は個別設定がOnでも通常マスクを表示しません。
- **Last-position cover** — 対象窓の位置情報が取れなくなった場合、appが保持している最後の利用可能位置を不透明に覆います。再起動後はWindow Pin作成時の保存位置を使う場合があります。
- **Share Preview** — 選んだ1ウインドウをScreenCaptureKitで端末内処理し、対応するWindow Pinと、同じsourceへ接続済み・有効なText Followルールで完了済みのすべての一致Mosaicをフレームへ合成します。動的ルールの認識状態やマスク編集に応じて直前の表示を即座に消し、必要なら全面を覆います。
- **Share Guide** — ディスプレイ共有、単一窓共有、タブ共有の違いと、選ぶべきBlurFollow側の表示方法を案内します。
- **Reconnect** — 対象窓を閉じた、作り直した、または再接続が曖昧な場合に、Appleのピッカーで対象を選び直せます。
- **Local-first** — 画面フレームのファイル保存、音声取得、録画、分析SDK、広告SDK、BlurFollowからのフレーム送信を行いません。
- **通常利用は無料** — 公式Mac App Store版はDisplay Pin 10件、Window Pin 5件、Text Follow (Beta)／文字追従（ベータ）のルールを2件まで無料で作成できます。ベータ表記によってこの2件の無料枠は変わらず、各枠を超える作成は買い切りの「無制限マスク」でアプリ側の上限をまとめて解除できます。既存マスク・ルールや安全・確認機能は課金状態にかかわらず利用できます。同じText Followルールの複数一致は1件として数えます。0.1.1以前からのApp Storeユーザとソースビルドは無制限です。

Text Followのベータ表記は機能成熟度を示すだけで、本文に記載する安全側の動作、端末内処理、非保存・非送信、共有前確認の契約を緩和しません。

## どれを共有するか

| 会議アプリで選ぶ対象 | 通常マスクの扱い | 操作 |
|---|---|---|
| ディスプレイ全体 | 外部オーバーレイも画面の一部として見える想定 | Display Pin / Window Pin / Text Followを確認してディスプレイを共有 |
| Chromeなどの単一ウインドウ | 外部オーバーレイは共有映像に含まれない | Share Previewを作り、**BlurFollow Share Preview**を共有 |
| Chrome / Safariなどのブラウザタブ | デスクトップ上の外部オーバーレイは含まれない | タブ共有を使わず、ブラウザ窓から作ったShare Previewを共有 |
| BlurFollow Share Preview | 対応するWindow Pinと、接続済みText Followルールの完了済み一致をフレーム内へ合成 | 動的認識状態を含む全マスクを確認し、このプレビューを共有 |

Share Previewは合成結果を見せるための通常のmacOSウインドウです。元窓、BlurFollow側のプレビュー、会議アプリ側のプレビューは別の表示経路です。共有を開始した後も、会議アプリ側のプレビューを確認してください。

## 動作環境と権限

- macOS 14.0以降
- Xcode 16以降を推奨
- Apple Silicon / Intel Mac

### macOS 15.2以降

Window Pin、Text Follow、Share Previewは、Appleのシステムピッカーで利用者が選んだ窓ごとに認可されます。Text Followの文字認識はApple Visionを使ってこのMac内だけで行い、フレームや認識文字列を保存・送信しません。

### macOS 14〜15.1

選択した窓のidentityを解決し、Text Followを端末内処理するため、広域の「画面収録」許可が必要です。許可後はBlurFollowを終了して再起動してください。拒否した場合、Window Pin、Text Follow、Share Previewは開始しません。Display Pinはこの権限なしで利用できます。

権限の目的とOS差分は [互換性](Docs/COMPATIBILITY.md) と [脅威・制約モデル](Docs/THREAT_MODEL.md) に記載しています。

## 使い方

### Display Pin — 画面へ固定

1. Homeで「画面に固定」を選びます。
2. 対象ディスプレイ上でドラッグし、マスク範囲を決めます。
3. Masksで名前、Frost / Mosaic / Redact、Frost / Mosaicの強さ・粒度・色味・枠線、有効／無効を調整します。
4. 共有に使うディスプレイと会議アプリのプレビューで位置を確認します。

Display Pinはディスプレイ内の割合座標です。解像度、拡大率、ディスプレイ配置、主画面の変更後は位置を再確認してください。保存したdisplay UUIDが見つからない場合、そのマスクは表示されません。

### Window Pin — ウインドウへ追従

1. Homeで「ウインドウに追従」を選びます。
2. Appleのシステムピッカーで対象窓を選びます。
3. 対象窓上でドラッグし、隠したい範囲を決めます。
4. 範囲を決めるとBlurFollowのMasksへ自動で戻るので、表現と見た目を調整します。
5. 対象窓を移動・リサイズし、マスク位置を目視確認します。

Window Pinはウインドウ内の**割合座標**を追います。DOM要素、文字列、フォーム項目などの意味を認識しません。ページのレイアウト、ツールバー、サイドバー、ズーム倍率が変わると、隠したい情報とマスクの関係も変わり得ます。

対象窓を閉じて作り直した、タイトルが変わった、または状態が「Select again／選び直す」になった場合は、Masksの「Reconnect…」で正しい窓を選び直してください。再接続後もマスク位置を必ず確認します。

### Text Follow (Beta) — 文字追従（ベータ）

1. Homeで「Text Follow／文字追従」を選びます。
2. ルール名、完全一致・前方一致・部分一致（Contains）・正規表現のいずれか、検索パターンを入力します。照合は大文字・小文字を区別します。Containsは認識文字列の途中にパターンが含まれる場合に一致します。
3. Appleのシステムピッカーで対象ウインドウを選びます。
4. BlurFollowは選択窓の変更フレームをこのMac内で認識し、一致した文字ブロックすべてへMosaicを表示します。Containsを含むどのモードでも、部分文字だけでなくVisionが返した認識ブロック全体が対象です。同じパターンが複数箇所にあっても、無料枠では保存ルール1件です。
5. Masksで一致数、対象窓、モザイクの強さ・粒度・余白を確認し、必要ならReconnectで窓を選び直します。

Text FollowはWindow Pinの固定割合座標とは別機能です。OCRは誤認識、見逃し、遅延を起こし得ます。画面遷移、スクロール、ズーム、フォント、アニメーション、重なり、低コントラスト、縦書きなどで結果が変わります。「一致あり」や表示中のモザイクは機密性を保証しません。秘密情報は可能なら元画面から除き、共有前と遷移後に実際の出力を確認してください。再起動後は、Appleの選択単位の認可を復元するためReconnectが必要になる場合があります。

Settingsの「厳格な安全モード：ウインドウ全体を保護」は既定でオンです。オンでは接続中、変更フレームの認識中、取得失敗、ウインドウ情報の一時的な欠落中に加え、完了したOCRが0一致だった場合も、デスクトップ上の現在または最後に確認できた対象ウインドウ全体を角までモザイクします。0一致は対象文字列が存在しない証明にはならないためです。同じ理由でShare Previewも、オン時の0一致結果を全面coverとして扱います。オフではデスクトップ上の直前に完了した一致位置を維持し、Share Previewでは完了した0一致結果を表示可能にするため、全面フラッシュを避けられます。その代わり、OCRの見逃し、移動・新規出現した対象は次の一致結果まで覆われない可能性があり、漏れ耐性は下がります。未接続、認識中、失敗など未確定状態のShare Previewは、この設定をオフにしても全面保護を維持します。対象の消失、別Space、identity不一致が確認できた場合は、無関係な画面を覆わないよう古いデスクトップpanelを隠します。動画やアニメーションなどで内容変更が続く間は、オン時の安全カバーやShare Previewの全面保護が継続する場合があります。

### Masks — 見た目、位置、On/Offを調整

1. Masksで対象マスクを開き、Frost / Mosaic / Redactを選びます。FrostとMosaicは効果の強さ、粒度、色味、枠線を個別に調整できます。Redactは常に不透明です。
2. 位置を変える場合は、Masksまたはメインウインドウのツールバーで対象マスクの「Move…」を押し、画面上のマスク本体をドラッグします。マウスまたはトラックパッドを離すと新しい割合座標が保存されます。保存前にEscまたは「Cancel Move」を使うと取り消せます。「Move…」は全体と対象マスクがOnで、位置を取得できている場合に使えます。
3. メインウインドウのツールバーでは、各手動マスクのサブメニューから個別のOn/OffとMoveを選べます。メニューバーのBlurFollowアイコンからは各マスクを個別にOn/Offできます。「Show Masks」はデスクトップ上の通常マスクをまとめて切り替えます。Share Previewは個別にOnのWindow Pinと、選択sourceに関連する接続済み・有効なText Followルールを使うため、別に表示を確認してください。
4. 見た目、位置、On/Offを変えた後は、通常表示と利用中のShare Preview、会議アプリ側のプレビューをもう一度確認します。

### Share Preview — 単一窓／タブ共有の代替

1. Share GuideまたはHomeで「Share Preview」を開始します。
2. Appleのシステムピッカーで元のウインドウを選びます。
3. **BlurFollow Share Preview**内に、想定したWindow Pinと、選択sourceへ接続した有効なText Followルールのすべての一致Mosaicが合成されていることを確認します。
4. 画面内の「位置を確認しました」に同意します。
5. Google Meet、Zoom、Teamsなどで、元の窓やタブではなく **BlurFollow Share Preview** を単一ウインドウ共有します。
6. 会議アプリ側のプレビューでも、範囲、スクロール後の表示、Text Followの更新を確認します。Share PreviewとText FollowのOCRは同じ選択source境界を使い、別のchild window、メニュー、シート、popoverは取り込みません。
7. 終了時は「停止」を押すか、Share Previewウインドウを閉じます。

Share PreviewはDisplay Pinやデスクトップ上の別panelを直接取り込みません。代わりに、選択sourceへ対応するWindow PinとText Followの一時的な一致座標を同じcapture frameへ描画します。同じappのWindow Pinが選択sourceか別窓かを安全に解決できない間、または関連する有効Text Followルールが未接続、再接続待ち、接続中、認識中、失敗、source unavailable、状態と一致座標が不整合な間は、直前のframeを即座に消して全面を不透明にし、「Preview paused」と表示します。保存データの復旧警告、無効なmask座標やcapture metadata、Window Pinも関連Text Followルールもない構成も同様です。

Text FollowとShare Previewは別々のcapture streamを使うため、WindowServerのframe時刻を比較します。Share Preview側の最新変更が関連ルールの最古の認識完了frameより新しい間、Preview側が関連ルールの最新認識frameまで進んでいない間、または変更情報を安全に比較できない間は、古い一致位置を合成せず全面保護を維持します。Previewの最初のsource frameでは同じ選択sourceへ新しい認識を要求し、静止画面ではidle時刻と保持中の最新sampleを使って安全条件を満たしたframeを再描画します。

関連する全Text Followルールがscanを完了していれば、各ルールのすべての一致MosaicをWindow Pinと一緒に合成します。厳格安全モードがオンなら、完了scanが0一致でもShare Previewは全面を覆います。オフなら0一致を有効な構成として現在frameを表示できますが、「一致なし」は秘密文字列が存在しないことやOCRが見逃していないことの証明ではありません。Window PinまたはText Followの位置、見た目、On/Off、認識状態、Share Previewのcapture状態が変わるたびに確認状態を解除します。現在の合成結果が表示されるまで待ち、全マスクを確認し直してください。

## 状態の読み方

| 表示 | 意味 | 利用者の操作 |
|---|---|---|
| Following / Placed | 現在の窓またはディスプレイ位置を取得し、その座標でマスクを描画中 | 共有前に実際のマスク位置を確認 |
| Checking position / Finding window | 表示位置を確認中、または対象窓を探索中 | 現在位置とLast-position coverの表示を確認 |
| Select again | 対象窓を特定できず、再接続が必要 | Reconnectで選び直し、位置を確認 |
| Last-position cover | 最後に取得した窓位置を全体カバーで表示 | 現在位置とは限らないため、共有を止めて再接続 |
| Preview active | Window Pinと完了済みText Follow結果を使える現在frameへ合成中。厳格安全モードがオフなら完了scanの0一致も含む | 全マスクと0一致の妥当性を確認し、会議アプリ側でも再確認 |
| Preview paused | 合成条件を満たさず、直前frameをclearして全面coverまたは空表示 | 共有せず、警告、source、Window Pin、関連Text Followルールの接続・認識状態を確認 |

色だけで状態を判断しないでください。「Following」や「Placed」は座標を取得できたという技術状態であり、隠したい情報とマスクが一致しているという判定ではありません。

## 保存データ

保存するもの:

- マスク名、mode、style、強さ、粒度、色味、枠線、角丸、割合座標
- 対象ディスプレイUUID
- 対象アプリ名、bundle ID、窓タイトル、窓identityの再接続情報
- Text Followのルール名、match mode、入力pattern、Mosaicの見た目、余白、有効状態
- アプリ設定

保存しないもの:

- 画面ピクセル
- Share Previewの映像frame
- 音声、録画
- 利用分析

公式Mac App Store版では、任意の「無制限マスク」の商品情報、購入、購入状態の検証、復元にAppleのStoreKitを使います。Apple Accountの認証情報や決済情報をBlurFollowが受け取ることはなく、画面内容、マスク内容、利用解析を購入処理へ渡しません。評価依頼の表示判断に使う初回利用日、Share Preview確認回数、最後に依頼した版と日時は端末内のUserDefaultsだけに保存します。

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
- Text FollowのOCRとShare Previewは、座標境界を一致させるため同じ選択sourceだけをcaptureし、child windowを除外します。別windowとして実装されたメニュー、シート、popover、通知は認識・合成されません。DRM対象コンテンツなども元アプリ／macOS側の制約を受けます。
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
- [課金・レビュー導線](Docs/MONETIZATION.md)
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
