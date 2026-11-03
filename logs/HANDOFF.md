# 引き継ぎ

最終更新: 2026-11-03

再開の手順は [`README.md`](../README.md) の「作業を再開する」、作業のルールは [`AGENTS.md`](../AGENTS.md) を参照してください。

## 現在の状況

| 項目 | 状態 |
|---|---|
| コンテナ内のxtoolによるビルド | 成功 |
| 署名、プロビジョニング | 成功 |
| Macの中継経由でのiPhone 16 Proの認識 | 成功 |
| iPhone 16 Proへのインストール | 成功 |
| 2台目へのインストール | 未実施(ケーブルがない) |
| ペアリング、2台の間の通信 | 未検証 |
| Wi-Fiルーターなしでの通信 | 未検証 |
| `Coder` + `TLS()` の実行時の動作 | 未検証 |

## 次にやること

1. **2台目を用意する:** iPhone 13用のケーブルを用意し、USBでインストールする。同じLANにいるだけではコンテナから見えなかった。
   - Wi-Fi経由にする場合は、一度USBでつなぎ、Finderで「Wi-Fi接続時にこのiPhoneを表示」を有効にする(未検証)。
   - Apple Developerに登録済みなのは `iPhone 13 mini`。無印のiPhone 13なら、新規登録とProfileの再作成が発生する。
2. **2台で通信を試す:** Hostで「Allow Pairing」、Joinで「Add Device」をタップしてペアリングする。Host、Joinの順に「Start」をタップし、メッセージを送り合う。
3. **Wi-Fiルーターなしで試す:** 同じLANにいる状態では、目的の確認にならない。
4. **1台でできる確認(任意):** 診断画面を追加する案がある。未着手。
   - `WACapabilities` の上限値を表示する。
   - ペアリングなしで `NetworkListener` と `NetworkBrowser` を起動し、`WAError` を表示する。
   - `entitlementMissing` なら署名の問題、`noPairedDevices` なら相手がいないだけ、と区別できる見込み。

## 環境の状態と注意点

- **Bundle ID:** `xtool.yml` は `com.n0bisuke.awarechat`。xtoolがApple側に `XTL-<ID>.com.n0bisuke.awarechat` で登録するので、実機上のIDも接頭辞付きになる見込み。
- **APIキー:** 現在のキーでログイン済み。`compose.yml` がマウントするファイルと、xtoolのログイン情報は別に管理される。キーを再発行したら、`xtool auth login --mode key` をやり直す。
- **再作成が未確認:** 2026-11-03の作業は再作成前のコンテナで行った。次の点は再作成後に確認する。
  - xtoolの認証がNamed Volumeから引き継がれるか(`xtool auth status`)
  - `USBMUXD_SOCKET_ADDRESS` が設定されるか
  - `/run/secrets/apple-api-key.p8` が新しいキーを指すか
- **`zip`:** 作業中のコンテナに `apt-get` で直接入れたので、再作成すると消える。`Dockerfile` には追加済み。
- **バージョン:** `Dockerfile` は `swift:6.4.2-noble` と xtoolの `latest`。作業中のコンテナはSwift 6.4.1、xtool 1.24.0。リビルドすると変わる可能性がある。
- **Apple Developerのチーム:** 他のメンバーの端末や証明書もあるチーム。xtoolが作るDevelopment Profileには登録済みの全端末が入る。

## 分かったこと

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
