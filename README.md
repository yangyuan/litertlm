# litertlm
Native LiteRT-LM bindings for Flutter across mobile, desktop, and web.

Pub Package: https://pub.dev/packages/litertlm

API Reference: https://pub.dev/documentation/litertlm/latest/

Live Example Flutter Project: https://github.com/yangyuan/agentic-lite

Powered by LiteRT-LM v0.17.0.

## Overview
This package is a lightweight bridge to the official LiteRT-LM runtimes. It uses each platform's optimized distribution, providing the same hardware acceleration and capabilities, including the Swift package on iOS and macOS, the Maven artifact on Android, and CLI distribution on Windows.

## Platform Support
| Platform | Runtime artifact | Integration |
| --- | --- | --- |
| iOS | Official Swift package | FFI |
| Android | Official Maven artifact | JNI |
| macOS | Official Swift package | FFI |
| Windows* | Official CLI distribution | FFI |
| Linux | Official CLI distribution | FFI |
| Web | Official NPM package | JS interop |

**Note:** Windows ARM64 is not currently supported because there is no official upstream package available.

## Usage

### Installation
```
$ flutter pub add litertlm
```

### Prepare Model
You can download `.litertlm` models from [LiteRT Community on Hugging Face](https://huggingface.co/litert-community) or other distributors. Models such as Gemma 4 E2B/E4B are great starting points and run on most devices and platforms, including web.

**Note:** LiteRT-LM expects a valid file path or URL. Flutter asset identifiers are not directly supported. On some platforms, assets are bundled into the app package and may be subject to size limits such as 1 GB. In general, `.litertlm` model files are not a good fit for Flutter assets.

### Basic Inference
1. Create and initialize `Engine`.

```dart
final engine = Engine(
  engineConfig: const EngineConfig(
    modelPath: '/path/to/model.litertlm',
    backend: Backend.gpu(),
  ),
);

await engine.initialize();
```

2. Create a `Conversation`.

```dart
final conversation = await engine.createConversation(
  ConversationConfig(
    systemMessage: Message.system('You are concise and helpful.'),
  ),
);
```

3. Send a `Message` and read the response.

```dart
final response = await conversation.sendMessage(
  Message.user('Write one sentence about Flutter.'),
);

print(response.text);
```

4. Dispose native resources.

```dart
await conversation.dispose();
await engine.dispose();
```

### Streaming

There are two ways to get streaming responses.

Use `sendMessageStream` and iterate over `Stream<Message>`.

```dart
final text = StringBuffer();

await for (final chunk in conversation.sendMessageStream(
  Message.user('Tell me a long story.'),
)) {
  text.write(chunk.text);
}

print(text);
```

Use `sendMessageWithCallback` for better control of lifecycle.

```dart
final callbackText = StringBuffer();

final callback = MessageCallback.from(
  onMessage: (message) {
    callbackText.write(message.text);
  },
  onDone: () {
    print(callbackText);
  },
  onError: (error, stackTrace) {
    print(error);
  },
);

await conversation.sendMessageWithCallback(
  Message.user('Tell me a long story.'),
  callback,
);
```

### Message

The examples above use `Message.text`, a convenience getter for common text-only responses. For agent-style workflows, inspect the structured fields on `Message` directly. `contents` preserves multimodal content, and `toolCalls` exposes model-requested tool invocations.

A real-life message might look like this:

```dart
Message(
  role: Role.model,
  contents: Contents([
    Content.text('Let me check the weather in Seattle.'),
  ]),
  toolCalls: [
    ToolCall(
      name: 'get_weather',
      arguments: {'city': 'Seattle'},
    ),
  ],
);
```

### Multimodal

Use `Contents` with multiple `Content` values for text, image, and audio inputs. File paths are passed through to the native runtime.

```dart
final conversation = await engine.createConversation();

final response = await conversation.sendMessage(
  Message.userContents(
    Contents([
      Content.text('Describe this image.'),
      Content.imageFile('/path/to/photo.jpg'),
    ]),
  ),
);

print(response.text);
```

You can also pass in-memory bytes:

```dart
final response = await conversation.sendMessage(
  Message.userContents(
    Contents([
      Content.text('Transcribe this audio.'),
      Content.audioBytes(audioBytes),
    ]),
  ),
);
```

### Tool Use
Define tools by implementing `Tool`.

```dart
class WeatherTool implements Tool {
  @override
  Map<String, Object?> getToolDescription() {
    return {
      'type': 'function',
      'function': {
        'name': 'get_weather',
        'description': 'Gets the current weather for a city.',
        'parameters': {
          'type': 'object',
          'properties': {
            'city': {'type': 'string'},
          },
          'required': ['city'],
        },
      },
    };
  }

  @override
  Future<Object?> execute(Map<String, Object?> arguments) async {
    final city = arguments['city'];
    return {'city': city, 'condition': 'sunny', 'temperature_c': 22};
  }
}
```

Create a `Conversation` with the tools. Automatic tool calling is enabled by default.

```dart
final conversation = await engine.createConversation(
  ConversationConfig(
    tools: [WeatherTool()],
  ),
);

final response = await conversation.sendMessage(
  Message.user('What is the weather in Seattle?'),
);

print(response.text);
```

To handle tool calls yourself, disable automatic tool calling and inspect `response.toolCalls`.

### Tool Call Streaming

For supported models, tool-call streaming can be enabled.

```dart
ExperimentalFlags.enableConversationToolCallStreaming = true;

final conversation = await engine.createConversation(
  ConversationConfig(
    automaticToolCalling: false,
    tools: [WeatherTool()],
  ),
);

final toolCallContent = StringBuffer();

await for (final message in conversation.sendMessageStream(
  Message.user('What is the weather in Seattle?'),
)) {
  final fragment = message.channels['tool_call'];
  if (fragment != null) {
    toolCallContent.write(fragment);
  }
}
```

The `tool_call` channel emits consecutive pieces of the raw tool-call content.
The format depends on LiteRT-LM's internal data processor and is not currently unified across models.
For Gemma 4, expect a format such as `call:get_weather{city:<|"|>Mountain View<|"|>}`, where `<|"|>` is the quote separator token. Other models might emit different formats.
After the fragments, a later message contains the complete parsed `ToolCall` in `Message.toolCalls`.

### ExperimentalFlags
`ExperimentalFlags` provides switches for experimental runtime behavior. The upstream Kotlin SDK exposes `ExperimentalFlags` as global runtime flags. To provide consistent behavior across platforms, `litertlm` follows the same design for `ExperimentalFlags`.

Supported `ExperimentalFlags`:
* `enableBenchmark`: Enables benchmark collection for engines created after the flag is set.
* `enableConversationConstrainedDecoding`: Enables constrained decoding for conversations created after the flag is set.
* `enableConversationToolCallStreaming`: Enables tool-call token streaming for subsequently created conversations.
* `enableSpeculativeDecoding`: Controls speculative decoding for engines created after the flag is set. `null` uses the model default, `true` enables it, and `false` disables it.
* `conversationToolCallStreamingChannelName`: Sets the channel name for streamed tool-call tokens.
* `filterChannelContentFromKvCache`: Controls whether channel content is filtered from the KV cache. `null` uses the runtime or model default.
* `visualTokenBudget`: The visual token budget.

## Troubleshooting

### LiteRtLmException
LiteRT-LM depends heavily on device hardware, runtime support, and model capabilities. Even when the APIs are used correctly, some actions may fail because of the user's hardware or model selection. Upstream LiteRT-LM may fail silently while logging the underlying issue in native logs. Since those logs are not practical to catch and handle internally, this package throws `LiteRtLmException` when LiteRT-LM clearly refuses to work. Developers can set `LogSeverity` to inspect detailed device logs. It is recommended to catch `LiteRtLmException` around the engine lifecycle and handle it as a recoverable runtime failure.

### LiteRtLmNativeException, LiteRtLmOutOfMemoryException

`LiteRtLmNativeException` is thrown when a native exception occurs while creating an engine, conversation, or session. `LiteRtLmOutOfMemoryException` is a specialized subtype for native memory allocation failures. Both extend `LiteRtLmException`. After catching either exception, dispose the engine instead of reusing it.

### UnsupportedError
LiteRT-LM is under fast development, and not all features are immediately available on every platform. This package throws `UnsupportedError` when the selected platform runtime does not support the requested feature.
