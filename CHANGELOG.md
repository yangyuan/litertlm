## 0.0.14

* Updated LiteRT-LM runtime dependencies across supported platforms to v0.17.0.
* Updated the Android JNI engine guard for the added maximum-vision-token argument.
* Aligned native `ExperimentalFlags.visualTokenBudget` initialization with the upstream engine-level limit.

## 0.0.13

* Added `LiteRtLmNativeException` and `LiteRtLmOutOfMemoryException` to report native failures during engine, conversation, and session creation.

## 0.0.12

* Updated LiteRT-LM runtime dependencies across supported platforms to v0.15.0.
* Aligned FFI streaming callbacks with the v0.15.0 opaque stream-chunk ABI.
* Changed `ExperimentalFlags.filterChannelContentFromKvCache` to `bool?`; `null` uses the upstream runtime or model default.
* Added Android support for conversation-level and per-send `maxOutputTokens`.

## 0.0.11

* Updated the iOS and macOS dependencies after upstream replaced the LiteRT-LM v0.14.0 binary artifacts in place.
* Aligned iOS and macOS streaming callbacks with the replacement artifacts.

## 0.0.10

* Added Web support for conversation token counts and benchmark information.
* Added opt-in native tool-call token streaming.
* Added native CPU thread-count configuration.
* Added `maxOutputTokens` to `Conversation.sendMessage`, `Conversation.sendMessageStream`, and `Conversation.sendMessageWithCallback`.
* Added `Conversation.renderPreface` for native platforms.
* Fixed FFI serialization of `ConversationConfig.systemMessage`.

## 0.0.9

* Updated native runtime dependencies to LiteRT-LM v0.14.0.
* Added platform-specific FFI compatibility for the v0.14.0 streaming callback ABI differences.

## 0.0.8

* Improved WASM compatibility.

## 0.0.7

* Added `MessageCallback.onMessageDone` for message boundaries.
* Updated `Conversation.sendMessageStream` to emit an empty message at native message-generation boundaries.
* Added `SessionConfig.maxOutputTokens` and `SessionConfig.applyPromptTemplateInSession` for supported platforms.
* Added `ExperimentalFlags.filterChannelContentFromKvCache` and `ExperimentalFlags.visualTokenBudget`.

## 0.0.6

* Added `ExperimentalFlags` with `enableBenchmark`, `enableSpeculativeDecoding`, `enableConversationConstrainedDecoding`.

## 0.0.5

* Added callback-style conversation streaming.

## 0.0.4

* Added `maxNumImages` for `EngineConfig`.
* Added `Channel` for supported platforms.
* Added `Session`, `SessionConfig`, and advanced session control.
* Added model capabilities check.
* Added benchmark support.
* Improved `Backend` control.

## 0.0.3

* Improved `ConversationConfig`, `Tool` with Swift/Java matching contract.
* Improved tool call support.
* Added document for public contract.

## 0.0.2

* Initial release with experimental support for all platforms.
