# 引き継ぎ

最終更新: 2026-11-04

再開の手順は [`README.md`](../README.md) の「作業を再開する」、作業のルールは [`AGENTS.md`](../AGENTS.md) を参照してください。

**2026-11-04時点で休止中。** 再開時は、未コミットの変更と [`BACKLOG.md`](BACKLOG.md) の「未決定」を最初に確認してください。切断対策のコードは、残すか戻すかが未決定で、未コミットです。

## 現在の状況

| 項目 | 状態 |
|---|---|
| コンテナ内のxtoolによるビルド | 成功 |
| 署名、プロビジョニング | 成功 |
| Macの中継経由でのiPhone 16 Proの認識 | 成功 |
| iPhone 16 Proへのインストール | 成功 |
| iPhone 13 miniへのインストール | 成功 |
| ペアリング | 成功 |
| 2台の間の接続、メッセージ送受信 | 成功(`TCP()` 版、ユーザーが実機で確認) |
| Wi-Fiルーターなしでの通信 | 未検証 |
| `Coder` + `TLS()` の実行時の動作 | 失敗(`-9838`) |
| `Coder` + `TCP()` の実行時の動作 | 成功 |
| `TLV` + `TCP()` への変更後の通信 | 成功 |
| 写真、お絵描き、速度テスト | 成功(ユーザーが実機で確認) |
| 電波強度と距離の目安の変化 | 未確認 |
| 数分で切れる問題の対策 | 実装済み、実機では未検証 |

## 次にやること

機能の候補や調査済みの案は [`BACKLOG.md`](BACKLOG.md) にあります。

1. **切断対策を実機で試す:** 両方に入れ直し、10分ほどつなぎっぱなしにする。切れたら、画面の「前回:」の内容で原因を確認する。2台とも同じ版が必要。
2. **Wi-Fiルーターなしで試す:** 同じLANにいる状態では、目的の確認にならない。
3. **Wi-Fi経由のインストール(任意):** 一度USBでつなぎ、Finderで「Wi-Fi接続時にこのiPhoneを表示」を有効にする(未検証)。同じLANにいるだけではコンテナから見えなかった。
4. **1台でできる確認(任意):** 診断画面を追加する案がある。未着手。
   - `WACapabilities` の上限値を表示する。
   - ペアリングなしで `NetworkListener` と `NetworkBrowser` を起動し、`WAError` を表示する。
   - `entitlementMissing` なら署名の問題、`noPairedDevices` なら相手がいないだけ、と区別できる見込み。

## 環境の状態と注意点

- **Bundle ID:** `xtool.yml` は `com.n0bisuke.awarechat`。xtoolがApple側に `XTL-<ID>.com.n0bisuke.awarechat` で登録するので、実機上のIDも接頭辞付きになる見込み。
- **APIキー:** 現在のキーでログイン済み。`compose.yml` がマウントするファイルと、xtoolのログイン情報は別に管理される。キーを再発行したら、`xtool auth login --mode key` をやり直す。
- **コンテナの再作成:** 再作成後も、xtoolの認証は残っていた。`USBMUXD_SOCKET_ADDRESS` が設定され、`/run/secrets/apple-api-key.p8` は新しいキーを指している。
- **`zip`:** 再作成で消えたので、`apt-get` で入れ直した。イメージをリビルドするまでは、再作成のたびに必要。`Dockerfile` には追加済み。
- **`Error: unknown`:** 2台接続中に `xtool dev run -u <UDID>` が接続前に2回失敗し、`--usb` を付けた1回で成功した。`--usb` が効いたのか、たまたま通ったのかは未確認。
- **接続の瞬断:** iPhone 13 miniが一時的にコンテナから見えなくなり、少し待つと戻ったことがあった。ユーザーによるとLightning端子の接触が怪しく、これが原因の可能性がある(未確定)。`Error: unknown` も同じ原因かもしれない。見えないときは数秒待ち、ケーブルを挿し直す。
- **`ideviceinfo`:** 中継経由では `Invalid HostID` で失敗した。`xtool dev run` は同じ端末で成功したので、インストールの妨げにはならなかった。
- **バージョン:** `Dockerfile` は `swift:6.4.2-noble` と xtoolの `latest`。作業中のコンテナはSwift 6.4.1、xtool 1.24.0。リビルドすると変わる可能性がある。
- **Apple Developerのチーム:** 他のメンバーの端末や証明書もあるチーム。xtoolが作るDevelopment Profileには登録済みの全端末が入る。

## 分かったこと

- **数分で切れる問題:** 原因は未確定。AppleのフォーラムのDTSの回答では、無通信の接続は閉じられる可能性があり、アプリがサスペンドされると接続が閉じる。タイムアウト時間は非公開。対策としてハートビート(10秒ごと)、45秒無通信での再接続、自動再接続、接続中の画面ロック防止、切断理由の表示を追加した。バックグラウンドでの維持は対象外。

- **`-9838`:** `errSSLPeerInternalError`。アイデンティティなしの `TLS()` を `Coder` の下に置くと、ペアリングと発見の後のハンドシェイクで失敗した。Hostに証明書がないことが原因と見ているが未確認。Appleの資料には `TLS()` だけの例がある。WWDC25のセッションは、Wi-Fi層で認証と暗号化がされると説明しているので、`TCP()` に変更した。
- **スクリーンショットの確認:** Macから `logs/tmp/` に置くと読める。`logs/tmp/` はGitの対象外。`logs/` の直下に置くと公開されるので置かない。`idevicescreenshot` は中継経由で失敗する。

- **Wi-Fi AwareのCapability:** App Store Connect APIは `WIFI_AWARE` を受け付けず、409を返す。Apple DeveloperのWebサイトでApp IDのWi-Fi Awareを有効にすると、Provisioningを通過し、Profileにエンタイトルメントが入った。
- **申請の要否:** Espressifの記事は申請が必要と書いているが、今回のチームでは申請について確認しないまま、Webサイトでの有効化で署名まで通った。
- **Macとの接続:** OrbStackのコンテナから、Macの `127.0.0.1` だけで待ち受ける中継に `host.docker.internal` で届く。LANに公開する必要はない。
- **`socat` は不要:** Node.js標準モジュールだけの `scripts/usbmuxd-relay.mjs` で動く。
- **`xtool devices`:** 既定では端末が見つかるまで待ち続ける。`--no-wait` は端末が接続中なら正しく表示する。空なら未接続か、未ロック解除か、未信頼を疑う。
- **`xtool ds teams list`:** APIキー認証では使えない。Team IDは `xtool ds certificates list` の `team id` で確認できる。
- **`xtool auth login`:** プロンプトはKey ID、Issuer ID、Key pathの順。Key pathはコンテナ内のパスを入力する。日本語入力の文字が混ざると、相対パスと解釈されて失敗する。上書きできるので `logout` は不要。
- **パイプでのログイン:** 入力をまとめて流し込むと `I/O on closed channel` で失敗する。プロンプトに合わせて間隔を空けて渡すと通る。
- **Apple公式ドキュメント:** 通常のURLは本文を取得できないことがある。末尾に `.md` を付けると取得できる。

## 検討して採用しなかったもの

- **OrbStackのUSBパススルー:** 接続中はMacからiPhoneが見えなくなる。公式のテスト済み機器にiPhoneがない。
- **`/var/run/usbmuxd` の直接マウント:** OrbStack経由で動く根拠が見つからなかった。未検証。
- **`socat`:** `brew` を使いたくなかったので、Node.jsの中継に置き換えた。
