import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../litertlm/benchmark.dart';
import '../litertlm/config.dart';
import '../litertlm/exceptions.dart';
import '../litertlm/message.dart';
import '../litertlm/runtime.dart';
import '../litertlm/session.dart';
import 'runtime.dart';

const _sdkModuleUrl =
    'https://cdn.jsdelivr.net/npm/@litert-lm/core@0.17.0/+esm';
const _sdkLoadTimeout = Duration(seconds: 30);
const _samplerTypeTopP = 2;
const _unavailableInitTimeInSecond = 0.0;

/// Creates the web native runtime.
LiteRtLmNativeRuntime createRuntime() => _LiteRtLmWebRuntime();

class _LiteRtLmWebRuntime implements LiteRtLmNativeRuntime {
  Future<JSObject>? _sdkModule;

  @override
  bool enableBenchmark = false;

  @override
  bool? enableSpeculativeDecoding;

  @override
  bool enableConversationConstrainedDecoding = false;

  @override
  bool enableConversationToolCallStreaming = false;

  @override
  String conversationToolCallStreamingChannelName = 'tool_call';

  @override
  bool? filterChannelContentFromKvCache;

  @override
  int? visualTokenBudget;

  @override
  EngineHandle createEngine(EngineConfig config) {
    if (config.visionBackend != null) {
      throw UnsupportedError(
        'visionBackend is not supported by the LiteRT-LM JS SDK.',
      );
    }
    if (config.audioBackend != null) {
      throw UnsupportedError(
        'audioBackend is not supported by the LiteRT-LM JS SDK.',
      );
    }
    if (config.cacheDir != null && config.cacheDir!.isNotEmpty) {
      throw UnsupportedError(
        'cacheDir is not supported by the LiteRT-LM JS SDK.',
      );
    }
    if (config.loraRank != null) {
      throw UnsupportedError(
        'loraRank is not supported by the LiteRT-LM JS SDK.',
      );
    }
    if (config.audioLoraRank != null) {
      throw UnsupportedError(
        'audioLoraRank is not supported by the LiteRT-LM JS SDK.',
      );
    }
    if (config.maxNumImages != null) {
      throw UnsupportedError(
        'maxNumImages is not supported by the LiteRT-LM JS SDK.',
      );
    }
    final benchmarkEnabled = enableBenchmark;
    final speculativeDecodingEnabled = enableSpeculativeDecoding;
    if (speculativeDecodingEnabled != null) {
      throw UnsupportedError(
        'ExperimentalFlags.enableSpeculativeDecoding is not supported by the LiteRT-LM JS SDK.',
      );
    }

    final jsEngine = _loadSdk()
        .timeout(
          _sdkLoadTimeout,
          onTimeout: () => throw const LiteRtLmException(
            'Timed out loading the LiteRT-LM JS SDK.',
          ),
        )
        .then((sdk) {
          final settings = <String, Object?>{
            'model': config.modelPath,
            'backend': _backendValue(sdk, config.backend),
          };

          final mainExecutorSettings = <String, Object?>{};
          final maxNumTokens = config.maxNumTokens;
          if (maxNumTokens != null) {
            mainExecutorSettings['maxNumTokens'] = maxNumTokens;
          }
          final threadCount = switch (config.backend) {
            CpuBackend(:final threadCount) => threadCount,
            _ => null,
          };
          if (threadCount != null) {
            mainExecutorSettings['backendConfig'] = {
              'kv_increment_size': 16,
              'prefill_chunk_size': -1,
              'number_of_threads': threadCount,
            };
          }
          if (benchmarkEnabled) {
            settings['benchmarkEnabled'] = true;
          }
          if (mainExecutorSettings.isNotEmpty) {
            settings['mainExecutorSettings'] = mainExecutorSettings;
          }

          final engineConstructor = sdk.getProperty<JSObject>('Engine'.toJS);
          return _promiseToFuture<JSObject>(
            engineConstructor.callMethod<JSPromise<JSObject>>(
              'create'.toJS,
              _parseJson(jsonEncode(settings)),
            ),
          );
        });
    return _WebEngineHandle(jsEngine);
  }

  @override
  CapabilitiesHandle createCapabilities(String modelPath) {
    throw UnsupportedError(
      'Capabilities is not supported by the LiteRT-LM JS SDK.',
    );
  }

  @override
  bool hasSpeculativeDecodingSupport(CapabilitiesHandle capabilities) {
    throw UnsupportedError(
      'Capabilities is not supported by the LiteRT-LM JS SDK.',
    );
  }

  @override
  void deleteCapabilities(CapabilitiesHandle capabilities) {}

  @override
  Future<BenchmarkInfo> benchmark(
    EngineConfig config, {
    required int prefillTokens,
    required int decodeTokens,
  }) async {
    throw UnsupportedError(
      'benchmark is not supported by the LiteRT-LM JS SDK.',
    );
  }

  @override
  Future<void> initializeEngine(EngineHandle engine) async {
    await (engine as _WebEngineHandle).engine;
  }

  @override
  Future<ConversationHandle> createConversation(
    EngineHandle engine,
    ConversationConfig config,
  ) async {
    if (enableConversationToolCallStreaming) {
      throw UnsupportedError(
        'ExperimentalFlags.enableConversationToolCallStreaming is not supported by the LiteRT-LM JS SDK.',
      );
    }
    final conversationConstrainedDecodingEnabled =
        enableConversationConstrainedDecoding;
    final filterChannelContentFromKvCache =
        this.filterChannelContentFromKvCache;
    final jsEngine = await (engine as _WebEngineHandle).engine;
    final jsConfig = _conversationConfigToJs(
      config,
      enableConversationConstrainedDecoding:
          conversationConstrainedDecodingEnabled,
      filterChannelContentFromKvCache: filterChannelContentFromKvCache,
    );
    final conversation = await _promiseToFuture<JSObject>(
      jsEngine.callMethod<JSPromise<JSObject>>(
        'createConversation'.toJS,
        jsConfig,
      ),
    );
    return _WebConversationHandle(conversation);
  }

  @override
  Future<SessionHandle> createSession(
    EngineHandle engine,
    SessionConfig config,
  ) async {
    final jsEngine = await (engine as _WebEngineHandle).engine;
    final session = await _promiseToFuture<JSObject>(
      jsEngine.callMethod<JSPromise<JSObject>>(
        'createSession'.toJS,
        _sessionConfigToJs(config),
      ),
    );
    return _WebSessionHandle(session);
  }

  @override
  Future<Message> sendMessage(
    ConversationHandle conversation,
    String messageJson, {
    String? extraContextJson,
    int? maxOutputTokens,
  }) async {
    if (maxOutputTokens != null) {
      throw UnsupportedError(
        'Per-send maxOutputTokens is not supported by the LiteRT-LM JS SDK.',
      );
    }
    if (visualTokenBudget != null) {
      throw UnsupportedError(
        'ExperimentalFlags.visualTokenBudget is not supported by the LiteRT-LM JS SDK.',
      );
    }
    if (extraContextJson != null) {
      throw UnsupportedError(
        'Per-message extraContext is not supported by the LiteRT-LM JS SDK. '
        'Use ConversationConfig.extraContext on web.',
      );
    }
    final jsConversation = conversation as _WebConversationHandle;
    final response = await _promiseToFuture<JSObject>(
      jsConversation.conversation.callMethod<JSPromise<JSObject>>(
        'sendMessage'.toJS,
        _parseJson(messageJson),
      ),
    );
    return Message.fromJsonString(_stringifyJson(response));
  }

  @override
  Future<void> sendMessageWithCallback(
    ConversationHandle conversation,
    String messageJson, {
    String? extraContextJson,
    int? maxOutputTokens,
    required void Function(Message message) onMessage,
    required void Function() onDone,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) async {
    JSObject? streamReader;
    try {
      if (maxOutputTokens != null) {
        throw UnsupportedError(
          'Per-send maxOutputTokens is not supported by the LiteRT-LM JS SDK.',
        );
      }
      if (visualTokenBudget != null) {
        throw UnsupportedError(
          'ExperimentalFlags.visualTokenBudget is not supported by the LiteRT-LM JS SDK.',
        );
      }
      if (extraContextJson != null) {
        throw UnsupportedError(
          'Per-message extraContext is not supported by the LiteRT-LM JS SDK. '
          'Use ConversationConfig.extraContext on web.',
        );
      }
      final jsConversation = conversation as _WebConversationHandle;
      streamReader = _messageStreamReader(
        jsConversation.conversation,
        _parseJson(messageJson),
      );
      jsConversation.streamReader = streamReader;
      await _pumpMessageStream(streamReader, onMessage);
      onDone();
    } catch (error, stackTrace) {
      onError(error, stackTrace);
      rethrow;
    } finally {
      if (conversation is _WebConversationHandle &&
          identical(conversation.streamReader, streamReader)) {
        conversation.streamReader = null;
      }
    }
  }

  @override
  void cancelConversation(ConversationHandle conversation) {
    final handle = conversation as _WebConversationHandle;
    final reader = handle.streamReader;
    if (reader != null) {
      _ignoreJsPromise(reader.callMethod<JSPromise<JSAny?>>('cancel'.toJS));
      handle.streamReader = null;
    }
    handle.conversation.callMethod<JSAny?>('cancel'.toJS);
  }

  @override
  Future<void> runSessionPrefill(
    SessionHandle session,
    List<InputData> inputData,
  ) async {
    final handle = session as _WebSessionHandle;
    await _promiseToFuture<JSAny?>(
      handle.session.callMethod<JSPromise<JSAny?>>(
        'runPrefill'.toJS,
        _parseJson(jsonEncode(_inputDataToWebTextList(inputData))),
      ),
    );
  }

  @override
  Future<String> runSessionDecode(SessionHandle session) async {
    final handle = session as _WebSessionHandle;
    final responses = await _promiseToFuture<JSObject>(
      handle.session.callMethod<JSPromise<JSObject>>('runDecode'.toJS),
    );
    return _responsesFirstText(responses);
  }

  @override
  Future<String> generateSessionContent(
    SessionHandle session,
    List<InputData> inputData,
  ) async {
    await runSessionPrefill(session, inputData);
    return runSessionDecode(session);
  }

  @override
  Stream<String> generateSessionContentStream(
    SessionHandle session,
    List<InputData> inputData,
  ) {
    return Stream.error(
      UnsupportedError(
        'Session.generateContentStream is not supported by the LiteRT-LM JS SDK.',
      ),
    );
  }

  @override
  void cancelSession(SessionHandle session) {
    final handle = session as _WebSessionHandle;
    handle.session.callMethod<JSAny?>('cancel'.toJS);
  }

  @override
  Future<int> getTokenCount(ConversationHandle conversation) async {
    final handle = conversation as _WebConversationHandle;
    final tokenCount = await _promiseToFuture<JSNumber>(
      handle.conversation.callMethod<JSPromise<JSNumber>>('getTokenCount'.toJS),
    );
    return tokenCount.toDartInt;
  }

  @override
  Future<BenchmarkInfo> getBenchmarkInfo(
    ConversationHandle conversation,
  ) async {
    final handle = conversation as _WebConversationHandle;
    final info = await _promiseToFuture<JSObject>(
      handle.conversation.callMethod<JSPromise<JSObject>>(
        'getBenchmarkInfo'.toJS,
      ),
    );
    return BenchmarkInfo(
      initTimeInSecond: _unavailableInitTimeInSecond,
      timeToFirstTokenInSecond: info
          .getProperty<JSNumber>('timeToFirstTokenInSecond'.toJS)
          .toDartDouble,
      lastPrefillTokenCount: info
          .getProperty<JSNumber>('lastPrefillTokenCount'.toJS)
          .toDartInt,
      lastDecodeTokenCount: info
          .getProperty<JSNumber>('lastDecodeTokenCount'.toJS)
          .toDartInt,
      lastPrefillTokensPerSecond: info
          .getProperty<JSNumber>('lastPrefillTokensPerSecond'.toJS)
          .toDartDouble,
      lastDecodeTokensPerSecond: info
          .getProperty<JSNumber>('lastDecodeTokensPerSecond'.toJS)
          .toDartDouble,
    );
  }

  @override
  Future<String> renderMessageIntoString(
    ConversationHandle conversation,
    String messageJson,
  ) async {
    throw UnsupportedError(
      'renderMessageIntoString is not supported by the LiteRT-LM JS SDK.',
    );
  }

  @override
  Future<String> renderPreface(ConversationHandle conversation) async {
    throw UnsupportedError(
      'renderPreface is not supported by the LiteRT-LM JS SDK.',
    );
  }

  @override
  void deleteConversation(ConversationHandle conversation) {
    final handle = conversation as _WebConversationHandle;
    _ignoreJsPromise(
      handle.conversation.callMethod<JSPromise<JSAny?>>('delete'.toJS),
    );
  }

  @override
  void deleteSession(SessionHandle session) {
    final handle = session as _WebSessionHandle;
    _ignoreJsPromise(
      handle.session.callMethod<JSPromise<JSAny?>>('delete'.toJS),
    );
  }

  @override
  void deleteEngine(EngineHandle engine) {
    final handle = engine as _WebEngineHandle;
    unawaited(
      handle.engine.then((jsEngine) {
        _ignoreJsPromise(jsEngine.callMethod<JSPromise<JSAny?>>('delete'.toJS));
      }),
    );
  }

  @override
  void setMinimumLogLevel(LogSeverity severity) {
    throw UnsupportedError(
      'setMinimumLogLevel is not supported on web because the LiteRT-LM JS SDK '
      'does not expose log-level configuration.',
    );
  }

  Future<JSObject> _loadSdk() {
    final existing = globalContext.getProperty<JSObject?>('litertlm'.toJS);
    if (existing != null) {
      return Future.value(existing);
    }

    return _sdkModule ??= _importSdkModule();
  }

  Future<JSObject> _importSdkModule() async {
    final importer = _newFunction(
      'specifier'.toJS,
      '''
const timeoutMs = ${_sdkLoadTimeout.inMilliseconds};
return Promise.race([
  import(specifier),
  new Promise((_, reject) => setTimeout(
    () => reject(new Error(
      'Timed out importing ' + specifier + ' after ' + timeoutMs + 'ms'
    )),
    timeoutMs
  )),
]);
'''
          .toJS,
    );
    return _promiseToFuture<JSObject>(
      importer.callAsFunction(null, _sdkModuleUrl.toJS) as JSPromise<JSObject>,
    );
  }

  int _backendValue(JSObject sdk, Backend backend) {
    final backends = sdk.getProperty<JSObject>('Backend'.toJS);
    return switch (backend) {
      CpuBackend() => backends.getProperty<JSNumber>('CPU'.toJS).toDartInt,
      GpuBackend() =>
        backends.getProperty<JSNumber>('GPU_ARTISAN'.toJS).toDartInt,
      NpuBackend() => throw UnsupportedError(
        'NPU backend is not supported by the LiteRT-LM JS SDK.',
      ),
    };
  }

  JSObject _parseJson(String value) {
    final json = globalContext.getProperty<JSObject>('JSON'.toJS);
    return json.callMethod<JSObject>('parse'.toJS, value.toJS);
  }

  JSObject _conversationConfigToJs(
    ConversationConfig config, {
    required bool enableConversationConstrainedDecoding,
    required bool? filterChannelContentFromKvCache,
  }) {
    final dartSessionConfig = config.sessionConfig;
    final loraConfig = dartSessionConfig?.loraConfig;
    if (loraConfig?.loraPath != null || loraConfig?.audioLoraPath != null) {
      throw UnsupportedError(
        'LoRA config is not supported by the LiteRT-LM JS SDK.',
      );
    }
    if (config.channels != null) {
      throw UnsupportedError(
        'ConversationConfig.channels is not supported by the LiteRT-LM JS SDK.',
      );
    }

    final jsConfig = <String, Object?>{
      'sessionConfig': _sessionConfigToJson(dartSessionConfig),
    };
    final preface = <String, Object?>{};
    final messages = <Object?>[
      if (config.systemMessage != null) config.systemMessage!.toJson(),
      ...config.initialMessages.map((message) => message.toJson()),
    ];
    if (messages.isNotEmpty) {
      preface['messages'] = messages;
    }
    final tools = config.tools
        .map((tool) => tool.getToolDescription())
        .toList(growable: false);
    if (tools.isNotEmpty) {
      preface['tools'] = tools;
    }
    if (config.extraContext.isNotEmpty) {
      preface['extra_context'] = config.extraContext;
    }
    if (preface.isNotEmpty) {
      jsConfig['preface'] = preface;
    }
    if (enableConversationConstrainedDecoding) {
      jsConfig['enableConstrainedDecoding'] = true;
    }
    if (filterChannelContentFromKvCache != null) {
      jsConfig['filterChannelContentFromKvCache'] =
          filterChannelContentFromKvCache;
    }
    return _parseJson(jsonEncode(jsConfig));
  }

  JSObject _sessionConfigToJs(SessionConfig config) {
    return _parseJson(jsonEncode(_sessionConfigToJson(config)));
  }

  Map<String, Object?> _sessionConfigToJson(SessionConfig? config) {
    final loraConfig = config?.loraConfig;
    if (loraConfig?.loraPath != null || loraConfig?.audioLoraPath != null) {
      throw UnsupportedError(
        'LoRA config is not supported by the LiteRT-LM JS SDK.',
      );
    }

    final samplerConfig = config?.samplerConfig;
    return {
      if (samplerConfig != null)
        'samplerParams': {
          'type': _samplerTypeTopP,
          'k': samplerConfig.topK,
          'p': samplerConfig.topP,
          'temperature': samplerConfig.temperature,
          'seed': samplerConfig.seed,
        },
      'maxOutputTokens': ?config?.maxOutputTokens,
      'applyPromptTemplateInSession': ?config?.applyPromptTemplateInSession,
    };
  }

  List<String> _inputDataToWebTextList(List<InputData> inputData) {
    return inputData
        .map((input) {
          return switch (input) {
            TextInputData(:final text) => text,
            ImageInputData() => throw UnsupportedError(
              'Session image input is not supported by the LiteRT-LM JS SDK.',
            ),
            AudioInputData() => throw UnsupportedError(
              'Session audio input is not supported by the LiteRT-LM JS SDK.',
            ),
          };
        })
        .toList(growable: false);
  }

  String _responsesFirstText(JSObject responses) {
    try {
      final texts = responses
          .callMethod<JSArray<JSString>>('getTexts'.toJS)
          .toDart;
      return texts.isEmpty ? '' : texts.first.toDart;
    } finally {
      responses.callMethod<JSAny?>('delete'.toJS);
    }
  }

  String _stringifyJson(JSAny value) {
    final json = globalContext.getProperty<JSObject>('JSON'.toJS);
    return json.callMethod<JSString>('stringify'.toJS, value).toDart;
  }

  Future<T> _promiseToFuture<T extends JSAny?>(JSPromise<T> promise) async {
    try {
      return await promise.toDart;
    } catch (error) {
      throw LiteRtLmException(error.toString());
    }
  }

  void _ignoreJsPromise(JSPromise<JSAny?> promise) {
    unawaited(_promiseToFuture<JSAny?>(promise).catchError((_) => null));
  }

  JSObject _messageStreamReader(JSObject conversation, JSObject message) {
    final stream = conversation.callMethod<JSObject>(
      'sendMessageStreaming'.toJS,
      message,
    );
    return stream.callMethod<JSObject>('getReader'.toJS);
  }

  Future<void> _pumpMessageStream(
    JSObject reader,
    void Function(Message message) onMessage,
  ) async {
    while (true) {
      final result = await _promiseToFuture<JSObject>(
        reader.callMethod<JSPromise<JSObject>>('read'.toJS),
      );

      final isDone = result.getProperty<JSBoolean>('done'.toJS).toDart;
      if (isDone) {
        return;
      }

      final chunk = result.getProperty<JSAny?>('value'.toJS);
      if (chunk != null) {
        onMessage(Message.fromJsonString(_stringifyJson(chunk)));
      }
    }
  }
}

class _WebEngineHandle implements EngineHandle {
  _WebEngineHandle(this.engine);

  final Future<JSObject> engine;
}

class _WebConversationHandle implements ConversationHandle {
  _WebConversationHandle(this.conversation);

  final JSObject conversation;
  JSObject? streamReader;
}

class _WebSessionHandle implements SessionHandle {
  _WebSessionHandle(this.session);

  final JSObject session;
}

@JS('Function')
external JSFunction _newFunction(JSString argumentName, JSString body);
