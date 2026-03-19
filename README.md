# AstroPotatoChatPhone

LocalLLMClient (Swift + XcodeGen + SPM) を使って、iPhone 上でローカル LLM を動かす最小構成のチャットアプリです。

## 仕様
- Bundle ID: `com.aoiastro.apcp`
- iOS: 17.0+
- LLM: `Qwen/Qwen2.5-1.5B-Instruct-GGUF`
- 量子化: `qwen2.5-1.5b-instruct-q4_k_m.gguf`（初回起動時に HF からダウンロード）
- Tool Calling 記憶: `remember_user_fact` / `recall_user_fact` / `search_user_memory`
- 音声モード: 音声入力（Speech）+ 返答読み上げ（AVSpeechSynthesizer）

## セットアップ
1. XcodeGen でプロジェクト生成
   ```bash
   xcodegen
   ```
2. `AstroPotatoChatPhone.xcodeproj` を開く
3. 実機で実行（初回にモデルをダウンロード）

## モデル差し替え
`App/ChatViewModel.swift` の `id` と `model` を変更してください。

```swift
let model = LLMSession.DownloadModel.llama(
    id: "Qwen/Qwen2.5-1.5B-Instruct-GGUF",
    model: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
    parameter: .init(
        temperature: 0.7,
        topK: 40,
        topP: 0.9
    )
)
```

## Tool Calling 記憶機能
このアプリは LocalLLMClient の Tool Calling を使って、会話中のユーザー情報を保存・参照します。

- 保存: `remember_user_fact`
- キー参照: `recall_user_fact`
- あいまい検索: `search_user_memory`

保存先は `UserDefaults`（キー: `apcp.memory.v1`）です。

## 音声モード
- `Voice On/Off` ボタンで権限取得と音声モード切り替え
- `Mic` ボタンで音声入力を開始/停止
- アシスタント応答は音声モード中に自動読み上げ
- 音声入力中は無音を約1.2秒検知すると自動で送信（ハンズフリー入力）
- 読み上げ完了後は自動で再リスニング開始（連続会話）

## GitHub Actions (署名なしビルド)
`.github/workflows/unsigned-build.yml` で、XcodeGen → 署名なしビルド → `.ipa` 生成まで実行します。
AltStore 用にあとから署名する前提の `.ipa` です。

## 注意
- LocalLLMClient は experimental です。API 変更の可能性があります。
- 大きなモデルを安定して動かすにはメモリ制限緩和のエンタイトルメントが必要な場合があります。
