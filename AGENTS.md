# AGENTS.md

iOS 26以降のWi-Fi Awareで2台のiPhoneを直接つなぐ実験用リポジトリです。アプリ本体は `AwareChat/` にあります。概要と利用手順は `README.md` を参照してください。

## 作業の記録

- **作業を始めるとき:** `logs/HANDOFF.md` を読み、現在の状況と次の作業を確認する。再開の手順は `README.md` の「作業を再開する」にある。
- **作業を終えるとき:** `logs/HANDOFF.md` を最新の状態に書き換え、`logs/YYYY-MM-DD.md` に実行した内容と結果を追記する。同じ日のファイルがあれば追記する。
- **長く残す知見:** 手順は `README.md`、作業のルールは `AGENTS.md`、その時点の状況と経緯は `logs/` に書く。
- **公開リポジトリ:** `logs/` もGitHubで公開される。秘密鍵、Issuer ID、Team ID、UDID、Profile ID、個人名、他メンバーの端末名、Macのユーザーパスは書かない。

## 制約

- 作成、編集、ビルドはコンテナ内で行う。Xcode GUIは使わない。
- Swift、xtool、Darwin SDKを再インストールしない。
- `*.p8` などの秘密鍵やApple Developerの認証情報を読まない、表示しない、送信しない。コミットもしない。
- Appleの公開APIだけを使う。未確認のAPIを推測で実装しない。
- 次の操作はユーザーに確認してから行う。
  - `xtool dev build --sign`、`xtool dev run`、`xtool ds`(Developerアカウントや実機に変更が及ぶ可能性がある)
  - コミットとプッシュ

## コマンド

```sh
cd AwareChat
xtool dev build             # 署名なしビルド(出力先: xtool/AwareChat.app)
xtool devices --no-wait     # 端末一覧
xtool sdk status            # SDKの状態
```

`xtool devices` は既定で端末が見つかるまで待ち続けるので、`--no-wait` を付けてください。

端末の認識には、Macで `node scripts/usbmuxd-relay.mjs` を起動しておく必要があります。コンテナに `USBMUXD_SOCKET_ADDRESS` がなければ、`USBMUXD_SOCKET_ADDRESS=host.docker.internal:27015` をコマンドの前に付けてください。

`swift build` ではなく `xtool dev build` を使ってください。テストターゲットはまだないため、確認の基本はビルドの成功です。

## APIの調べ方

次の順で一次情報を確認します。

1. **SDKの `.swiftinterface`:** 実際に使えるシグネチャと `@available` を確認する。

   ```text
   /root/.swiftpm/swift-sdks/darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/<Framework>.framework/Modules/<Framework>.swiftmodule/arm64e-apple-ios.swiftinterface
   ```

   SwiftUIの `DevicePicker` と `DevicePairingView` は `_DeviceDiscoveryUI_SwiftUI.framework` にあります。

2. **Apple公式ドキュメント:** developer.apple.comの通常のURLは本文を取得できないことがあります。末尾に `.md` を付けると取得できます(例: `.../documentation/wifiaware/adopting-wi-fi-aware.md`)。

SDKはiOS 27.2までのAPIを含みますが、最小OSはiOS 26.0です。iOS 26.4や27.0で追加されたAPIを使う場合は、`#available` で囲んでください。

## 変更時の注意

- **サービス名:** `_awarechat._tcp` は `Info.plist` のキーと `ChatSession.swift` の `chatServiceName` で一致させる。無効な名前や宣言漏れは、実行時のクラッシュにつながる。
- **サービスの宣言:** 各サービスに `Publishable` か `Subscribable` の少なくとも一方が必要。ないとクラッシュする。
- **エンタイトルメント:** 使う役割に合わせて `AwareChat.entitlements` の `Publish` と `Subscribe` を設定する。
- **両端の設定:** プロトコルスタックは `makeProtocolStack()` で共通化している。性能モードを変える場合も、ListenerとConnectionで同じ値にする(不一致時の動作は未定義)。
- **並行処理:** `ChatSession` は `@MainActor`。Swift 6の厳格な並行性チェックで警告を出さない状態を保つ。

## 検証状況

ビルド成功は、実機で動くことを意味しません。報告では、確認済みの内容と未確認の内容を分けてください。

- **確認済み:** コンテナ内のxtoolによるビルド、署名、プロビジョニング、中継経由のiPhone 16 Proへのインストール。Profileへの `com.apple.developer.wifi-aware` の反映。
- **未確認:** ペアリング、2台の間の通信、`Coder` + `TLS()` の実行時の動作。
- **Capability:** App Store Connect APIは `WIFI_AWARE` を受け付けない(409)。APIキー認証では、Apple DeveloperのWebサイトでApp IDに有効化しておく必要がある。
- **Bundle ID:** `xtool.yml` の `bundleID` は `com.n0bisuke.awarechat`。生成物ではなくこのファイルを変更する。xtoolのソースでは、Apple側に登録するIDに `XTL-<ID>.` の接頭辞を付ける実装になっている。
- **APIキー認証:** `xtool ds teams list` はパスワード認証専用で使えない。Team IDは `xtool ds profiles list` の `team identifiers` などで確認する。
