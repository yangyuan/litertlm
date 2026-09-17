// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:convert';

import 'package:jni/_internal.dart' as jni_internal;
import 'package:jni/jni.dart';

import '../litertlm/benchmark.dart';
import '../litertlm/config.dart';
import '../litertlm/exceptions.dart';
import '../litertlm/message.dart';
import '../litertlm/runtime.dart';
import '../litertlm/session.dart';
import 'runtime.dart';

/// Creates the JNI-backed native runtime.
LiteRtLmNativeRuntime createJniRuntime() => _LiteRtLmJniRuntime();

String _encodeInputDataListJson(List<InputData> inputData) {
  return jsonEncode(inputData.map((input) => input.toJson()).toList());
}

String _encodeBackendJson(Backend backend) {
  return jsonEncode({
    'name': backend.name,
    if (backend case CpuBackend(:final threadCount?))
      'threadCount': threadCount,
    if (backend case NpuBackend(:final nativeLibraryDir?))
      'nativeLibraryDir': nativeLibraryDir,
  });
}

class _LiteRtLmJniRuntime implements LiteRtLmNativeRuntime {
  final _class = JClass.forName('org/rockstudio/litertlm/LiteRtLmJniBridge');

  late final _nativeExceptionClass = JClass.forName(
    'org/rockstudio/litertlm/LiteRtLmJniNativeException',
  );
  late final _nativeExceptionGetCode = _nativeExceptionClass.instanceMethodId(
    'getCode',
    '()I',
  );
  late final _nativeExceptionGetOperation = _nativeExceptionClass
      .instanceMethodId('getOperation', '()I');

  @override
  bool enableConversationToolCallStreaming = false;

  @override
  String conversationToolCallStreamingChannelName = 'tool_call';

  late final _createEngine = _class.staticMethodId(
    'createEngine',
    '(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;IILjava/lang/String;)Lcom/google/ai/edge/litertlm/Engine;',
  );
  late final _createCapabilities = _class.staticMethodId(
    'createCapabilities',
    '(Ljava/lang/String;)Lcom/google/ai/edge/litertlm/Capabilities;',
  );
  late final _hasSpeculativeDecodingSupport = _class.staticMethodId(
    'hasSpeculativeDecodingSupport',
    '(Lcom/google/ai/edge/litertlm/Capabilities;)Z',
  );
  late final _deleteCapabilities = _class.staticMethodId(
    'deleteCapabilities',
    '(Lcom/google/ai/edge/litertlm/Capabilities;)V',
  );
  late final _benchmark = _class.staticMethodId(
    'benchmark',
    '(Ljava/lang/String;Ljava/lang/String;IILjava/lang/String;)Ljava/lang/String;',
  );
  late final _initializeEngine = _class.staticMethodId(
    'initializeEngine',
    '(Lcom/google/ai/edge/litertlm/Engine;)V',
  );
  late final _deleteEngine = _class.staticMethodId(
    'deleteEngine',
    '(Lcom/google/ai/edge/litertlm/Engine;)V',
  );
  late final _createConversation = _class.staticMethodId(
    'createConversation',
    '(Lcom/google/ai/edge/litertlm/Engine;Ljava/lang/String;)Lcom/google/ai/edge/litertlm/Conversation;',
  );
  late final _createSession = _class.staticMethodId(
    'createSession',
    '(Lcom/google/ai/edge/litertlm/Engine;Ljava/lang/String;)Lcom/google/ai/edge/litertlm/Session;',
  );
  late final _sendMessage = _class.staticMethodId(
    'sendMessage',
    '(Lcom/google/ai/edge/litertlm/Conversation;Ljava/lang/String;Ljava/lang/String;I)Ljava/lang/String;',
  );
  late final _sendMessageStream = _class.staticMethodId(
    'sendMessageStream',
    '(Lcom/google/ai/edge/litertlm/Conversation;Ljava/lang/String;Ljava/lang/String;ILcom/google/ai/edge/litertlm/MessageCallback;)V',
  );
  late final _runSessionPrefill = _class.staticMethodId(
    'runSessionPrefill',
    '(Lcom/google/ai/edge/litertlm/Session;Ljava/lang/String;)V',
  );
  late final _runSessionDecode = _class.staticMethodId(
    'runSessionDecode',
    '(Lcom/google/ai/edge/litertlm/Session;)Ljava/lang/String;',
  );
  late final _generateSessionContent = _class.staticMethodId(
    'generateSessionContent',
    '(Lcom/google/ai/edge/litertlm/Session;Ljava/lang/String;)Ljava/lang/String;',
  );
  late final _generateSessionContentStream = _class.staticMethodId(
    'generateSessionContentStream',
    '(Lcom/google/ai/edge/litertlm/Session;Ljava/lang/String;Lcom/google/ai/edge/litertlm/ResponseCallback;)V',
  );
  late final _messageToJson = _class.staticMethodId(
    'messageToJson',
    '(Lcom/google/ai/edge/litertlm/Message;)Ljava/lang/String;',
  );
  late final _cancelConversation = _class.staticMethodId(
    'cancelConversation',
    '(Lcom/google/ai/edge/litertlm/Conversation;)V',
  );
  late final _cancelSession = _class.staticMethodId(
    'cancelSession',
    '(Lcom/google/ai/edge/litertlm/Session;)V',
  );
  late final _getTokenCount = _class.staticMethodId(
    'getTokenCount',
    '(Lcom/google/ai/edge/litertlm/Conversation;)I',
  );
  late final _getBenchmarkInfo = _class.staticMethodId(
    'getBenchmarkInfo',
    '(Lcom/google/ai/edge/litertlm/Conversation;)Ljava/lang/String;',
  );
  late final _renderMessageToString = _class.staticMethodId(
    'renderMessageToString',
    '(Lcom/google/ai/edge/litertlm/Conversation;Ljava/lang/String;)Ljava/lang/String;',
  );
  late final _renderPreface = _class.staticMethodId(
    'renderPreface',
    '(Lcom/google/ai/edge/litertlm/Conversation;)Ljava/lang/String;',
  );
  late final _deleteConversation = _class.staticMethodId(
    'deleteConversation',
    '(Lcom/google/ai/edge/litertlm/Conversation;)V',
  );
  late final _deleteSession = _class.staticMethodId(
    'deleteSession',
    '(Lcom/google/ai/edge/litertlm/Session;)V',
  );

  late final _setMinimumLogLevel = _class.staticMethodId(
    'setMinimumLogLevel',
    '(I)V',
  );
  late final _getEnableBenchmark = _class.staticMethodId(
    'getEnableBenchmark',
    '()I',
  );
  late final _setEnableBenchmark = _class.staticMethodId(
    'setEnableBenchmark',
    '(I)V',
  );
  late final _integerClass = JClass.forName('java/lang/Integer');
  late final _integerValueOf = _integerClass.staticMethodId(
    'valueOf',
    '(I)Ljava/lang/Integer;',
  );
  late final _integerIntValue = _integerClass.instanceMethodId(
    'intValue',
    '()I',
  );
  late final _getEnableSpeculativeDecoding = _class.staticMethodId(
    'getEnableSpeculativeDecoding',
    '()Ljava/lang/Integer;',
  );
  late final _setEnableSpeculativeDecoding = _class.staticMethodId(
    'setEnableSpeculativeDecoding',
    '(Ljava/lang/Integer;)V',
  );
  late final _getEnableConversationConstrainedDecoding = _class.staticMethodId(
    'getEnableConversationConstrainedDecoding',
    '()I',
  );
  late final _setEnableConversationConstrainedDecoding = _class.staticMethodId(
    'setEnableConversationConstrainedDecoding',
    '(I)V',
  );
  late final _getFilterChannelContentFromKvCache = _class.staticMethodId(
    'getFilterChannelContentFromKvCache',
    '()Ljava/lang/Integer;',
  );
  late final _setFilterChannelContentFromKvCache = _class.staticMethodId(
    'setFilterChannelContentFromKvCache',
    '(Ljava/lang/Integer;)V',
  );
  late final _getVisualTokenBudget = _class.staticMethodId(
    'getVisualTokenBudget',
    '()Ljava/lang/Integer;',
  );
  late final _setVisualTokenBudget = _class.staticMethodId(
    'setVisualTokenBudget',
    '(Ljava/lang/Integer;)V',
  );

  @override
  bool get enableBenchmark {
    return _getEnableBenchmark.call(_class, jint.type, []) != 0;
  }

  @override
  set enableBenchmark(bool value) {
    _setEnableBenchmark.call(_class, jvoid.type, [JValueInt(value ? 1 : 0)]);
  }

  @override
  bool? get enableSpeculativeDecoding {
    final value = _getEnableSpeculativeDecoding.callNullable(
      _class,
      JObject.type,
      [],
    );
    if (value == null) {
      return null;
    }
    try {
      return _integerIntValue.call(value, jint.type, []) != 0;
    } finally {
      value.release();
    }
  }

  @override
  set enableSpeculativeDecoding(bool? value) {
    if (value == null) {
      _setEnableSpeculativeDecoding.call(_class, jvoid.type, [null]);
      return;
    }
    final integer = _integerValueOf.call(_integerClass, JObject.type, [
      JValueInt(value ? 1 : 0),
    ]);
    try {
      _setEnableSpeculativeDecoding.call(_class, jvoid.type, [integer]);
    } finally {
      integer.release();
    }
  }

  @override
  bool get enableConversationConstrainedDecoding {
    return _getEnableConversationConstrainedDecoding.call(
          _class,
          jint.type,
          [],
        ) !=
        0;
  }

  @override
  set enableConversationConstrainedDecoding(bool value) {
    _setEnableConversationConstrainedDecoding.call(_class, jvoid.type, [
      JValueInt(value ? 1 : 0),
    ]);
  }

  @override
  bool? get filterChannelContentFromKvCache {
    final value = _getFilterChannelContentFromKvCache.callNullable(
      _class,
      JObject.type,
      [],
    );
    if (value == null) {
      return null;
    }
    try {
      return _integerIntValue.call(value, jint.type, []) != 0;
    } finally {
      value.release();
    }
  }

  @override
  set filterChannelContentFromKvCache(bool? value) {
    if (value == null) {
      _setFilterChannelContentFromKvCache.call(_class, jvoid.type, [null]);
      return;
    }
    final integer = _integerValueOf.call(_integerClass, JObject.type, [
      JValueInt(value ? 1 : 0),
    ]);
    try {
      _setFilterChannelContentFromKvCache.call(_class, jvoid.type, [integer]);
    } finally {
      integer.release();
    }
  }

  @override
  int? get visualTokenBudget {
    final value = _getVisualTokenBudget.callNullable(_class, JObject.type, []);
    if (value == null) {
      return null;
    }
    try {
      return _integerIntValue.call(value, jint.type, []);
    } finally {
      value.release();
    }
  }

  @override
  set visualTokenBudget(int? value) {
    if (value == null) {
      _setVisualTokenBudget.call(_class, jvoid.type, [null]);
      return;
    }
    final integer = _integerValueOf.call(_integerClass, JObject.type, [
      JValueInt(value),
    ]);
    try {
      _setVisualTokenBudget.call(_class, jvoid.type, [integer]);
    } finally {
      integer.release();
    }
  }

  @override
  EngineHandle createEngine(EngineConfig config) {
    if (config.loraRank != null) {
      throw UnsupportedError(
        'loraRank is not supported by the LiteRT-LM Android SDK.',
      );
    }
    if (config.audioLoraRank != null) {
      throw UnsupportedError(
        'audioLoraRank is not supported by the LiteRT-LM Android SDK.',
      );
    }
    final modelPath = config.modelPath.toJString();
    final backend = _encodeBackendJson(config.backend).toJString();
    final visionBackend =
        (config.visionBackend == null
                ? ''
                : _encodeBackendJson(config.visionBackend!))
            .toJString();
    final audioBackend =
        (config.audioBackend == null
                ? ''
                : _encodeBackendJson(config.audioBackend!))
            .toJString();
    final cacheDir = (config.cacheDir ?? '').toJString();
    try {
      return _JniEngineHandle(
        _createEngine.call(_class, JObject.type, [
          modelPath,
          backend,
          visionBackend,
          audioBackend,
          JValueInt(config.maxNumTokens ?? _unsetInt),
          JValueInt(config.maxNumImages ?? _unsetInt),
          cacheDir,
        ]),
      );
    } finally {
      modelPath.release();
      backend.release();
      visionBackend.release();
      audioBackend.release();
      cacheDir.release();
    }
  }

  @override
  CapabilitiesHandle createCapabilities(String modelPath) {
    final modelPathString = modelPath.toJString();
    try {
      return _JniCapabilitiesHandle(
        _createCapabilities.call(_class, JObject.type, [modelPathString]),
      );
    } finally {
      modelPathString.release();
    }
  }

  @override
  bool hasSpeculativeDecodingSupport(CapabilitiesHandle capabilities) {
    final jniCapabilities = capabilities as _JniCapabilitiesHandle;
    return _hasSpeculativeDecodingSupport.call(_class, jboolean.type, [
      jniCapabilities.capabilities,
    ]);
  }

  @override
  void deleteCapabilities(CapabilitiesHandle capabilities) {
    final jniCapabilities = capabilities as _JniCapabilitiesHandle;
    _deleteCapabilities.call(_class, jvoid.type, [
      jniCapabilities.capabilities,
    ]);
    jniCapabilities.capabilities.release();
  }

  @override
  Future<BenchmarkInfo> benchmark(
    EngineConfig config, {
    required int prefillTokens,
    required int decodeTokens,
  }) async {
    final modelPath = config.modelPath.toJString();
    final backend = _encodeBackendJson(config.backend).toJString();
    final cacheDir = (config.cacheDir ?? '').toJString();
    try {
      final benchmarkInfoJson = _translateNativeException(
        LiteRtLmOperation.engineInitialization,
        () => _benchmark
            .call(_class, JString.type, [
              modelPath,
              backend,
              JValueInt(prefillTokens),
              JValueInt(decodeTokens),
              cacheDir,
            ])
            .toDartString(releaseOriginal: true),
      );
      return BenchmarkInfo.fromJsonString(benchmarkInfoJson);
    } finally {
      modelPath.release();
      backend.release();
      cacheDir.release();
    }
  }

  @override
  Future<void> initializeEngine(EngineHandle engine) async {
    final jniEngine = engine as _JniEngineHandle;
    _translateNativeException(
      LiteRtLmOperation.engineInitialization,
      () => _initializeEngine.call(_class, jvoid.type, [jniEngine.engine]),
    );
  }

  @override
  Future<ConversationHandle> createConversation(
    EngineHandle engine,
    ConversationConfig config,
  ) async {
    if (enableConversationToolCallStreaming) {
      throw UnsupportedError(
        'ExperimentalFlags.enableConversationToolCallStreaming is not supported by the LiteRT-LM Android SDK.',
      );
    }
    final sessionConfig = config.sessionConfig;
    if (sessionConfig?.applyPromptTemplateInSession != null) {
      throw UnsupportedError(
        'SessionConfig.applyPromptTemplateInSession is not supported by the LiteRT-LM Android SDK.',
      );
    }
    final jniEngine = engine as _JniEngineHandle;
    final configJson = jsonEncode(config.toJson()).toJString();
    try {
      return _JniConversationHandle(
        _translateNativeException(
          LiteRtLmOperation.conversationCreation,
          () => _createConversation.call(_class, JObject.type, [
            jniEngine.engine,
            configJson,
          ]),
        ),
      );
    } finally {
      configJson.release();
    }
  }

  @override
  Future<SessionHandle> createSession(
    EngineHandle engine,
    SessionConfig config,
  ) async {
    if (config.maxOutputTokens != null) {
      throw UnsupportedError(
        'SessionConfig.maxOutputTokens is not supported by the LiteRT-LM Android SDK.',
      );
    }
    if (config.applyPromptTemplateInSession != null) {
      throw UnsupportedError(
        'SessionConfig.applyPromptTemplateInSession is not supported by the LiteRT-LM Android SDK.',
      );
    }
    final jniEngine = engine as _JniEngineHandle;
    final configJson = jsonEncode(config.toJson()).toJString();
    try {
      return _JniSessionHandle(
        _translateNativeException(
          LiteRtLmOperation.sessionCreation,
          () => _createSession.call(_class, JObject.type, [
            jniEngine.engine,
            configJson,
          ]),
        ),
      );
    } finally {
      configJson.release();
    }
  }

  @override
  Future<Message> sendMessage(
    ConversationHandle conversation,
    String messageJson, {
    String? extraContextJson,
    int? maxOutputTokens,
  }) async {
    final jniConversation = conversation as _JniConversationHandle;
    final message = messageJson.toJString();
    final extraContext = (extraContextJson ?? '').toJString();
    try {
      final response = _sendMessage
          .call(_class, JString.type, [
            jniConversation.conversation,
            message,
            extraContext,
            JValueInt(maxOutputTokens ?? _unsetInt),
          ])
          .toDartString(releaseOriginal: true);
      return Message.fromJsonString(response);
    } finally {
      message.release();
      extraContext.release();
    }
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
  }) {
    final jniConversation = conversation as _JniConversationHandle;
    final done = Completer<void>();
    JObject? streamCallback;

    void releaseCallback() {
      streamCallback?.release();
      streamCallback = null;
    }

    void completeDone() {
      releaseCallback();
      if (done.isCompleted) return;
      try {
        onDone();
        done.complete();
      } catch (error, stackTrace) {
        done.completeError(error, stackTrace);
      }
    }

    void completeError(Object error, StackTrace stackTrace) {
      releaseCallback();
      if (done.isCompleted) return;
      try {
        onError(error, stackTrace);
      } catch (callbackError, callbackStackTrace) {
        done.completeError(callbackError, callbackStackTrace);
        return;
      }
      done.completeError(error, stackTrace);
    }

    streamCallback = _MessageCallback.implement(
      _MessageCallbackImplementation(
        onMessage: (message) {
          try {
            final messageJson = _messageToJson
                .call(_class, JString.type, [message])
                .toDartString(releaseOriginal: true);
            onMessage(Message.fromJsonString(messageJson));
          } catch (error, stackTrace) {
            _cancelConversation.call(_class, jvoid.type, [
              jniConversation.conversation,
            ]);
            completeError(error, stackTrace);
          }
        },
        onDone: completeDone,
        onError: (throwable) {
          completeError(
            LiteRtLmException(throwable.toString()),
            StackTrace.current,
          );
        },
      ),
    );
    final message = messageJson.toJString();
    final extraContext = (extraContextJson ?? '').toJString();
    try {
      _sendMessageStream.call(_class, jvoid.type, [
        jniConversation.conversation,
        message,
        extraContext,
        JValueInt(maxOutputTokens ?? _unsetInt),
        streamCallback,
      ]);
    } catch (error, stackTrace) {
      completeError(error, stackTrace);
    } finally {
      message.release();
      extraContext.release();
    }

    return done.future;
  }

  @override
  void cancelConversation(ConversationHandle conversation) {
    final jniConversation = conversation as _JniConversationHandle;
    _cancelConversation.call(_class, jvoid.type, [
      jniConversation.conversation,
    ]);
  }

  @override
  Future<void> runSessionPrefill(
    SessionHandle session,
    List<InputData> inputData,
  ) async {
    final jniSession = session as _JniSessionHandle;
    final inputDataJson = _encodeInputDataListJson(inputData).toJString();
    try {
      _runSessionPrefill.call(_class, jvoid.type, [
        jniSession.session,
        inputDataJson,
      ]);
    } finally {
      inputDataJson.release();
    }
  }

  @override
  Future<String> runSessionDecode(SessionHandle session) async {
    final jniSession = session as _JniSessionHandle;
    return _runSessionDecode
        .call(_class, JString.type, [jniSession.session])
        .toDartString(releaseOriginal: true);
  }

  @override
  Future<String> generateSessionContent(
    SessionHandle session,
    List<InputData> inputData,
  ) async {
    final jniSession = session as _JniSessionHandle;
    final inputDataJson = _encodeInputDataListJson(inputData).toJString();
    try {
      return _generateSessionContent
          .call(_class, JString.type, [jniSession.session, inputDataJson])
          .toDartString(releaseOriginal: true);
    } finally {
      inputDataJson.release();
    }
  }

  @override
  Stream<String> generateSessionContentStream(
    SessionHandle session,
    List<InputData> inputData,
  ) {
    final jniSession = session as _JniSessionHandle;
    JObject? streamCallback;
    late StreamController<String> controller;

    controller = StreamController<String>(
      onListen: () {
        streamCallback = _ResponseCallback.implement(
          _ResponseCallbackImplementation(
            onNext: controller.add,
            onDone: () {
              unawaited(controller.close());
              streamCallback?.release();
              streamCallback = null;
            },
            onError: (throwable) {
              controller.addError(LiteRtLmException(throwable.toString()));
              unawaited(controller.close());
              streamCallback?.release();
              streamCallback = null;
            },
          ),
        );
        final inputDataJson = _encodeInputDataListJson(inputData).toJString();
        try {
          _generateSessionContentStream.call(_class, jvoid.type, [
            jniSession.session,
            inputDataJson,
            streamCallback,
          ]);
        } catch (error) {
          streamCallback?.release();
          streamCallback = null;
          controller.addError(error);
          unawaited(controller.close());
        } finally {
          inputDataJson.release();
        }
      },
      onCancel: () {
        if (streamCallback != null) {
          _cancelSession.call(_class, jvoid.type, [jniSession.session]);
          streamCallback?.release();
          streamCallback = null;
        }
      },
    );

    return controller.stream;
  }

  @override
  void cancelSession(SessionHandle session) {
    final jniSession = session as _JniSessionHandle;
    _cancelSession.call(_class, jvoid.type, [jniSession.session]);
  }

  @override
  Future<int> getTokenCount(ConversationHandle conversation) async {
    final jniConversation = conversation as _JniConversationHandle;
    return _getTokenCount.call(_class, jint.type, [
      jniConversation.conversation,
    ]);
  }

  @override
  Future<BenchmarkInfo> getBenchmarkInfo(
    ConversationHandle conversation,
  ) async {
    final jniConversation = conversation as _JniConversationHandle;
    final benchmarkInfoJson = _getBenchmarkInfo
        .call(_class, JString.type, [jniConversation.conversation])
        .toDartString(releaseOriginal: true);
    return BenchmarkInfo.fromJsonString(benchmarkInfoJson);
  }

  @override
  Future<String> renderMessageIntoString(
    ConversationHandle conversation,
    String messageJson,
  ) async {
    final jniConversation = conversation as _JniConversationHandle;
    final message = messageJson.toJString();
    try {
      return _renderMessageToString
          .call(_class, JString.type, [jniConversation.conversation, message])
          .toDartString(releaseOriginal: true);
    } finally {
      message.release();
    }
  }

  @override
  Future<String> renderPreface(ConversationHandle conversation) async {
    final jniConversation = conversation as _JniConversationHandle;
    return _renderPreface
        .call(_class, JString.type, [jniConversation.conversation])
        .toDartString(releaseOriginal: true);
  }

  @override
  void deleteConversation(ConversationHandle conversation) {
    final jniConversation = conversation as _JniConversationHandle;
    _deleteConversation.call(_class, jvoid.type, [
      jniConversation.conversation,
    ]);
    jniConversation.conversation.release();
  }

  @override
  void deleteSession(SessionHandle session) {
    final jniSession = session as _JniSessionHandle;
    _deleteSession.call(_class, jvoid.type, [jniSession.session]);
    jniSession.session.release();
  }

  @override
  void deleteEngine(EngineHandle engine) {
    final jniEngine = engine as _JniEngineHandle;
    _deleteEngine.call(_class, jvoid.type, [jniEngine.engine]);
    jniEngine.engine.release();
  }

  @override
  void setMinimumLogLevel(LogSeverity severity) {
    _setMinimumLogLevel.call(_class, jvoid.type, [JValueInt(severity.value)]);
  }

  T _translateNativeException<T>(
    LiteRtLmOperation expectedOperation,
    T Function() call,
  ) {
    try {
      return call();
    } on JThrowable catch (error) {
      if (!error.isInstanceOf(_nativeExceptionClass)) {
        rethrow;
      }

      late final int code;
      late final int operationValue;
      try {
        code = _nativeExceptionGetCode.call(error, jint.type, []);
        operationValue = _nativeExceptionGetOperation.call(
          error,
          jint.type,
          [],
        );
      } finally {
        error.release();
      }

      var operation = expectedOperation;
      for (final candidate in LiteRtLmOperation.values) {
        if (candidate.nativeValue == operationValue) {
          operation = candidate;
          break;
        }
      }
      if (code == LiteRtLmNativeException.outOfMemoryCode) {
        throw LiteRtLmOutOfMemoryException(operation);
      }
      throw LiteRtLmNativeException(
        'Native exception code $code during ${operation.name}.',
        operation,
        code: code,
      );
    }
  }
}

class _JniEngineHandle implements EngineHandle {
  _JniEngineHandle(this.engine);

  final JObject engine;
}

class _JniCapabilitiesHandle implements CapabilitiesHandle {
  _JniCapabilitiesHandle(this.capabilities);

  final JObject capabilities;
}

class _JniConversationHandle implements ConversationHandle {
  _JniConversationHandle(this.conversation);

  final JObject conversation;
}

class _JniSessionHandle implements SessionHandle {
  _JniSessionHandle(this.session);

  final JObject session;
}

class _MessageCallback extends JObject {
  _MessageCallback.fromReference(super.reference) : super.fromReference();

  static JObject implement(_MessageCallbackImplementation implementation) {
    final implementer = JImplementer();
    implementIn(implementer, implementation);
    return implementer.implement<JObject>();
  }

  static final _implementations = <int, _MessageCallbackImplementation>{};

  static jni_internal.JObjectPtr _invoke(
    int port,
    jni_internal.JObjectPtr descriptor,
    jni_internal.JObjectPtr args,
  ) {
    return _invokeMethod(
      port,
      jni_internal.MethodInvocation.fromAddresses(
        0,
        descriptor.address,
        args.address,
      ),
    );
  }

  static final jni_internal.Pointer<
    jni_internal.NativeFunction<
      jni_internal.JObjectPtr Function(
        jni_internal.Int64,
        jni_internal.JObjectPtr,
        jni_internal.JObjectPtr,
      )
    >
  >
  _invokePointer = jni_internal.Pointer.fromFunction(_invoke);

  static jni_internal.JObjectPtr _invokeMethod(
    int port,
    jni_internal.MethodInvocation invocation,
  ) {
    try {
      final descriptor = invocation.methodDescriptor.toDartString(
        releaseOriginal: true,
      );
      final args = invocation.args;
      final implementation = _implementations[port]!;

      if (descriptor == r'onMessage(Lcom/google/ai/edge/litertlm/Message;)V') {
        implementation.onMessage(args![0]!);
        return jni_internal.nullptr;
      }
      if (descriptor == r'onDone()V') {
        implementation.onDone();
        return jni_internal.nullptr;
      }
      if (descriptor == r'onError(Ljava/lang/Throwable;)V') {
        implementation.onError(args![0]!);
        return jni_internal.nullptr;
      }
      throw LiteRtLmException('Unknown MessageCallback method: $descriptor');
    } catch (error) {
      return jni_internal.ProtectedJniExtensions.newDartException(error);
    }
  }

  static void implementIn(
    JImplementer implementer,
    _MessageCallbackImplementation implementation,
  ) {
    late final jni_internal.RawReceivePort port;
    port = jni_internal.RawReceivePort((message) {
      if (message == null) {
        _implementations.remove(port.sendPort.nativePort);
        port.close();
        return;
      }
      final invocation = jni_internal.MethodInvocation.fromMessage(message);
      final result = _invokeMethod(port.sendPort.nativePort, invocation);
      jni_internal.ProtectedJniExtensions.returnResult(
        invocation.result,
        result,
      );
    });
    implementer.add(
      'com.google.ai.edge.litertlm.MessageCallback',
      port,
      _invokePointer,
      const [
        r'onMessage(Lcom/google/ai/edge/litertlm/Message;)V',
        r'onDone()V',
        r'onError(Ljava/lang/Throwable;)V',
      ],
    );
    _implementations[port.sendPort.nativePort] = implementation;
  }
}

class _MessageCallbackImplementation {
  _MessageCallbackImplementation({
    required this.onMessage,
    required this.onDone,
    required this.onError,
  });

  final void Function(JObject message) onMessage;
  final void Function() onDone;
  final void Function(JObject throwable) onError;
}

class _ResponseCallback extends JObject {
  _ResponseCallback.fromReference(super.reference) : super.fromReference();

  static JObject implement(_ResponseCallbackImplementation implementation) {
    final implementer = JImplementer();
    implementIn(implementer, implementation);
    return implementer.implement<JObject>();
  }

  static final _implementations = <int, _ResponseCallbackImplementation>{};

  static jni_internal.JObjectPtr _invoke(
    int port,
    jni_internal.JObjectPtr descriptor,
    jni_internal.JObjectPtr args,
  ) {
    return _invokeMethod(
      port,
      jni_internal.MethodInvocation.fromAddresses(
        0,
        descriptor.address,
        args.address,
      ),
    );
  }

  static final jni_internal.Pointer<
    jni_internal.NativeFunction<
      jni_internal.JObjectPtr Function(
        jni_internal.Int64,
        jni_internal.JObjectPtr,
        jni_internal.JObjectPtr,
      )
    >
  >
  _invokePointer = jni_internal.Pointer.fromFunction(_invoke);

  static jni_internal.JObjectPtr _invokeMethod(
    int port,
    jni_internal.MethodInvocation invocation,
  ) {
    try {
      final descriptor = invocation.methodDescriptor.toDartString(
        releaseOriginal: true,
      );
      final args = invocation.args;
      final implementation = _implementations[port]!;

      if (descriptor == r'onNext(Ljava/lang/String;)V') {
        implementation.onNext(
          (args![0]! as JString).toDartString(releaseOriginal: false),
        );
        return jni_internal.nullptr;
      }
      if (descriptor == r'onDone()V') {
        implementation.onDone();
        return jni_internal.nullptr;
      }
      if (descriptor == r'onError(Ljava/lang/Throwable;)V') {
        implementation.onError(args![0]!);
        return jni_internal.nullptr;
      }
      throw LiteRtLmException('Unknown ResponseCallback method: $descriptor');
    } catch (error) {
      return jni_internal.ProtectedJniExtensions.newDartException(error);
    }
  }

  static void implementIn(
    JImplementer implementer,
    _ResponseCallbackImplementation implementation,
  ) {
    late final jni_internal.RawReceivePort port;
    port = jni_internal.RawReceivePort((message) {
      if (message == null) {
        _implementations.remove(port.sendPort.nativePort);
        port.close();
        return;
      }
      final invocation = jni_internal.MethodInvocation.fromMessage(message);
      final result = _invokeMethod(port.sendPort.nativePort, invocation);
      jni_internal.ProtectedJniExtensions.returnResult(
        invocation.result,
        result,
      );
    });
    implementer.add(
      'com.google.ai.edge.litertlm.ResponseCallback',
      port,
      _invokePointer,
      const [
        r'onNext(Ljava/lang/String;)V',
        r'onDone()V',
        r'onError(Ljava/lang/Throwable;)V',
      ],
    );
    _implementations[port.sendPort.nativePort] = implementation;
  }
}

class _ResponseCallbackImplementation {
  _ResponseCallbackImplementation({
    required this.onNext,
    required this.onDone,
    required this.onError,
  });

  final void Function(String response) onNext;
  final void Function() onDone;
  final void Function(JObject throwable) onError;
}

const _unsetInt = -0x80000000;
