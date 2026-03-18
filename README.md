# AstroPotatoChatPhone

LocalLLMClient (Swift + XcodeGen + SPM) を使って、iPhone 上でローカル LLM を動かす最小構成のチャットアプリです。

## 仕様
- Bundle ID: `com.aoiastro.apcp`
- iOS: 17.0+
- LLM: `Qwen/Qwen2.5-1.5B-Instruct-GGUF`
- 量子化: `qwen2.5-1.5b-instruct-q4_k_m.gguf`（初回起動時に HF からダウンロード）

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

## GitHub Actions (署名なしビルド)
`.github/workflows/unsigned-build.yml` で、XcodeGen → 署名なしビルド → `.ipa` 生成まで実行します。
AltStore 用にあとから署名する前提の `.ipa` です。

## 注意
- LocalLLMClient は experimental です。API 変更の可能性があります。
- 大きなモデルを安定して動かすにはメモリ制限緩和のエンタイトルメントが必要な場合があります。

