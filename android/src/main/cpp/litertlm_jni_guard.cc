#include <dlfcn.h>
#include <jni.h>

#include <array>
#include <cstddef>
#include <new>

#include "native_error.h"

namespace {

constexpr std::size_t kOperationCount = 3;

using CreateEngine = jlong(JNICALL*)(
    JNIEnv*, jobject, jstring, jstring, jstring, jstring, jint, jint, jstring,
  jboolean, jobject, jstring, jstring, jstring, jint, jint, jint);
using CreateBenchmark = jlong(JNICALL*)(JNIEnv*, jobject, jstring, jstring,
                                        jint, jint, jstring, jstring, jobject);
using CreateConversation = jlong(JNICALL*)(
    JNIEnv*, jobject, jlong, jobject, jstring, jstring, jstring, jstring,
    jboolean, jobject, jstring, jstring, jstring, jboolean, jint, jobject,
    jboolean);
using CreateSession = jlong(JNICALL*)(JNIEnv*, jobject, jlong, jobject,
                                      jstring, jstring);

CreateEngine original_create_engine = nullptr;
CreateBenchmark original_create_benchmark = nullptr;
CreateConversation original_create_conversation = nullptr;
CreateSession original_create_session = nullptr;
std::array<jthrowable, kOperationCount> out_of_memory_exceptions{};
std::array<jthrowable, kOperationCount> unexpected_exceptions{};
bool installed = false;

void ThrowInstallError(JNIEnv* env) {
  if (env->ExceptionCheck()) {
    return;
  }
  jclass exception_class = env->FindClass("java/lang/IllegalStateException");
  if (exception_class != nullptr) {
    env->ThrowNew(exception_class, "Could not install LiteRT-LM JNI guards.");
    env->DeleteLocalRef(exception_class);
  }
}

template <typename Function>
bool LoadFunction(void* library, const char* symbol, Function& function) {
  function = reinterpret_cast<Function>(dlsym(library, symbol));
  return function != nullptr;
}

bool CreateGuardExceptions(JNIEnv* env) {
  jclass exception_class =
      env->FindClass("org/rockstudio/litertlm/LiteRtLmJniNativeException");
  if (exception_class == nullptr) {
    return false;
  }
  jmethodID constructor = env->GetMethodID(exception_class, "<init>", "(II)V");
  if (constructor == nullptr) {
    env->DeleteLocalRef(exception_class);
    return false;
  }

  for (jint operation = 0; operation < kOperationCount; ++operation) {
    jobject out_of_memory =
      env->NewObject(exception_class, constructor,
               litertlm::kNativeCallOutOfMemory, operation);
    if (out_of_memory == nullptr) {
      env->DeleteLocalRef(exception_class);
      return false;
    }
    out_of_memory_exceptions[operation] = static_cast<jthrowable>(
        env->NewGlobalRef(out_of_memory));
    env->DeleteLocalRef(out_of_memory);
    if (out_of_memory_exceptions[operation] == nullptr) {
      env->DeleteLocalRef(exception_class);
      return false;
    }

    jobject unexpected = env->NewObject(exception_class, constructor,
                                        litertlm::kNativeCallUnexpectedException,
                                        operation);
    if (unexpected == nullptr) {
      env->DeleteLocalRef(exception_class);
      return false;
    }
    unexpected_exceptions[operation] =
        static_cast<jthrowable>(env->NewGlobalRef(unexpected));
    env->DeleteLocalRef(unexpected);
    if (unexpected_exceptions[operation] == nullptr) {
      env->DeleteLocalRef(exception_class);
      return false;
    }
  }

  env->DeleteLocalRef(exception_class);
  return true;
}

void ThrowNativeException(JNIEnv* env, jint code, jint operation) noexcept {
  if (env->ExceptionCheck()) {
    env->ExceptionClear();
  }
  const std::size_t index =
      operation >= 0 && operation < kOperationCount
          ? static_cast<std::size_t>(operation)
          : static_cast<std::size_t>(litertlm::kEngineInitialization);
      jthrowable exception = code == litertlm::kNativeCallOutOfMemory
                             ? out_of_memory_exceptions[index]
                             : unexpected_exceptions[index];
  if (exception != nullptr) {
    env->Throw(exception);
  }
}

template <typename Function, typename... Args>
jlong Guard(JNIEnv* env, jobject receiver, jint operation, Function function,
            Args... args) noexcept {
  try {
    return function(env, receiver, args...);
  } catch (const std::bad_alloc&) {
    ThrowNativeException(env, litertlm::kNativeCallOutOfMemory, operation);
  } catch (...) {
    ThrowNativeException(env, litertlm::kNativeCallUnexpectedException,
                         operation);
  }
  return 0;
}

jlong JNICALL GuardedCreateEngine(
    JNIEnv* env, jobject receiver, jstring model_path, jstring backend,
    jstring vision_backend, jstring audio_backend, jint max_num_tokens,
    jint max_num_images, jstring cache_dir, jboolean enable_benchmark,
    jobject enable_speculative_decoding, jstring main_npu_library_dir,
    jstring vision_npu_library_dir, jstring audio_npu_library_dir,
    jint main_backend_num_threads, jint audio_backend_num_threads,
    jint max_vision_tokens_per_image) noexcept {
  return Guard(env, receiver, litertlm::kEngineInitialization,
               original_create_engine,
               model_path, backend, vision_backend, audio_backend,
               max_num_tokens, max_num_images, cache_dir, enable_benchmark,
               enable_speculative_decoding, main_npu_library_dir,
               vision_npu_library_dir, audio_npu_library_dir,
               main_backend_num_threads, audio_backend_num_threads,
               max_vision_tokens_per_image);
}

jlong JNICALL GuardedCreateBenchmark(
    JNIEnv* env, jobject receiver, jstring model_path, jstring backend,
    jint prefill_tokens, jint decode_tokens, jstring cache_dir,
    jstring main_npu_library_dir,
    jobject enable_speculative_decoding) noexcept {
  return Guard(env, receiver, litertlm::kEngineInitialization,
               original_create_benchmark, model_path, backend, prefill_tokens,
               decode_tokens, cache_dir, main_npu_library_dir,
               enable_speculative_decoding);
}

jlong JNICALL GuardedCreateConversation(
    JNIEnv* env, jobject receiver, jlong engine, jobject sampler_config,
    jstring messages_json, jstring tools_json, jstring channels_json,
    jstring extra_context_json, jboolean enable_constrained_decoding,
    jobject filter_channel_content_from_kv_cache,
    jstring overwrite_prompt_template, jstring lora_path,
    jstring audio_lora_path, jboolean prefill_preface_on_init,
    jint max_output_tokens, jobject thinking_config,
    jboolean enable_response_format) noexcept {
  return Guard(
      env, receiver, litertlm::kConversationCreation,
      original_create_conversation,
      engine, sampler_config, messages_json, tools_json, channels_json,
      extra_context_json, enable_constrained_decoding,
      filter_channel_content_from_kv_cache, overwrite_prompt_template,
      lora_path, audio_lora_path, prefill_preface_on_init, max_output_tokens,
      thinking_config, enable_response_format);
}

jlong JNICALL GuardedCreateSession(JNIEnv* env, jobject receiver, jlong engine,
                                   jobject sampler_config, jstring lora_path,
                                   jstring audio_lora_path) noexcept {
  return Guard(env, receiver, litertlm::kSessionCreation,
               original_create_session,
               engine, sampler_config, lora_path, audio_lora_path);
}

}  // namespace

extern "C" JNIEXPORT void JNICALL
Java_org_rockstudio_litertlm_LiteRtLmJniNativeGuard_install(JNIEnv* env,
                                                            jclass) {
  if (installed) {
    return;
  }

  void* library = dlopen("liblitertlm_jni.so", RTLD_NOW);
  if (library == nullptr ||
      !LoadFunction(
          library,
          "Java_com_google_ai_edge_litertlm_LiteRtLmJni_nativeCreateEngine",
          original_create_engine) ||
      !LoadFunction(
          library,
          "Java_com_google_ai_edge_litertlm_LiteRtLmJni_nativeCreateBenchmark",
          original_create_benchmark) ||
      !LoadFunction(
          library,
          "Java_com_google_ai_edge_litertlm_LiteRtLmJni_nativeCreateConversation",
          original_create_conversation) ||
      !LoadFunction(
          library,
          "Java_com_google_ai_edge_litertlm_LiteRtLmJni_nativeCreateSession",
          original_create_session) ||
      !CreateGuardExceptions(env)) {
    ThrowInstallError(env);
    return;
  }

  jclass target =
      env->FindClass("com/google/ai/edge/litertlm/LiteRtLmJni");
  if (target == nullptr) {
    ThrowInstallError(env);
    return;
  }

  JNINativeMethod methods[] = {
      {const_cast<char*>("nativeCreateEngine"),
       const_cast<char*>(
         "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;IILjava/lang/String;ZLjava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;III)J"),
       reinterpret_cast<void*>(&GuardedCreateEngine)},
      {const_cast<char*>("nativeCreateBenchmark"),
       const_cast<char*>(
           "(Ljava/lang/String;Ljava/lang/String;IILjava/lang/String;Ljava/lang/String;Ljava/lang/Boolean;)J"),
       reinterpret_cast<void*>(&GuardedCreateBenchmark)},
      {const_cast<char*>("nativeCreateConversation"),
       const_cast<char*>(
           "(JLcom/google/ai/edge/litertlm/SamplerConfig;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZLjava/lang/Boolean;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZILcom/google/ai/edge/litertlm/ThinkingConfig;Z)J"),
       reinterpret_cast<void*>(&GuardedCreateConversation)},
      {const_cast<char*>("nativeCreateSession"),
       const_cast<char*>(
           "(JLcom/google/ai/edge/litertlm/SamplerConfig;Ljava/lang/String;Ljava/lang/String;)J"),
       reinterpret_cast<void*>(&GuardedCreateSession)},
  };

  if (env->RegisterNatives(target, methods,
                           sizeof(methods) / sizeof(methods[0])) != JNI_OK) {
    env->DeleteLocalRef(target);
    ThrowInstallError(env);
    return;
  }

  env->DeleteLocalRef(target);
  installed = true;
}