import 'dart:io';
import 'dart:isolate';

const _partSizeBytes = 512 * 1024 * 1024;
const _liteRtLmVersion = 'v0.17.0';
const _baseUrl =
    'https://raw.githubusercontent.com/google-ai-edge/LiteRT-LM/$_liteRtLmVersion';
const _gemma4BaseUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main';
const _assets = [
  (
    url: '$_baseUrl/runtime/testdata/test_lm.litertlm',
    path: 'example/assets/models/test_lm.litertlm',
  ),
  (
    url: '$_gemma4BaseUrl/gemma-4-E2B-it.litertlm',
    path: 'example/assets/models/gemma-4-E2B-it.litertlm',
  ),
  (
    url: '$_gemma4BaseUrl/gemma-4-E2B-it-web.litertlm',
    path: 'example/assets/models/gemma-4-E2B-it-web.litertlm',
  ),
  (
    url: '$_baseUrl/runtime/testdata/colored_rect_163_586_615_957.jpg',
    path: 'example/assets/images/colored_rect_163_586_615_957.jpg',
  ),
  (
    url: '$_baseUrl/runtime/testdata/have_a_wonderful_day.wav',
    path: 'example/assets/audio/have_a_wonderful_day.wav',
  ),
];

Future<void> main() async {
  final scriptUri =
      await Isolate.resolvePackageUri(Platform.script) ?? Platform.script;
  final client = HttpClient();
  try {
    for (final asset in _assets) {
      final url = Uri.parse(asset.url);
      final file = File.fromUri(scriptUri.resolve('../${asset.path}'));
      await file.parent.create(recursive: true);

      if (!file.existsSync() || file.lengthSync() == 0) {
        final request = await client.getUrl(url);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Failed to download ${asset.url}', uri: url);
        }
        await response.pipe(file.openWrite());
      }
      await _cutIntoPartsIfNeeded(file);
    }
  } finally {
    client.close();
  }
}

Future<void> _cutIntoPartsIfNeeded(File file) async {
  final length = await file.length();
  if (length <= _partSizeBytes) return;

  var start = 0;
  var index = 0;
  while (start < length) {
    final end = start + _partSizeBytes > length
        ? length
        : start + _partSizeBytes;
    await file
        .openRead(start, end)
        .pipe(File('${file.path}.$index.part').openWrite());
    start = end;
    index += 1;
  }
}
