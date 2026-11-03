# wifi-aware-playground

iOS 26以降のWi-Fi Awareを使い、2台のiPhoneをWi-Fiルーターやインターネットなしで直接つなぐ実験用リポジトリです。
最小構成として、テキストメッセージを送受信するアプリ **AwareChat** を、XcodeのGUIを使わずLinuxコンテナ内で開発します。

## 現在の状況

| 項目 | 状態 |
|---|---|
| `xtool dev build`(署名なし) | 成功 |
| 署名・プロビジョニング | 成功 |
| 実機へのインストール | iPhone 16 Proで成功 |
| ペアリング・通信 | 未検証(2台目での確認が必要) |

**2台の間の通信はまだ確認していません。** `Coder` と `TLS()` の組み合わせはAppleのサンプルにないため、実行時に動くかどうかも未確認です。

## 作業を再開する

作業の続きは、次の順で再開します。現在の状況と次にやることは [`logs/HANDOFF.md`](logs/HANDOFF.md) を確認してください。

**1. Macでコンテナを起動します。** リポジトリのディレクトリで実行します。

```sh
docker compose up -d
docker compose exec swift bash
```

Named Volumeが消えるので `docker compose down -v` は実行しないでください。`--build` を付けるとSwiftとxtoolのバージョンが変わる可能性があるので、必要なときだけ使います。

**2. コンテナ内で環境を確認します。**

```sh
xtool auth status   # Key IDが現在のものか確認
xtool sdk status    # Darwin SDKの確認
which zip           # なければ apt-get update && apt-get install -y zip
```

`zip` は実機へのインストールに必要です。`Dockerfile` には追加済みですが、リビルド前のイメージには入っていません。

**3. 実機を使うなら、Macで中継を起動します。** Node.jsが必要です。このターミナルは開いたままにします。

```sh
node scripts/usbmuxd-relay.mjs
```

**4. iPhoneをUSBで接続してロックを解除し、コンテナ内で確認します。**

```sh
xtool devices --no-wait
```

何も表示されなければ、中継の起動、USB接続、ロック解除、「このコンピュータを信頼」を確認してください。コンテナに `USBMUXD_SOCKET_ADDRESS` が設定されていない場合は、`compose.yml` の変更が反映されていないので、`docker compose up -d` で再作成するか、コマンドの前に `USBMUXD_SOCKET_ADDRESS=host.docker.internal:27015` を付けます。

**5. ビルドしてインストールします。**

```sh
cd AwareChat
xtool dev build                # 署名なしのビルド
xtool dev run -u <UDID>        # 署名してインストール
```

`xtool dev run` はApple側のApp IDやProfileを更新することがあります。

**6. 終わったら、Macの中継を `Ctrl+C` で止めます。**

## 必要なもの

- Docker(`linux/arm64` のコンテナを実行できる環境)
- Xcodeの `.xip`(Darwin SDKの生成に使用)
- Apple Developerアカウント
- iOS 26以降を入れたWi-Fi Aware対応端末2台(iPhone 12以降)

シミュレーターでは動きません。

## セットアップ

```sh
docker compose up -d --build
docker compose exec swift bash
```

`compose.yml` は、リポジトリ直下の `.p8` ファイルを `/run/secrets/apple-api-key.p8` に読み取り専用でマウントします。ファイル名は `compose.yml` の指定に合わせてください。`.p8` と `.xip` はGitの管理対象外です。

初回のみ、コンテナ内で認証とSDKの準備をします。

```sh
xtool auth login --mode key                 # Key ID、Issuer ID、Key pathを入力(パスは /run/secrets/apple-api-key.p8)
xtool sdk build <Xcode.xipのパス> <出力先>  # XcodeからDarwin SDKを生成
xtool sdk status                            # SDKの確認
```

## ビルド

```sh
cd AwareChat
xtool dev build
```

成果物は `AwareChat/xtool/AwareChat.app` に出力されます。

## 実機で試す

> iPhone 16 Proへのインストール(手順2まで)を確認済みです。手順3以降は未検証です。

事前に、Apple DeveloperのWebサイトでApp IDのWi-Fi Awareを有効にしてください。App Store Connect APIは `WIFI_AWARE` を受け付けないため、APIキー認証のxtoolでは有効にできません。初回の `xtool dev run` はこのエラーで止まりますが、その時点でApp IDは作成されています。xtoolは `XTL-<ID>.` の接頭辞が付いたIDで登録します。

1. Macで `node scripts/usbmuxd-relay.mjs` を起動し、iPhoneをUSBで接続します。コンテナ内で `xtool devices --no-wait` を実行して端末を確認します。
2. 2台それぞれにインストールします: `xtool dev run -u <UDID>`
3. 片方をHostにして「Allow Pairing」、もう片方をJoinにして「Add Device」をタップし、ペアリングします。
4. Host、Joinの順に「Start」をタップします。
5. 「Connected」と表示されたら、メッセージを送り合います。

Bundle IDは `AwareChat/xtool.yml` の `com.n0bisuke.awarechat` です。xtoolのソースでは、Apple側に登録するIDに `XTL-<ID>.` の接頭辞を付ける実装になっています。

コンテナはMacの `usbmuxd` を、`scripts/usbmuxd-relay.mjs` の中継経由で使います(`USBMUXD_SOCKET_ADDRESS`)。中継は `127.0.0.1` だけで待ち受けるのでLANには公開されません。使わないときは `Ctrl+C` で止めてください。この経路でのiPhone 16 Proへのインストールまで確認済みです。

## 構成

```text
.
├── Dockerfile / compose.yml        開発コンテナ
├── scripts/usbmuxd-relay.mjs       Macのusbmuxdをコンテナへ中継(Macで実行)
├── logs/                           引き継ぎと作業ログ
└── AwareChat/
    ├── Package.swift               SwiftPMの定義(iOS 26以降)
    ├── xtool.yml                   Bundle IDと各設定ファイルの指定
    ├── Info.plist                  WiFiAwareServicesの宣言
    ├── AwareChat.entitlements      Wi-Fi Awareのエンタイトルメント
    └── Sources/AwareChat/
        ├── AwareChatApp.swift      エントリーポイント
        ├── ContentView.swift       対応チェック、ペアリング、チャットのUI
        └── ChatSession.swift       待ち受け、検索、接続、送受信
```

## 全体構成

開発環境とiPhoneの接続です。ビルド、署名、インストールはコンテナ内のxtoolが行い、MacはiPhoneとの接続を中継します。

```text
             Apple Developer
             (App ID / Certificate / Profile)
                     ^
                     | HTTPS (API key)
+--------------------|----------------------------------------+
| Mac                |                                        |
|                    |                                        |
|  +-----------------|-------------------------------------+  |
|  | Docker container on OrbStack (Linux ARM64)            |  |
|  |                 |                                     |  |
|  |  +--------------+-----+     +---------------------+   |  |
|  |  | xtool              |---->| Swift + Darwin SDK  |   |  |
|  |  | (sign and install) |     | (build AwareChat)   |   |  |
|  |  +--------------+-----+     +---------------------+   |  |
|  |                 |                                     |  |
|  +-----------------|-------------------------------------+  |
|                    | host.docker.internal:27015             |
|                    v                                        |
|  +--------------------------------------+                   |
|  | scripts/usbmuxd-relay.mjs (Node.js)  |                   |
|  | listens on 127.0.0.1:27015           |                   |
|  +-----------------+--------------------+                   |
|                    | /var/run/usbmuxd                       |
|                    v                                        |
|  +--------------------------------------+                   |
|  | usbmuxd (macOS)                      |                   |
|  +-----------------+--------------------+                   |
|                    |                                        |
+--------------------|----------------------------------------+
                     | USB
                     v
              +-------------+
              |   iPhone    |
              +-------------+
```

アプリを入れた2台のiPhoneの通信です。Wi-Fiルーターやインターネットを介さず、Wi-Fi Awareで直接つなぎます。**この部分は未検証です。**

```text
  iPhone (Host / Publisher)            iPhone (Join / Subscriber)
+---------------------------+        +---------------------------+
| AwareChat                 |        | AwareChat                 |
|                           |  pair  |                           |
|   DevicePairingView       |<------>|   DevicePicker            |
|                           |        |                           |
|   NetworkListener         |        |   NetworkBrowser          |
|        |                  |        |        |                  |
|        v                  | connect|        v                  |
|   NetworkConnection       |<-------|   NetworkConnection       |
|                           |        |                           |
|   Coder (JSON) + TLS      |<======>|   Coder (JSON) + TLS      |
+---------------------------+  text  +---------------------------+
              ^                                    ^
              +------------ Wi-Fi Aware -----------+
                 (no router, no internet)
```

## 仕組み

| 役割 | 使うAPI | ペアリングUI |
|---|---|---|
| Host(Publisher) | `NetworkListener` + `.wifiAware` | `DevicePairingView` |
| Join(Subscriber) | `NetworkBrowser` → `NetworkConnection` | `DevicePicker` |

サービス名は `_awarechat._tcp` です。メッセージは `Coder`(JSON)+ `TLS()` で送受信します。

## 参考資料

- [Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware)
- [Adopting Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware/adopting-wi-fi-aware)
- [Connecting devices for peer-to-peer Wi-Fi](https://developer.apple.com/documentation/wifiaware/connecting-paired-devices)
- [Building peer-to-peer apps](https://developer.apple.com/documentation/wifiaware/building-peer-to-peer-apps)
