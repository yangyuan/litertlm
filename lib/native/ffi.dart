import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../litertlm/benchmark.dart';
import '../litertlm/config.dart';
import '../litertlm/exceptions.dart';
import '../litertlm/message.dart';
import '../litertlm/runtime.dart';
import '../litertlm/session.dart';
import 'runtime.dart';

const _codeAssetName = 'package:litertlm/native/ffi.dart';
const _nativeFfiSupportAssetName =
    'package:litertlm/src/native_ffi_support.dart';
const _samplerTypeTopP = 2;
const _nativeCallSuccess = 0;
const _nativeCallFailure = 1;

Pointer<Opaque> _invokeGuardedPointerCall(
  LiteRtLmOperation operation,
  Pointer<Opaque> Function(Pointer<Int32> status) invoke,
) {
  final status = calloc<Int32>();
  try {
    final result = invoke(status);
    switch (status.value) {
      case _nativeCallSuccess:
      case _nativeCallFailure:
        return result;
      case LiteRtLmNativeException.outOfMemoryCode:
        throw LiteRtLmOutOfMemoryException(operation);
      case LiteRtLmNativeException.unexpectedExceptionCode:
        throw LiteRtLmNativeException(
          'Unexpected native exception during ${operation.name}.',
          operation,
          code: status.value,
        );
      default:
        throw LiteRtLmNativeException(
          'Unknown native call status ${status.value} during ${operation.name}.',
          operation,
          code: status.value,
        );
    }
  } finally {
    calloc.free(status);
  }
}

/// Creates the FFI-backed native runtime.
LiteRtLmNativeRuntime createFfiRuntime() => _LiteRtLmFfiRuntime();

class _LiteRtLmFfiRuntime implements LiteRtLmNativeRuntime {
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
    return _FfiEngineHandle(settings: _createEngineSettings(config));
  }

  @override
  CapabilitiesHandle createCapabilities(String modelPath) {
    _throwIfCapabilitiesUnsupported();

    final modelPathPointer = modelPath.toNativeUtf8();
    Pointer<Opaque> loadedFile;
    try {
      loadedFile = _loadedFileCreate(modelPathPointer);
    } finally {
      malloc.free(modelPathPointer);
    }
    if (loadedFile == nullptr) {
      throw LiteRtLmException(
        'Could not load LiteRT-LM capabilities for model: $modelPath.',
      );
    }
    return _FfiCapabilitiesHandle(pointer: loadedFile);
  }

  @override
  bool hasSpeculativeDecodingSupport(CapabilitiesHandle capabilities) {
    _throwIfCapabilitiesUnsupported();

    final ffiCapabilities = capabilities as _FfiCapabilitiesHandle;
    return _loadedFileHasSpeculativeDecodingSupport(ffiCapabilities.pointer);
  }

  @override
  void deleteCapabilities(CapabilitiesHandle capabilities) {
    _throwIfCapabilitiesUnsupported();

    final ffiCapabilities = capabilities as _FfiCapabilitiesHandle;
    _loadedFileDelete(ffiCapabilities.pointer);
  }

  void _throwIfCapabilitiesUnsupported() {
    // Windows and Linux native packages do not currently export the
    // litert_lm_loaded_file_* capabilities symbols used by the FFI bindings.
    if (Platform.isWindows || Platform.isLinux) {
      throw UnsupportedError(
        'Capabilities is not supported by the LiteRT-LM FFI runtime on Windows or Linux.',
      );
    }
  }

  @override
  Future<BenchmarkInfo> benchmark(
    EngineConfig config, {
    required int prefillTokens,
    required int decodeTokens,
  }) async {
    final engine = createEngine(config);
    var initialized = false;
    ConversationHandle? conversation;
    try {
      final ffiEngine = engine as _FfiEngineHandle;
      _engineSettingsEnableBenchmark(ffiEngine.settings);
      _engineSettingsSetNumPrefillTokens(ffiEngine.settings, prefillTokens);
      _engineSettingsSetNumDecodeTokens(ffiEngine.settings, decodeTokens);
      await initializeEngine(engine);
      initialized = true;
      conversation = await createConversation(
        engine,
        const ConversationConfig(),
      );
      await sendMessage(
        conversation,
        jsonEncode(
          Message.user('Engine ignore this message in this mode.').toJson(),
        ),
      );
      return await getBenchmarkInfo(conversation);
    } finally {
      if (conversation != null) {
        deleteConversation(conversation);
      }
      if (initialized) {
        deleteEngine(engine);
      }
    }
  }

  Pointer<Opaque> _createEngineSettings(EngineConfig config) {
    final modelPath = config.modelPath.toNativeUtf8();
    final backend = config.backend.name.toNativeUtf8();
    final visionBackend = _toOptionalNativeUtf8(config.visionBackend?.name);
    final audioBackend = _toOptionalNativeUtf8(config.audioBackend?.name);
    final settings = _engineSettingsCreate(
      modelPath,
      backend,
      visionBackend,
      audioBackend,
    );
    malloc.free(modelPath);
    malloc.free(backend);
    _freeOptionalNativeUtf8(visionBackend);
    _freeOptionalNativeUtf8(audioBackend);

    if (settings == nullptr) {
      throw const LiteRtLmException(
        'Could not create LiteRT-LM engine settings.',
      );
    }

    if (config.backend case CpuBackend(:final threadCount?)) {
      _engineSettingsSetNumThreads(settings, threadCount);
    }
    if (config.audioBackend case CpuBackend(:final threadCount?)) {
      _engineSettingsSetAudioNumThreads(settings, threadCount);
    }

    final maxNumTokens = config.maxNumTokens;
    if (maxNumTokens != null) {
      _engineSettingsSetMaxNumTokens(settings, maxNumTokens);
    }

    final maxNumImages = config.maxNumImages;
    if (maxNumImages != null) {
      _engineSettingsSetMaxNumImages(settings, maxNumImages);
    }

    final visualTokenBudget = this.visualTokenBudget;
    if (visualTokenBudget != null && visualTokenBudget > 0) {
      _engineSettingsSetMaxVisionTokensPerImage(settings, visualTokenBudget);
    }

    final cacheDir = config.cacheDir;
    if (cacheDir != null && cacheDir.isNotEmpty) {
      final cacheDirPointer = cacheDir.toNativeUtf8();
      try {
        _engineSettingsSetCacheDir(settings, cacheDirPointer);
      } finally {
        malloc.free(cacheDirPointer);
      }
    }

    if (config.backend case NpuBackend(:final nativeLibraryDir?)) {
      if (nativeLibraryDir.isNotEmpty) {
        final nativeLibraryDirPointer = nativeLibraryDir.toNativeUtf8();
        try {
          _engineSettingsSetLiteRtDispatchLibDir(
            settings,
            nativeLibraryDirPointer,
          );
        } finally {
          malloc.free(nativeLibraryDirPointer);
        }
      }
    }

    if (enableBenchmark) {
      _engineSettingsEnableBenchmark(settings);
    }

    final enableSpeculativeDecoding = this.enableSpeculativeDecoding;
    if (enableSpeculativeDecoding != null) {
      _engineSettingsSetEnableSpeculativeDecoding(
        settings,
        enableSpeculativeDecoding,
      );
    }

    final loraRank = config.loraRank;
    if (loraRank != null) {
      _engineSettingsSetLoraRank(settings, loraRank);
      if (loraRank > 0) {
        _setSupportedLoraRank(
          settings,
          loraRank,
          _engineSettingsSetSupportedLoraRanks,
          'LoRA',
        );
      }
    }

    final audioLoraRank = config.audioLoraRank;
    if (audioLoraRank != null) {
      _engineSettingsSetAudioLoraRank(settings, audioLoraRank);
      if (audioLoraRank > 0) {
        _setSupportedLoraRank(
          settings,
          audioLoraRank,
          _engineSettingsSetSupportedAudioLoraRanks,
          'audio LoRA',
        );
      }
    }

    return settings;
  }

  @override
  Future<void> initializeEngine(EngineHandle engine) async {
    final ffiEngine = engine as _FfiEngineHandle;

    try {
      final createdEngine = _invokeGuardedPointerCall(
        LiteRtLmOperation.engineInitialization,
        (status) => _guardedEngineCreate(
          Native.addressOf(_engineCreate),
          ffiEngine.settings,
          status,
        ),
      );
      if (createdEngine == nullptr) {
        throw const LiteRtLmException('Could not create LiteRT-LM engine.');
      }
      ffiEngine.pointer = createdEngine;
    } finally {
      _engineSettingsDelete(ffiEngine.settings);
    }
  }

  @override
  Future<ConversationHandle> createConversation(
    EngineHandle engine,
    ConversationConfig config,
  ) async {
    if (config.channels != null) {
      throw UnsupportedError(
        'ConversationConfig.channels is not supported by the LiteRT-LM C API.',
      );
    }

    final ffiEngine = engine as _FfiEngineHandle;
    final conversationConfig = _conversationConfigCreate();
    if (conversationConfig == nullptr) {
      throw const LiteRtLmException(
        'Could not create LiteRT-LM conversation config.',
      );
    }

    Pointer<Opaque> sessionConfig = nullptr;
    try {
      sessionConfig = _sessionConfigCreate();
      if (sessionConfig == nullptr) {
        throw const LiteRtLmException(
          'Could not create LiteRT-LM session config.',
        );
      }

      _applySessionConfig(sessionConfig, config.sessionConfig);

      _conversationConfigSetSessionConfig(conversationConfig, sessionConfig);
      _applyConversationConfig(conversationConfig, config);
      final conversation = _invokeGuardedPointerCall(
        LiteRtLmOperation.conversationCreation,
        (status) => _guardedConversationCreate(
          Native.addressOf(_conversationCreate),
          ffiEngine.pointer!,
          conversationConfig,
          status,
        ),
      );
      if (conversation == nullptr) {
        throw const LiteRtLmException(
          'Could not create LiteRT-LM conversation.',
        );
      }
      return _FfiConversationHandle(pointer: conversation);
    } finally {
      if (sessionConfig != nullptr) {
        _sessionConfigDelete(sessionConfig);
      }
      _conversationConfigDelete(conversationConfig);
    }
  }

  @override
  Future<SessionHandle> createSession(
    EngineHandle engine,
    SessionConfig config,
  ) async {
    final ffiEngine = engine as _FfiEngineHandle;
    final sessionConfig = _sessionConfigCreate();
    if (sessionConfig == nullptr) {
      throw const LiteRtLmException(
        'Could not create LiteRT-LM session config.',
      );
    }

    try {
      _applySessionConfig(sessionConfig, config);
      final session = _invokeGuardedPointerCall(
        LiteRtLmOperation.sessionCreation,
        (status) => _guardedEngineCreateSession(
          Native.addressOf(_engineCreateSession),
          ffiEngine.pointer!,
          sessionConfig,
          status,
        ),
      );
      if (session == nullptr) {
        throw const LiteRtLmException('Could not create LiteRT-LM session.');
      }
      return _FfiSessionHandle(pointer: session);
    } finally {
      _sessionConfigDelete(sessionConfig);
    }
  }

  @override
  Future<Message> sendMessage(
    ConversationHandle conversation,
    String messageJson, {
    String? extraContextJson,
    int? maxOutputTokens,
  }) async {
    final ffiConversation = conversation as _FfiConversationHandle;
    final optionalArgs = _createConversationOptionalArgs(maxOutputTokens);
    final messageJsonPointer = messageJson.toNativeUtf8();
    final extraContextPointer = _toOptionalNativeUtf8(extraContextJson);
    Pointer<Opaque> response;
    try {
      response = _conversationSendMessage(
        ffiConversation.pointer,
        messageJsonPointer,
        extraContextPointer,
        optionalArgs,
      );
    } finally {
      _deleteConversationOptionalArgs(optionalArgs);
      malloc.free(messageJsonPointer);
      _freeOptionalNativeUtf8(extraContextPointer);
    }
    if (response == nullptr) {
      throw const LiteRtLmException('Could not send LiteRT-LM message.');
    }

    try {
      final responseString = _jsonResponseGetString(response);
      if (responseString == nullptr) {
        throw const LiteRtLmException('Could not read LiteRT-LM response.');
      }
      return Message.fromJsonString(responseString.toDartString());
    } finally {
      _jsonResponseDelete(response);
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
    final ffiConversation = conversation as _FfiConversationHandle;
    final optionalArgs = _createConversationOptionalArgs(maxOutputTokens);
    final messageJsonPointer = messageJson.toNativeUtf8();
    final extraContextPointer = _toOptionalNativeUtf8(extraContextJson);
    late final _FfiStreamCallback streamCallback;
    final callback = NativeCallable<_DartStreamCallbackNative>.listener((
      Pointer<Utf8> chunk,
      bool isFinal,
      Pointer<Utf8> errorMessage,
    ) {
      _handleStreamCallback(streamCallback, chunk, isFinal, errorMessage);
    });
    final callbackRegistration = _createStreamCallbackRegistration(callback);
    streamCallback = _FfiStreamCallback(
      onMessage: onMessage,
      onDone: onDone,
      onError: onError,
      conversation: ffiConversation.pointer,
      callback: callback,
      callbackContext: callbackRegistration.context,
      messageJsonPointer: messageJsonPointer,
      extraContextPointer: extraContextPointer,
    );

    final int result;
    try {
      result = _conversationSendMessageStream(
        ffiConversation.pointer,
        messageJsonPointer,
        extraContextPointer,
        optionalArgs,
        callbackRegistration.function,
        callbackRegistration.data,
      );
    } finally {
      _deleteConversationOptionalArgs(optionalArgs);
    }

    if (result != 0) {
      streamCallback.error = LiteRtLmException(
        'Could not start LiteRT-LM message stream: $result.',
      );
      streamCallback.stackTrace = StackTrace.current;
      scheduleMicrotask(() => _disposeFfiStream(streamCallback));
    }
    return streamCallback.done.future;
  }

  @override
  void cancelConversation(ConversationHandle conversation) {
    final ffiConversation = conversation as _FfiConversationHandle;
    _conversationCancelProcess(ffiConversation.pointer);
  }

  @override
  Future<void> runSessionPrefill(
    SessionHandle session,
    List<InputData> inputData,
  ) async {
    if (inputData.isEmpty) {
      throw const LiteRtLmException('Session prefill requires input data.');
    }
    final ffiSession = session as _FfiSessionHandle;
    final result = _withInputData(
      inputData,
      (inputs, count) => _sessionRunPrefill(ffiSession.pointer, inputs, count),
    );
    if (result != 0) {
      throw LiteRtLmException(
        'Could not run LiteRT-LM session prefill: $result.',
      );
    }
  }

  @override
  Future<String> runSessionDecode(SessionHandle session) async {
    final ffiSession = session as _FfiSessionHandle;
    final responses = _sessionRunDecode(ffiSession.pointer);
    if (responses == nullptr) {
      throw const LiteRtLmException('Could not run LiteRT-LM session decode.');
    }
    return _responsesFirstText(responses);
  }

  @override
  Future<String> generateSessionContent(
    SessionHandle session,
    List<InputData> inputData,
  ) async {
    final ffiSession = session as _FfiSessionHandle;
    final responses = _withInputData(
      inputData,
      (inputs, count) =>
          _sessionGenerateContent(ffiSession.pointer, inputs, count),
    );
    if (responses == nullptr) {
      throw const LiteRtLmException(
        'Could not generate LiteRT-LM session content.',
      );
    }
    return _responsesFirstText(responses);
  }

  @override
  Stream<String> generateSessionContentStream(
    SessionHandle session,
    List<InputData> inputData,
  ) {
    final ffiSession = session as _FfiSessionHandle;
    late StreamController<String> controller;
    _FfiTextStreamCallback? streamCallback;

    controller = StreamController<String>(
      onListen: () {
        late final _FfiTextStreamCallback currentStreamCallback;
        final callback = NativeCallable<_DartStreamCallbackNative>.listener((
          Pointer<Utf8> chunk,
          bool isFinal,
          Pointer<Utf8> errorMessage,
        ) {
          _handleTextStreamCallback(
            currentStreamCallback,
            chunk,
            isFinal,
            errorMessage,
          );
        });
        final callbackRegistration = _createStreamCallbackRegistration(
          callback,
        );
        currentStreamCallback = _FfiTextStreamCallback(
          controller: controller,
          session: ffiSession.pointer,
          callback: callback,
          callbackContext: callbackRegistration.context,
        );
        streamCallback = currentStreamCallback;

        final result = _withInputData(
          inputData,
          (inputs, count) => _sessionGenerateContentStream(
            ffiSession.pointer,
            inputs,
            count,
            callbackRegistration.function,
            callbackRegistration.data,
          ),
        );

        if (result != 0) {
          controller.addError(
            LiteRtLmException(
              'Could not start LiteRT-LM session content stream: $result.',
            ),
          );
          scheduleMicrotask(() => _disposeFfiTextStream(currentStreamCallback));
        }
      },
      onCancel: () {
        final callback = streamCallback;
        if (callback == null || callback.isDone) {
          return null;
        }
        callback.isCanceled = true;
        _sessionCancelProcess(callback.session);
        return callback.done.future;
      },
    );

    return controller.stream;
  }

  @override
  void cancelSession(SessionHandle session) {
    final ffiSession = session as _FfiSessionHandle;
    _sessionCancelProcess(ffiSession.pointer);
  }

  @override
  Future<int> getTokenCount(ConversationHandle conversation) async {
    final ffiConversation = conversation as _FfiConversationHandle;
    final tokenCount = _conversationGetTokenCount(ffiConversation.pointer);
    if (tokenCount < 0) {
      throw const LiteRtLmException('Could not get LiteRT-LM token count.');
    }
    return tokenCount;
  }

  @override
  Future<BenchmarkInfo> getBenchmarkInfo(
    ConversationHandle conversation,
  ) async {
    final ffiConversation = conversation as _FfiConversationHandle;
    final benchmarkInfo = _conversationGetBenchmarkInfo(
      ffiConversation.pointer,
    );
    if (benchmarkInfo == nullptr) {
      throw const LiteRtLmException('Could not get LiteRT-LM benchmark info.');
    }
    try {
      final numPrefillTurns = _benchmarkInfoGetNumPrefillTurns(benchmarkInfo);
      final numDecodeTurns = _benchmarkInfoGetNumDecodeTurns(benchmarkInfo);
      final lastPrefillTurn = numPrefillTurns - 1;
      final lastDecodeTurn = numDecodeTurns - 1;
      return BenchmarkInfo(
        initTimeInSecond: _benchmarkInfoGetTotalInitTimeInSecond(benchmarkInfo),
        timeToFirstTokenInSecond: _benchmarkInfoGetTimeToFirstToken(
          benchmarkInfo,
        ),
        lastPrefillTokenCount: numPrefillTurns > 0
            ? _benchmarkInfoGetPrefillTokenCountAt(
                benchmarkInfo,
                lastPrefillTurn,
              )
            : 0,
        lastDecodeTokenCount: numDecodeTurns > 0
            ? _benchmarkInfoGetDecodeTokenCountAt(benchmarkInfo, lastDecodeTurn)
            : 0,
        lastPrefillTokensPerSecond: numPrefillTurns > 0
            ? _benchmarkInfoGetPrefillTokensPerSecondAt(
                benchmarkInfo,
                lastPrefillTurn,
              )
            : 0,
        lastDecodeTokensPerSecond: numDecodeTurns > 0
            ? _benchmarkInfoGetDecodeTokensPerSecondAt(
                benchmarkInfo,
                lastDecodeTurn,
              )
            : 0,
      );
    } finally {
      _benchmarkInfoDelete(benchmarkInfo);
    }
  }

  @override
  Future<String> renderMessageIntoString(
    ConversationHandle conversation,
    String messageJson,
  ) async {
    final ffiConversation = conversation as _FfiConversationHandle;
    final messageJsonPointer = messageJson.toNativeUtf8();
    Pointer<Utf8> rendered;
    try {
      rendered = _conversationRenderMessageToString(
        ffiConversation.pointer,
        messageJsonPointer,
      );
    } finally {
      malloc.free(messageJsonPointer);
    }
    if (rendered == nullptr) {
      throw const LiteRtLmException('Could not render LiteRT-LM message.');
    }
    return rendered.toDartString();
  }

  @override
  Future<String> renderPreface(ConversationHandle conversation) async {
    final ffiConversation = conversation as _FfiConversationHandle;
    final rendered = _conversationRenderPrefaceToString(
      ffiConversation.pointer,
    );
    if (rendered == nullptr) {
      throw const LiteRtLmException('Could not render LiteRT-LM preface.');
    }
    return rendered.toDartString();
  }

  @override
  void deleteConversation(ConversationHandle conversation) {
    final ffiConversation = conversation as _FfiConversationHandle;
    _conversationDelete(ffiConversation.pointer);
  }

  @override
  void deleteSession(SessionHandle session) {
    final ffiSession = session as _FfiSessionHandle;
    _sessionDelete(ffiSession.pointer);
  }

  @override
  void deleteEngine(EngineHandle engine) {
    final ffiEngine = engine as _FfiEngineHandle;
    final pointer = ffiEngine.pointer;
    if (pointer != null) {
      _engineDelete(pointer);
      ffiEngine.pointer = null;
    }
  }

  @override
  void setMinimumLogLevel(LogSeverity severity) {
    _setMinimumLogLevel(severity.value);
  }

  Pointer<Utf8> _toOptionalNativeUtf8(String? value) {
    if (value == null) {
      return nullptr.cast<Utf8>();
    }
    return value.toNativeUtf8();
  }

  void _freeOptionalNativeUtf8(Pointer<Utf8> value) {
    if (value != nullptr) {
      malloc.free(value);
    }
  }

  void _applySessionConfig(
    Pointer<Opaque> nativeSessionConfig,
    SessionConfig? dartSessionConfig,
  ) {
    if (dartSessionConfig == null) {
      return;
    }

    final samplerConfig = dartSessionConfig.samplerConfig;
    if (samplerConfig != null) {
      final samplerParams = _samplerParamsCreate(_samplerTypeTopP);
      if (samplerParams == nullptr) {
        throw const LiteRtLmException(
          'Could not create LiteRT-LM sampler parameters.',
        );
      }
      try {
        _samplerParamsSetTopK(samplerParams, samplerConfig.topK);
        _samplerParamsSetTopP(samplerParams, samplerConfig.topP);
        _samplerParamsSetTemperature(samplerParams, samplerConfig.temperature);
        _samplerParamsSetSeed(samplerParams, samplerConfig.seed);
        _sessionConfigSetSamplerParams(nativeSessionConfig, samplerParams);
      } finally {
        _samplerParamsDelete(samplerParams);
      }
    }

    final loraConfig = dartSessionConfig.loraConfig;
    _setLoraPath(
      nativeSessionConfig,
      loraConfig?.loraPath,
      _sessionConfigSetLoraPath,
    );
    _setLoraPath(
      nativeSessionConfig,
      loraConfig?.audioLoraPath,
      _sessionConfigSetAudioLoraPath,
    );
    final maxOutputTokens = dartSessionConfig.maxOutputTokens;
    if (maxOutputTokens != null) {
      _sessionConfigSetMaxOutputTokens(nativeSessionConfig, maxOutputTokens);
    }
    final applyPromptTemplateInSession =
        dartSessionConfig.applyPromptTemplateInSession;
    if (applyPromptTemplateInSession != null) {
      _sessionConfigSetApplyPromptTemplate(
        nativeSessionConfig,
        applyPromptTemplateInSession,
      );
    }
  }

  T _withInputData<T>(
    List<InputData> inputData,
    T Function(Pointer<Pointer<Opaque>> inputs, int count) callback,
  ) {
    if (inputData.isEmpty) {
      return callback(nullptr.cast<Pointer<Opaque>>(), 0);
    }

    final inputs = calloc<Pointer<Opaque>>(inputData.length);
    try {
      for (var index = 0; index < inputData.length; index += 1) {
        final input = inputData[index];
        final (type, bytes) = switch (input) {
          TextInputData(:final text) => (
            _inputDataTypeText,
            Uint8List.fromList(utf8.encode(text)),
          ),
          ImageInputData(:final bytes) => (_inputDataTypeImage, bytes),
          AudioInputData(:final bytes) => (_inputDataTypeAudio, bytes),
        };
        final allocationSize = bytes.isEmpty ? 1 : bytes.length;
        final data = calloc<Uint8>(allocationSize);
        try {
          if (bytes.isNotEmpty) {
            data.asTypedList(allocationSize).setAll(0, bytes);
          }
          final nativeInput = _inputDataCreate(
            type,
            data.cast<Void>(),
            bytes.length,
          );
          if (nativeInput == nullptr) {
            throw const LiteRtLmException(
              'Could not create LiteRT-LM input data.',
            );
          }
          inputs[index] = nativeInput;
        } finally {
          calloc.free(data);
        }
      }

      return callback(inputs, inputData.length);
    } finally {
      for (var index = 0; index < inputData.length; index += 1) {
        final nativeInput = inputs[index];
        if (nativeInput != nullptr) {
          _inputDataDelete(nativeInput);
        }
      }
      calloc.free(inputs);
    }
  }

  String _responsesFirstText(Pointer<Opaque> responses) {
    try {
      if (_responsesGetNumCandidates(responses) <= 0) {
        return '';
      }
      final text = _responsesGetResponseTextAt(responses, 0);
      if (text == nullptr) {
        return '';
      }
      return text.toDartString();
    } finally {
      _responsesDelete(responses);
    }
  }

  void _setLoraPath(
    Pointer<Opaque> sessionConfig,
    String? path,
    int Function(Pointer<Opaque>, Pointer<Utf8>) setter,
  ) {
    if (path == null) {
      return;
    }

    final pathPointer = path.toNativeUtf8();
    try {
      final result = setter(sessionConfig, pathPointer);
      if (result != 0) {
        throw LiteRtLmException('Could not set LiteRT-LM LoRA path: $path.');
      }
    } finally {
      malloc.free(pathPointer);
    }
  }

  void _setSupportedLoraRank(
    Pointer<Opaque> settings,
    int rank,
    int Function(Pointer<Opaque>, Pointer<Int>, int) setter,
    String label,
  ) {
    final ranks = calloc<Int>();
    try {
      ranks.value = rank;
      final result = setter(settings, ranks, 1);
      if (result != 0) {
        throw LiteRtLmException(
          'Could not set supported LiteRT-LM $label ranks.',
        );
      }
    } finally {
      calloc.free(ranks);
    }
  }

  void _applyConversationConfig(
    Pointer<Opaque> conversationConfig,
    ConversationConfig config,
  ) {
    final systemMessage = config.systemMessage;
    if (systemMessage != null) {
      final systemMessageJson = jsonEncode(systemMessage.contents.toJson());
      _withNativeUtf8(systemMessageJson, (pointer) {
        _conversationConfigSetSystemMessage(conversationConfig, pointer);
      });
    }

    if (config.initialMessages.isNotEmpty) {
      final messages = config.initialMessages
          .map((message) => message.toJson())
          .toList(growable: false);
      _withNativeUtf8(jsonEncode(messages), (pointer) {
        _conversationConfigSetMessages(conversationConfig, pointer);
      });
    }

    if (config.tools.isNotEmpty) {
      final tools = config.tools
          .map((tool) => tool.getToolDescription())
          .toList(growable: false);
      _withNativeUtf8(jsonEncode(tools), (pointer) {
        _conversationConfigSetTools(conversationConfig, pointer);
      });
    }

    if (config.extraContext.isNotEmpty) {
      _withNativeUtf8(jsonEncode(config.extraContext), (pointer) {
        _conversationConfigSetExtraContext(conversationConfig, pointer);
      });
    }

    if (enableConversationConstrainedDecoding) {
      _conversationConfigSetEnableConstrainedDecoding(conversationConfig, true);
    }

    final filterChannelContentFromKvCache =
        this.filterChannelContentFromKvCache;
    if (filterChannelContentFromKvCache != null) {
      _conversationConfigSetFilterChannelContentFromKvCache(
        conversationConfig,
        filterChannelContentFromKvCache,
      );
    }

    if (enableConversationToolCallStreaming) {
      _withNativeUtf8(conversationToolCallStreamingChannelName, (
        channelNamePointer,
      ) {
        _conversationConfigSetStreamToolCalls(
          conversationConfig,
          true,
          channelNamePointer,
        );
      });
    }
  }

  Pointer<Opaque> _createConversationOptionalArgs(int? maxOutputTokens) {
    final visualTokenBudget = this.visualTokenBudget;
    if (visualTokenBudget == null && maxOutputTokens == null) {
      return nullptr;
    }

    final optionalArgs = _conversationOptionalArgsCreate();
    if (optionalArgs == nullptr) {
      throw const LiteRtLmException(
        'Could not create LiteRT-LM conversation optional args.',
      );
    }
    if (visualTokenBudget != null) {
      _conversationOptionalArgsSetVisualTokenBudget(
        optionalArgs,
        visualTokenBudget,
      );
    }
    if (maxOutputTokens != null) {
      _conversationOptionalArgsSetMaxOutputTokens(
        optionalArgs,
        maxOutputTokens,
      );
    }
    return optionalArgs;
  }

  void _deleteConversationOptionalArgs(Pointer<Opaque> optionalArgs) {
    if (optionalArgs != nullptr) {
      _conversationOptionalArgsDelete(optionalArgs);
    }
  }

  void _withNativeUtf8(String value, void Function(Pointer<Utf8>) callback) {
    final pointer = value.toNativeUtf8();
    try {
      callback(pointer);
    } finally {
      malloc.free(pointer);
    }
  }
}

class _FfiEngineHandle implements EngineHandle {
  _FfiEngineHandle({required this.settings});

  final Pointer<Opaque> settings;
  Pointer<Opaque>? pointer;
}

class _FfiCapabilitiesHandle implements CapabilitiesHandle {
  const _FfiCapabilitiesHandle({required this.pointer});

  final Pointer<Opaque> pointer;
}

class _FfiConversationHandle implements ConversationHandle {
  _FfiConversationHandle({required this.pointer});

  final Pointer<Opaque> pointer;
}

class _FfiSessionHandle implements SessionHandle {
  _FfiSessionHandle({required this.pointer});

  final Pointer<Opaque> pointer;
}

class _FfiStreamCallback {
  _FfiStreamCallback({
    required this.onMessage,
    required this.onDone,
    required this.onError,
    required this.conversation,
    required this.callback,
    required this.callbackContext,
    required this.messageJsonPointer,
    required this.extraContextPointer,
  });

  final void Function(Message message) onMessage;
  final void Function() onDone;
  final void Function(Object error, StackTrace stackTrace) onError;
  final Pointer<Opaque> conversation;
  final NativeCallable<_DartStreamCallbackNative> callback;
  final Pointer<Opaque> callbackContext;
  final Pointer<Utf8> messageJsonPointer;
  final Pointer<Utf8> extraContextPointer;
  final Completer<void> done = Completer<void>();
  Object? error;
  StackTrace? stackTrace;
  bool isCanceled = false;
  bool isDone = false;
}

class _FfiTextStreamCallback {
  _FfiTextStreamCallback({
    required this.controller,
    required this.session,
    required this.callback,
    required this.callbackContext,
  });

  final StreamController<String> controller;
  final Pointer<Opaque> session;
  final NativeCallable<_DartStreamCallbackNative> callback;
  final Pointer<Opaque> callbackContext;
  final Completer<void> done = Completer<void>();
  bool isCanceled = false;
  bool isDone = false;
}

class _StreamCallbackRegistration {
  const _StreamCallbackRegistration({
    required this.function,
    required this.data,
    required this.context,
  });

  final Pointer<NativeFunction<_StreamCallbackPointerNative>> function;
  final Pointer<Opaque> data;
  final Pointer<Opaque> context;
}

void _handleStreamCallback(
  _FfiStreamCallback streamCallback,
  Pointer<Utf8> chunk,
  bool isFinal,
  Pointer<Utf8> errorMessage,
) {
  if (streamCallback.isDone) {
    if (chunk != nullptr) {
      _nativeFree(chunk.cast<Void>());
    }
    if (errorMessage != nullptr) {
      _nativeFree(errorMessage.cast<Void>());
    }
    return;
  }

  if (errorMessage != nullptr) {
    try {
      if (!streamCallback.isCanceled) {
        streamCallback.error = LiteRtLmException(errorMessage.toDartString());
        streamCallback.stackTrace = StackTrace.current;
      }
    } finally {
      if (chunk != nullptr) {
        _nativeFree(chunk.cast<Void>());
      }
      _nativeFree(errorMessage.cast<Void>());
    }
    scheduleMicrotask(() => _disposeFfiStream(streamCallback));
    return;
  }

  if (chunk != nullptr) {
    try {
      if (!streamCallback.isCanceled) {
        streamCallback.onMessage(Message.fromJsonString(chunk.toDartString()));
      }
    } catch (error, stackTrace) {
      streamCallback.error ??= error;
      streamCallback.stackTrace ??= stackTrace;
      streamCallback.isCanceled = true;
      _conversationCancelProcess(streamCallback.conversation);
    } finally {
      _nativeFree(chunk.cast<Void>());
    }
  }

  if (isFinal) {
    scheduleMicrotask(() => _disposeFfiStream(streamCallback));
  }
}

void _disposeFfiStream(_FfiStreamCallback streamCallback) {
  if (streamCallback.isDone) {
    return;
  }

  streamCallback.isDone = true;
  malloc.free(streamCallback.messageJsonPointer);
  if (streamCallback.extraContextPointer != nullptr) {
    malloc.free(streamCallback.extraContextPointer);
  }
  if (streamCallback.callbackContext != nullptr) {
    _streamCallbackContextDelete(streamCallback.callbackContext);
  }
  streamCallback.callback.close();
  if (!streamCallback.done.isCompleted) {
    final error = streamCallback.error;
    try {
      if (error == null) {
        streamCallback.onDone();
        streamCallback.done.complete();
      } else {
        final stackTrace = streamCallback.stackTrace ?? StackTrace.current;
        streamCallback.onError(error, stackTrace);
        streamCallback.done.completeError(error, stackTrace);
      }
    } catch (callbackError, callbackStackTrace) {
      streamCallback.done.completeError(callbackError, callbackStackTrace);
    }
  }
}

void _handleTextStreamCallback(
  _FfiTextStreamCallback streamCallback,
  Pointer<Utf8> chunk,
  bool isFinal,
  Pointer<Utf8> errorMessage,
) {
  if (streamCallback.isDone) {
    if (chunk != nullptr) {
      _nativeFree(chunk.cast<Void>());
    }
    if (errorMessage != nullptr) {
      _nativeFree(errorMessage.cast<Void>());
    }
    return;
  }

  if (errorMessage != nullptr) {
    try {
      if (!streamCallback.isCanceled) {
        streamCallback.controller.addError(
          LiteRtLmException(errorMessage.toDartString()),
        );
      }
    } finally {
      if (chunk != nullptr) {
        _nativeFree(chunk.cast<Void>());
      }
      _nativeFree(errorMessage.cast<Void>());
    }
    scheduleMicrotask(() => _disposeFfiTextStream(streamCallback));
    return;
  }

  if (chunk != nullptr) {
    try {
      if (!streamCallback.isCanceled) {
        streamCallback.controller.add(chunk.toDartString());
      }
    } catch (error, stackTrace) {
      streamCallback.controller.addError(error, stackTrace);
    } finally {
      _nativeFree(chunk.cast<Void>());
    }
  }

  if (isFinal) {
    scheduleMicrotask(() => _disposeFfiTextStream(streamCallback));
  }
}

void _disposeFfiTextStream(_FfiTextStreamCallback streamCallback) {
  if (streamCallback.isDone) {
    return;
  }

  streamCallback.isDone = true;
  if (!streamCallback.isCanceled && !streamCallback.controller.isClosed) {
    unawaited(streamCallback.controller.close());
  }
  if (streamCallback.callbackContext != nullptr) {
    _streamCallbackContextDelete(streamCallback.callbackContext);
  }
  streamCallback.callback.close();
  if (!streamCallback.done.isCompleted) {
    streamCallback.done.complete();
  }
}

const _inputDataTypeText = 0;
const _inputDataTypeImage = 1;
const _inputDataTypeAudio = 3;

typedef _EngineSettingsCreateNative =
    Pointer<Opaque> Function(
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Utf8>,
    );
typedef _EngineSettingsSetMaxNumTokensNative =
    Void Function(Pointer<Opaque>, Int);
typedef _EngineSettingsSetMaxNumImagesNative =
    Void Function(Pointer<Opaque>, Int);
typedef _EngineSettingsSetMaxVisionTokensPerImageNative =
    Void Function(Pointer<Opaque>, Int);
typedef _EngineSettingsSetCacheDirNative =
    Void Function(Pointer<Opaque>, Pointer<Utf8>);
typedef _EngineSettingsSetLiteRtDispatchLibDirNative =
    Void Function(Pointer<Opaque>, Pointer<Utf8>);
typedef _EngineSettingsSetNumThreadsNative =
    Void Function(Pointer<Opaque>, Int);
typedef _EngineSettingsSetLoraRankNative = Void Function(Pointer<Opaque>, Int);
typedef _EngineSettingsSetBoolNative = Void Function(Pointer<Opaque>, Bool);
typedef _EngineSettingsSetSupportedLoraRanksNative =
    Int Function(Pointer<Opaque>, Pointer<Int>, Size);
typedef _EngineCreateNative = Pointer<Opaque> Function(Pointer<Opaque>);
typedef _EngineCreateSessionNative =
    Pointer<Opaque> Function(Pointer<Opaque>, Pointer<Opaque>);
typedef _GuardedEngineCreateNative =
    Pointer<Opaque> Function(
      Pointer<NativeFunction<_EngineCreateNative>>,
      Pointer<Opaque>,
      Pointer<Int32>,
    );
typedef _GuardedEngineCreateSessionNative =
    Pointer<Opaque> Function(
      Pointer<NativeFunction<_EngineCreateSessionNative>>,
      Pointer<Opaque>,
      Pointer<Opaque>,
      Pointer<Int32>,
    );
typedef _SessionConfigSetSamplerParamsNative =
    Void Function(Pointer<Opaque>, Pointer<Opaque>);
typedef _SamplerParamsSetIntNative = Void Function(Pointer<Opaque>, Int);
typedef _SamplerParamsSetFloatNative = Void Function(Pointer<Opaque>, Float);
typedef _SessionConfigSetIntNative = Void Function(Pointer<Opaque>, Int);
typedef _SessionConfigSetBoolNative = Void Function(Pointer<Opaque>, Bool);
typedef _SessionConfigSetLoraPathNative =
    Int Function(Pointer<Opaque>, Pointer<Utf8>);
typedef _ConversationConfigSetSessionConfigNative =
    Void Function(Pointer<Opaque>, Pointer<Opaque>);
typedef _ConversationConfigSetJsonNative =
    Void Function(Pointer<Opaque>, Pointer<Utf8>);
typedef _ConversationConfigSetBoolNative = Void Function(Pointer<Opaque>, Bool);
typedef _ConversationConfigSetStreamToolCallsNative =
    Void Function(Pointer<Opaque>, Bool, Pointer<Utf8>);
typedef _ConversationCreateNative =
    Pointer<Opaque> Function(Pointer<Opaque>, Pointer<Opaque>);
typedef _GuardedConversationCreateNative =
    Pointer<Opaque> Function(
      Pointer<NativeFunction<_ConversationCreateNative>>,
      Pointer<Opaque>,
      Pointer<Opaque>,
      Pointer<Int32>,
    );
typedef _InputDataCreateNative =
    Pointer<Opaque> Function(Int, Pointer<Void>, Size);
typedef _SessionRunPrefillNative =
    Int Function(Pointer<Opaque>, Pointer<Pointer<Opaque>>, Size);
typedef _SessionResponsesNative = Pointer<Opaque> Function(Pointer<Opaque>);
typedef _SessionGenerateContentNative =
    Pointer<Opaque> Function(Pointer<Opaque>, Pointer<Pointer<Opaque>>, Size);
typedef _SessionGenerateContentStreamNative =
    Int Function(
      Pointer<Opaque>,
      Pointer<Pointer<Opaque>>,
      Size,
      Pointer<NativeFunction<_StreamCallbackPointerNative>>,
      Pointer<Opaque>,
    );
typedef _ConversationSendMessageNative =
    Pointer<Opaque> Function(
      Pointer<Opaque>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Opaque>,
    );
typedef _StreamCallbackPointerNative = Void Function();
typedef _StreamChunkCallbackNative =
    Void Function(Pointer<Opaque>, Pointer<Opaque>);
typedef _DartStreamCallbackNative =
    Void Function(Pointer<Utf8>, Bool, Pointer<Utf8>);
typedef _StreamChunkGetStringNative = Pointer<Utf8> Function(Pointer<Opaque>);
typedef _StreamChunkIsFinalNative = Bool Function(Pointer<Opaque>);
typedef _ConversationSendMessageStreamNative =
    Int Function(
      Pointer<Opaque>,
      Pointer<Utf8>,
      Pointer<Utf8>,
      Pointer<Opaque>,
      Pointer<NativeFunction<_StreamCallbackPointerNative>>,
      Pointer<Opaque>,
    );
typedef _ConversationRenderMessageToStringNative =
    Pointer<Utf8> Function(Pointer<Opaque>, Pointer<Utf8>);
typedef _ConversationRenderPrefaceToStringNative =
    Pointer<Utf8> Function(Pointer<Opaque>);
typedef _BenchmarkInfoGetValueNative = Double Function(Pointer<Opaque>);
typedef _BenchmarkInfoGetCountNative = Int Function(Pointer<Opaque>);
typedef _BenchmarkInfoGetValueAtNative = Double Function(Pointer<Opaque>, Int);
typedef _BenchmarkInfoGetCountAtNative = Int Function(Pointer<Opaque>, Int);

@Native<_EngineSettingsCreateNative>(
  symbol: 'litert_lm_engine_settings_create',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _engineSettingsCreate(
  Pointer<Utf8> modelPath,
  Pointer<Utf8> backend,
  Pointer<Utf8> visionBackend,
  Pointer<Utf8> audioBackend,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_engine_settings_delete',
  assetId: _codeAssetName,
)
external void _engineSettingsDelete(Pointer<Opaque> settings);

@Native<_EngineSettingsSetMaxNumTokensNative>(
  symbol: 'litert_lm_engine_settings_set_max_num_tokens',
  assetId: _codeAssetName,
)
external void _engineSettingsSetMaxNumTokens(
  Pointer<Opaque> settings,
  int maxNumTokens,
);

@Native<_EngineSettingsSetMaxNumImagesNative>(
  symbol: 'litert_lm_engine_settings_set_max_num_images',
  assetId: _codeAssetName,
)
external void _engineSettingsSetMaxNumImages(
  Pointer<Opaque> settings,
  int maxNumImages,
);

@Native<_EngineSettingsSetMaxVisionTokensPerImageNative>(
  symbol: 'litert_lm_engine_settings_set_max_vision_tokens_per_image',
  assetId: _codeAssetName,
)
external void _engineSettingsSetMaxVisionTokensPerImage(
  Pointer<Opaque> settings,
  int maxVisionTokensPerImage,
);

@Native<_EngineSettingsSetCacheDirNative>(
  symbol: 'litert_lm_engine_settings_set_cache_dir',
  assetId: _codeAssetName,
)
external void _engineSettingsSetCacheDir(
  Pointer<Opaque> settings,
  Pointer<Utf8> cacheDir,
);

@Native<_EngineSettingsSetLiteRtDispatchLibDirNative>(
  symbol: 'litert_lm_engine_settings_set_litert_dispatch_lib_dir',
  assetId: _codeAssetName,
)
external void _engineSettingsSetLiteRtDispatchLibDir(
  Pointer<Opaque> settings,
  Pointer<Utf8> libDir,
);

@Native<_EngineSettingsSetNumThreadsNative>(
  symbol: 'litert_lm_engine_settings_set_num_threads',
  assetId: _codeAssetName,
)
external void _engineSettingsSetNumThreads(
  Pointer<Opaque> settings,
  int numThreads,
);

@Native<_EngineSettingsSetNumThreadsNative>(
  symbol: 'litert_lm_engine_settings_set_audio_num_threads',
  assetId: _codeAssetName,
)
external void _engineSettingsSetAudioNumThreads(
  Pointer<Opaque> settings,
  int numThreads,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_engine_settings_enable_benchmark',
  assetId: _codeAssetName,
)
external void _engineSettingsEnableBenchmark(Pointer<Opaque> settings);

@Native<_EngineSettingsSetMaxNumTokensNative>(
  symbol: 'litert_lm_engine_settings_set_num_prefill_tokens',
  assetId: _codeAssetName,
)
external void _engineSettingsSetNumPrefillTokens(
  Pointer<Opaque> settings,
  int numPrefillTokens,
);

@Native<_EngineSettingsSetMaxNumTokensNative>(
  symbol: 'litert_lm_engine_settings_set_num_decode_tokens',
  assetId: _codeAssetName,
)
external void _engineSettingsSetNumDecodeTokens(
  Pointer<Opaque> settings,
  int numDecodeTokens,
);

@Native<_EngineSettingsSetBoolNative>(
  symbol: 'litert_lm_engine_settings_set_enable_speculative_decoding',
  assetId: _codeAssetName,
)
external void _engineSettingsSetEnableSpeculativeDecoding(
  Pointer<Opaque> settings,
  bool enableSpeculativeDecoding,
);

@Native<_EngineSettingsSetLoraRankNative>(
  symbol: 'litert_lm_engine_settings_set_lora_rank',
  assetId: _codeAssetName,
)
external void _engineSettingsSetLoraRank(
  Pointer<Opaque> settings,
  int loraRank,
);

@Native<_EngineSettingsSetSupportedLoraRanksNative>(
  symbol: 'litert_lm_engine_settings_set_supported_lora_ranks',
  assetId: _codeAssetName,
)
external int _engineSettingsSetSupportedLoraRanks(
  Pointer<Opaque> settings,
  Pointer<Int> loraRanks,
  int numRanks,
);

@Native<_EngineSettingsSetLoraRankNative>(
  symbol: 'litert_lm_engine_settings_set_audio_lora_rank',
  assetId: _codeAssetName,
)
external void _engineSettingsSetAudioLoraRank(
  Pointer<Opaque> settings,
  int loraRank,
);

@Native<_EngineSettingsSetSupportedLoraRanksNative>(
  symbol: 'litert_lm_engine_settings_set_supported_audio_lora_ranks',
  assetId: _codeAssetName,
)
external int _engineSettingsSetSupportedAudioLoraRanks(
  Pointer<Opaque> settings,
  Pointer<Int> loraRanks,
  int numRanks,
);

@Native<_EngineCreateNative>(
  symbol: 'litert_lm_engine_create',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _engineCreate(Pointer<Opaque> settings);

@Native<_GuardedEngineCreateNative>(
  symbol: 'litertlm_engine_create_guarded',
  assetId: _nativeFfiSupportAssetName,
)
external Pointer<Opaque> _guardedEngineCreate(
  Pointer<NativeFunction<_EngineCreateNative>> create,
  Pointer<Opaque> settings,
  Pointer<Int32> status,
);

@Native<_EngineCreateSessionNative>(
  symbol: 'litert_lm_engine_create_session',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _engineCreateSession(
  Pointer<Opaque> engine,
  Pointer<Opaque> sessionConfig,
);

@Native<_GuardedEngineCreateSessionNative>(
  symbol: 'litertlm_engine_create_session_guarded',
  assetId: _nativeFfiSupportAssetName,
)
external Pointer<Opaque> _guardedEngineCreateSession(
  Pointer<NativeFunction<_EngineCreateSessionNative>> create,
  Pointer<Opaque> engine,
  Pointer<Opaque> sessionConfig,
  Pointer<Int32> status,
);

@Native<Pointer<Opaque> Function()>(
  symbol: 'litert_lm_session_config_create',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _sessionConfigCreate();

@Native<Pointer<Opaque> Function(Int)>(
  symbol: 'litert_lm_sampler_params_create',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _samplerParamsCreate(int type);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_sampler_params_delete',
  assetId: _codeAssetName,
)
external void _samplerParamsDelete(Pointer<Opaque> params);

@Native<_SamplerParamsSetIntNative>(
  symbol: 'litert_lm_sampler_params_set_top_k',
  assetId: _codeAssetName,
)
external void _samplerParamsSetTopK(Pointer<Opaque> params, int topK);

@Native<_SamplerParamsSetFloatNative>(
  symbol: 'litert_lm_sampler_params_set_top_p',
  assetId: _codeAssetName,
)
external void _samplerParamsSetTopP(Pointer<Opaque> params, double topP);

@Native<_SamplerParamsSetFloatNative>(
  symbol: 'litert_lm_sampler_params_set_temperature',
  assetId: _codeAssetName,
)
external void _samplerParamsSetTemperature(
  Pointer<Opaque> params,
  double temperature,
);

@Native<_SamplerParamsSetIntNative>(
  symbol: 'litert_lm_sampler_params_set_seed',
  assetId: _codeAssetName,
)
external void _samplerParamsSetSeed(Pointer<Opaque> params, int seed);

@Native<_SessionConfigSetSamplerParamsNative>(
  symbol: 'litert_lm_session_config_set_sampler_params',
  assetId: _codeAssetName,
)
external void _sessionConfigSetSamplerParams(
  Pointer<Opaque> config,
  Pointer<Opaque> samplerParams,
);

@Native<_SessionConfigSetIntNative>(
  symbol: 'litert_lm_session_config_set_max_output_tokens',
  assetId: _codeAssetName,
)
external void _sessionConfigSetMaxOutputTokens(
  Pointer<Opaque> config,
  int maxOutputTokens,
);

@Native<_SessionConfigSetBoolNative>(
  symbol: 'litert_lm_session_config_set_apply_prompt_template',
  assetId: _codeAssetName,
)
external void _sessionConfigSetApplyPromptTemplate(
  Pointer<Opaque> config,
  bool applyPromptTemplate,
);

@Native<_SessionConfigSetLoraPathNative>(
  symbol: 'litert_lm_session_config_set_lora_path',
  assetId: _codeAssetName,
)
external int _sessionConfigSetLoraPath(
  Pointer<Opaque> config,
  Pointer<Utf8> loraPath,
);

@Native<_SessionConfigSetLoraPathNative>(
  symbol: 'litert_lm_session_config_set_audio_lora_path',
  assetId: _codeAssetName,
)
external int _sessionConfigSetAudioLoraPath(
  Pointer<Opaque> config,
  Pointer<Utf8> audioLoraPath,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_session_config_delete',
  assetId: _codeAssetName,
)
external void _sessionConfigDelete(Pointer<Opaque> config);

@Native<Pointer<Opaque> Function()>(
  symbol: 'litert_lm_conversation_config_create',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _conversationConfigCreate();

@Native<_ConversationConfigSetSessionConfigNative>(
  symbol: 'litert_lm_conversation_config_set_session_config',
  assetId: _codeAssetName,
)
external void _conversationConfigSetSessionConfig(
  Pointer<Opaque> config,
  Pointer<Opaque> sessionConfig,
);

@Native<_ConversationConfigSetJsonNative>(
  symbol: 'litert_lm_conversation_config_set_system_message',
  assetId: _codeAssetName,
)
external void _conversationConfigSetSystemMessage(
  Pointer<Opaque> config,
  Pointer<Utf8> systemMessageJson,
);

@Native<_ConversationConfigSetJsonNative>(
  symbol: 'litert_lm_conversation_config_set_messages',
  assetId: _codeAssetName,
)
external void _conversationConfigSetMessages(
  Pointer<Opaque> config,
  Pointer<Utf8> messagesJson,
);

@Native<_ConversationConfigSetJsonNative>(
  symbol: 'litert_lm_conversation_config_set_tools',
  assetId: _codeAssetName,
)
external void _conversationConfigSetTools(
  Pointer<Opaque> config,
  Pointer<Utf8> toolsJson,
);

@Native<_ConversationConfigSetJsonNative>(
  symbol: 'litert_lm_conversation_config_set_extra_context',
  assetId: _codeAssetName,
)
external void _conversationConfigSetExtraContext(
  Pointer<Opaque> config,
  Pointer<Utf8> extraContextJson,
);

@Native<_ConversationConfigSetBoolNative>(
  symbol: 'litert_lm_conversation_config_set_enable_constrained_decoding',
  assetId: _codeAssetName,
)
external void _conversationConfigSetEnableConstrainedDecoding(
  Pointer<Opaque> config,
  bool enableConstrainedDecoding,
);

@Native<_ConversationConfigSetBoolNative>(
  symbol:
      'litert_lm_conversation_config_set_filter_channel_content_from_kv_cache',
  assetId: _codeAssetName,
)
external void _conversationConfigSetFilterChannelContentFromKvCache(
  Pointer<Opaque> config,
  bool filterChannelContentFromKvCache,
);

@Native<_ConversationConfigSetStreamToolCallsNative>(
  symbol: 'litert_lm_conversation_config_set_stream_tool_calls',
  assetId: _codeAssetName,
)
external void _conversationConfigSetStreamToolCalls(
  Pointer<Opaque> config,
  bool streamToolCalls,
  Pointer<Utf8> channelName,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_conversation_config_delete',
  assetId: _codeAssetName,
)
external void _conversationConfigDelete(Pointer<Opaque> config);

@Native<Pointer<Opaque> Function()>(
  symbol: 'litert_lm_conversation_optional_args_create',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _conversationOptionalArgsCreate();

@Native<Void Function(Pointer<Opaque>, Int)>(
  symbol: 'litert_lm_conversation_optional_args_set_visual_token_budget',
  assetId: _codeAssetName,
)
external void _conversationOptionalArgsSetVisualTokenBudget(
  Pointer<Opaque> optionalArgs,
  int visualTokenBudget,
);

@Native<Void Function(Pointer<Opaque>, Int)>(
  symbol: 'litert_lm_conversation_optional_args_set_max_output_tokens',
  assetId: _codeAssetName,
)
external void _conversationOptionalArgsSetMaxOutputTokens(
  Pointer<Opaque> optionalArgs,
  int maxOutputTokens,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_conversation_optional_args_delete',
  assetId: _codeAssetName,
)
external void _conversationOptionalArgsDelete(Pointer<Opaque> optionalArgs);

@Native<_ConversationCreateNative>(
  symbol: 'litert_lm_conversation_create',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _conversationCreate(
  Pointer<Opaque> engine,
  Pointer<Opaque> config,
);

@Native<_GuardedConversationCreateNative>(
  symbol: 'litertlm_conversation_create_guarded',
  assetId: _nativeFfiSupportAssetName,
)
external Pointer<Opaque> _guardedConversationCreate(
  Pointer<NativeFunction<_ConversationCreateNative>> create,
  Pointer<Opaque> engine,
  Pointer<Opaque> config,
  Pointer<Int32> status,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_session_delete',
  assetId: _codeAssetName,
)
external void _sessionDelete(Pointer<Opaque> session);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_session_cancel_process',
  assetId: _codeAssetName,
)
external void _sessionCancelProcess(Pointer<Opaque> session);

@Native<_InputDataCreateNative>(
  symbol: 'litert_lm_input_data_create',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _inputDataCreate(
  int type,
  Pointer<Void> data,
  int size,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_input_data_delete',
  assetId: _codeAssetName,
)
external void _inputDataDelete(Pointer<Opaque> inputData);

@Native<_SessionRunPrefillNative>(
  symbol: 'litert_lm_session_run_prefill',
  assetId: _codeAssetName,
)
external int _sessionRunPrefill(
  Pointer<Opaque> session,
  Pointer<Pointer<Opaque>> inputs,
  int numInputs,
);

@Native<_SessionResponsesNative>(
  symbol: 'litert_lm_session_run_decode',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _sessionRunDecode(Pointer<Opaque> session);

@Native<_SessionGenerateContentNative>(
  symbol: 'litert_lm_session_generate_content',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _sessionGenerateContent(
  Pointer<Opaque> session,
  Pointer<Pointer<Opaque>> inputs,
  int numInputs,
);

@Native<_SessionGenerateContentStreamNative>(
  symbol: 'litert_lm_session_generate_content_stream',
  assetId: _codeAssetName,
)
external int _sessionGenerateContentStream(
  Pointer<Opaque> session,
  Pointer<Pointer<Opaque>> inputs,
  int numInputs,
  Pointer<NativeFunction<_StreamCallbackPointerNative>> callback,
  Pointer<Opaque> callbackData,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_responses_delete',
  assetId: _codeAssetName,
)
external void _responsesDelete(Pointer<Opaque> responses);

@Native<Int Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_responses_get_num_candidates',
  assetId: _codeAssetName,
)
external int _responsesGetNumCandidates(Pointer<Opaque> responses);

@Native<Pointer<Utf8> Function(Pointer<Opaque>, Int)>(
  symbol: 'litert_lm_responses_get_response_text_at',
  assetId: _codeAssetName,
)
external Pointer<Utf8> _responsesGetResponseTextAt(
  Pointer<Opaque> responses,
  int index,
);

@Native<_ConversationSendMessageNative>(
  symbol: 'litert_lm_conversation_send_message',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _conversationSendMessage(
  Pointer<Opaque> conversation,
  Pointer<Utf8> messageJson,
  Pointer<Utf8> extraContext,
  Pointer<Opaque> optionalArgs,
);

@Native<_ConversationSendMessageStreamNative>(
  symbol: 'litert_lm_conversation_send_message_stream',
  assetId: _codeAssetName,
)
external int _conversationSendMessageStream(
  Pointer<Opaque> conversation,
  Pointer<Utf8> messageJson,
  Pointer<Utf8> extraContext,
  Pointer<Opaque> optionalArgs,
  Pointer<NativeFunction<_StreamCallbackPointerNative>> callback,
  Pointer<Opaque> callbackData,
);

_StreamCallbackRegistration _createStreamCallbackRegistration(
  NativeCallable<_DartStreamCallbackNative> callback,
) {
  final context = _streamCallbackContextCreate(
    callback.nativeFunction,
    Native.addressOf<NativeFunction<_StreamChunkGetStringNative>>(
      _streamChunkGetText,
    ),
    Native.addressOf<NativeFunction<_StreamChunkIsFinalNative>>(
      _streamChunkIsFinal,
    ),
    Native.addressOf<NativeFunction<_StreamChunkGetStringNative>>(
      _streamChunkGetError,
    ),
  );
  if (context == nullptr) {
    callback.close();
    throw const LiteRtLmException(
      'Could not create LiteRT-LM stream callback context.',
    );
  }
  return _StreamCallbackRegistration(
    function: Native.addressOf<NativeFunction<_StreamChunkCallbackNative>>(
      _streamChunkCallbackBridge,
    ).cast(),
    data: context,
    context: context,
  );
}

@Native<Pointer<Utf8> Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_stream_chunk_get_text',
  assetId: _codeAssetName,
)
external Pointer<Utf8> _streamChunkGetText(Pointer<Opaque> chunk);

@Native<Bool Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_stream_chunk_is_final',
  assetId: _codeAssetName,
)
external bool _streamChunkIsFinal(Pointer<Opaque> chunk);

@Native<Pointer<Utf8> Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_stream_chunk_get_error',
  assetId: _codeAssetName,
)
external Pointer<Utf8> _streamChunkGetError(Pointer<Opaque> chunk);

@Native<
  Pointer<Opaque> Function(
    Pointer<NativeFunction<_DartStreamCallbackNative>>,
    Pointer<NativeFunction<_StreamChunkGetStringNative>>,
    Pointer<NativeFunction<_StreamChunkIsFinalNative>>,
    Pointer<NativeFunction<_StreamChunkGetStringNative>>,
  )
>(
  symbol: 'litertlm_stream_callback_context_create',
  assetId: _nativeFfiSupportAssetName,
)
external Pointer<Opaque> _streamCallbackContextCreate(
  Pointer<NativeFunction<_DartStreamCallbackNative>> callback,
  Pointer<NativeFunction<_StreamChunkGetStringNative>> getText,
  Pointer<NativeFunction<_StreamChunkIsFinalNative>> isFinal,
  Pointer<NativeFunction<_StreamChunkGetStringNative>> getError,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litertlm_stream_callback_context_delete',
  assetId: _nativeFfiSupportAssetName,
)
external void _streamCallbackContextDelete(Pointer<Opaque> context);

@Native<_ConversationRenderMessageToStringNative>(
  symbol: 'litert_lm_conversation_render_message_to_string',
  assetId: _codeAssetName,
)
external Pointer<Utf8> _conversationRenderMessageToString(
  Pointer<Opaque> conversation,
  Pointer<Utf8> messageJson,
);

@Native<_ConversationRenderPrefaceToStringNative>(
  symbol: 'litert_lm_conversation_render_preface_to_string',
  assetId: _codeAssetName,
)
external Pointer<Utf8> _conversationRenderPrefaceToString(
  Pointer<Opaque> conversation,
);

@Native<_StreamChunkCallbackNative>(
  symbol: 'litertlm_stream_callback_bridge',
  assetId: _nativeFfiSupportAssetName,
)
external void _streamChunkCallbackBridge(
  Pointer<Opaque> callbackData,
  Pointer<Opaque> chunk,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'litertlm_free',
  assetId: _nativeFfiSupportAssetName,
)
external void _nativeFree(Pointer<Void> pointer);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_conversation_cancel_process',
  assetId: _codeAssetName,
)
external void _conversationCancelProcess(Pointer<Opaque> conversation);

@Native<Int Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_conversation_get_token_count',
  assetId: _codeAssetName,
)
external int _conversationGetTokenCount(Pointer<Opaque> conversation);

@Native<Pointer<Opaque> Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_conversation_get_benchmark_info',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _conversationGetBenchmarkInfo(
  Pointer<Opaque> conversation,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_benchmark_info_delete',
  assetId: _codeAssetName,
)
external void _benchmarkInfoDelete(Pointer<Opaque> benchmarkInfo);

@Native<_BenchmarkInfoGetValueNative>(
  symbol: 'litert_lm_benchmark_info_get_time_to_first_token',
  assetId: _codeAssetName,
)
external double _benchmarkInfoGetTimeToFirstToken(
  Pointer<Opaque> benchmarkInfo,
);

@Native<_BenchmarkInfoGetValueNative>(
  symbol: 'litert_lm_benchmark_info_get_total_init_time_in_second',
  assetId: _codeAssetName,
)
external double _benchmarkInfoGetTotalInitTimeInSecond(
  Pointer<Opaque> benchmarkInfo,
);

@Native<_BenchmarkInfoGetCountNative>(
  symbol: 'litert_lm_benchmark_info_get_num_prefill_turns',
  assetId: _codeAssetName,
)
external int _benchmarkInfoGetNumPrefillTurns(Pointer<Opaque> benchmarkInfo);

@Native<_BenchmarkInfoGetCountNative>(
  symbol: 'litert_lm_benchmark_info_get_num_decode_turns',
  assetId: _codeAssetName,
)
external int _benchmarkInfoGetNumDecodeTurns(Pointer<Opaque> benchmarkInfo);

@Native<_BenchmarkInfoGetCountAtNative>(
  symbol: 'litert_lm_benchmark_info_get_prefill_token_count_at',
  assetId: _codeAssetName,
)
external int _benchmarkInfoGetPrefillTokenCountAt(
  Pointer<Opaque> benchmarkInfo,
  int index,
);

@Native<_BenchmarkInfoGetCountAtNative>(
  symbol: 'litert_lm_benchmark_info_get_decode_token_count_at',
  assetId: _codeAssetName,
)
external int _benchmarkInfoGetDecodeTokenCountAt(
  Pointer<Opaque> benchmarkInfo,
  int index,
);

@Native<_BenchmarkInfoGetValueAtNative>(
  symbol: 'litert_lm_benchmark_info_get_prefill_tokens_per_sec_at',
  assetId: _codeAssetName,
)
external double _benchmarkInfoGetPrefillTokensPerSecondAt(
  Pointer<Opaque> benchmarkInfo,
  int index,
);

@Native<_BenchmarkInfoGetValueAtNative>(
  symbol: 'litert_lm_benchmark_info_get_decode_tokens_per_sec_at',
  assetId: _codeAssetName,
)
external double _benchmarkInfoGetDecodeTokensPerSecondAt(
  Pointer<Opaque> benchmarkInfo,
  int index,
);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_conversation_delete',
  assetId: _codeAssetName,
)
external void _conversationDelete(Pointer<Opaque> conversation);

@Native<Pointer<Utf8> Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_json_response_get_string',
  assetId: _codeAssetName,
)
external Pointer<Utf8> _jsonResponseGetString(Pointer<Opaque> response);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_json_response_delete',
  assetId: _codeAssetName,
)
external void _jsonResponseDelete(Pointer<Opaque> response);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_engine_delete',
  assetId: _codeAssetName,
)
external void _engineDelete(Pointer<Opaque> engine);

@Native<Void Function(Int)>(
  symbol: 'litert_lm_set_min_log_level',
  assetId: _codeAssetName,
)
external void _setMinimumLogLevel(int level);

@Native<Pointer<Opaque> Function(Pointer<Utf8>)>(
  symbol: 'litert_lm_loaded_file_create',
  assetId: _codeAssetName,
)
external Pointer<Opaque> _loadedFileCreate(Pointer<Utf8> modelPath);

@Native<Void Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_loaded_file_delete',
  assetId: _codeAssetName,
)
external void _loadedFileDelete(Pointer<Opaque> loadedFile);

@Native<Bool Function(Pointer<Opaque>)>(
  symbol: 'litert_lm_loaded_file_has_speculative_decoding_support',
  assetId: _codeAssetName,
)
external bool _loadedFileHasSpeculativeDecodingSupport(
  Pointer<Opaque> loadedFile,
);
