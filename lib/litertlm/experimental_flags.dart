import '../native/runtime.dart';

/// Experimental flags for LiteRT-LM.
///
/// These flags guard APIs that are not yet considered mature and may change or
/// be removed without notice.
final class ExperimentalFlags {
  const ExperimentalFlags._();

  /// Whether benchmark collection is enabled.
  ///
  /// This flag is read when a new [Engine] is created. Changing this value does
  /// not affect existing [Engine] or [Conversation] instances.
  static bool get enableBenchmark =>
      LiteRtLmNativeRuntime.instance.enableBenchmark;

  static set enableBenchmark(bool value) {
    LiteRtLmNativeRuntime.instance.enableBenchmark = value;
  }

  /// Whether speculative decoding is enabled.
  ///
  /// If null, uses the model default. If true, enables speculative decoding; an
  /// error is thrown if the model does not support it. If false, disables
  /// speculative decoding.
  ///
  /// This flag is read when a new [Engine] is created. Changing this value does
  /// not affect existing [Engine] or [Conversation] instances.
  static bool? get enableSpeculativeDecoding =>
      LiteRtLmNativeRuntime.instance.enableSpeculativeDecoding;

  static set enableSpeculativeDecoding(bool? value) {
    LiteRtLmNativeRuntime.instance.enableSpeculativeDecoding = value;
  }

  /// Whether conversation constrained decoding is enabled.
  ///
  /// This is primarily used for function calling.
  ///
  /// This flag is read when a new [Conversation] is created. Changing this
  /// value does not affect existing [Conversation] instances.
  static bool get enableConversationConstrainedDecoding =>
      LiteRtLmNativeRuntime.instance.enableConversationConstrainedDecoding;

  static set enableConversationConstrainedDecoding(bool value) {
    LiteRtLmNativeRuntime.instance.enableConversationConstrainedDecoding =
        value;
  }

  /// Whether tool-call tokens are emitted while responses are streaming.
  ///
  /// Token fragments are emitted in [Message.channels] using
  /// [conversationToolCallStreamingChannelName] as the key. The runtime emits
  /// the complete call in [Message.toolCalls] when ready. With automatic tool
  /// calling enabled, the complete call is consumed and executed before being
  /// forwarded to the caller.
  ///
  /// This flag is read when a new [Conversation] is created.
  static bool get enableConversationToolCallStreaming =>
      LiteRtLmNativeRuntime.instance.enableConversationToolCallStreaming;

  static set enableConversationToolCallStreaming(bool value) {
    LiteRtLmNativeRuntime.instance.enableConversationToolCallStreaming = value;
  }

  /// The [Message.channels] key used for streamed tool-call token fragments.
  ///
  /// This value is read when a new [Conversation] is created.
  static String get conversationToolCallStreamingChannelName =>
      LiteRtLmNativeRuntime.instance.conversationToolCallStreamingChannelName;

  static set conversationToolCallStreamingChannelName(String value) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Must not be empty.');
    }
    LiteRtLmNativeRuntime.instance.conversationToolCallStreamingChannelName =
        value;
  }

  /// Whether channel content is filtered from the KV cache.
  ///
  /// If null, uses the model or runtime default. If true, channel content
  /// (e.g. reasoning) will be filtered from the KV cache. If false, channel
  /// content remains in the KV cache.
  ///
  /// Note: This flag is read only when a new [Conversation] is created.
  /// Changing this value will not affect any existing [Conversation]
  /// instances.
  static bool? get filterChannelContentFromKvCache =>
      LiteRtLmNativeRuntime.instance.filterChannelContentFromKvCache;

  static set filterChannelContentFromKvCache(bool? value) {
    LiteRtLmNativeRuntime.instance.filterChannelContentFromKvCache = value;
  }

  /// The visual token budget.
  ///
  /// The number of visual tokens that the model can generate for a single
  /// image. If null, uses the model or runtime default.
  ///
  /// On native platforms, a positive value set before creating and initializing
  /// an engine also sets its maximum visual tokens per image. Later changes
  /// affect subsequent messages but must not exceed that engine's maximum.
  /// This flag is supported by Gemma 4 and is not supported on web.
  static int? get visualTokenBudget =>
      LiteRtLmNativeRuntime.instance.visualTokenBudget;

  static set visualTokenBudget(int? value) {
    LiteRtLmNativeRuntime.instance.visualTokenBudget = value;
  }
}
