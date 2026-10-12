import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

// ---------- محلل الروابط: يستخرج رابط الفيديو الفعلي داخل التطبيق ----------
final _dio = Dio(BaseOptions(
  followRedirects: true,
  connectTimeout: const Duration(seconds: 15),
  receiveTimeout: const Duration(seconds: 20),
  headers: {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0 Mobile Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9,ar;q=0.8',
  },
));

final _cache = <String, String>{};

Future<String> resolveVideoUrl(String input) async {
  if (_cache.containsKey(input)) return _cache[input]!;
  final u = Uri.parse(input);
  if (u.host.contains('youtube.com') || u.host.contains('youtu.be')) {
    throw 'روابط يوتيوب تُضاف من صفحة شورتس';
  }
  // رابط مباشر
  if (RegExp(r'\.(mp4|m4v|mov|webm|m3u8)(\?|$)', caseSensitive: false)
      .hasMatch(u.path)) {
    return _cache[input] = input;
  }
  // نجلب الصفحة ونبحث عن الفيديو في مصدرها
  final res = await _dio.get<String>(input,
      options: Options(responseType: ResponseType.plain));
  final html = (res.data ?? '')
      .replaceAll(r'\/', '/')
      .replaceAll(r'\u0026', '&')
      .replaceAll(r'\u002F', '/')
      .replaceAll('&amp;', '&');
  final patterns = <RegExp>[
    RegExp(r'''<meta[^>]+property=["']og:video(?::secure_url|:url)?["'][^>]+content=["']([^"']+)["']''',
        caseSensitive: false),
    RegExp(r'''<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:video''',
        caseSensitive: false),
    RegExp(r'''<video[^>]+src=["']([^"']+)["']''', caseSensitive: false),
    RegExp(r'''<source[^>]+src=["']([^"']+)["']''', caseSensitive: false),
    RegExp(r'''https?://[^"'\s<>\\]+\.mp4[^"'\s<>\\]*'''),
    RegExp(r'''https?://[^"'\s<>\\]+\.m3u8[^"'\s<>\\]*'''),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(html);
    if (m != null) {
      final found = m.groupCount >= 1 ? m.group(1)! : m.group(0)!;
      final abs = u.resolve(found).toString();
      return _cache[input] = abs;
    }
  }
  throw 'ما قدرت أجد فيديو في هذا الرابط (قد يكون محمياً)';
}

void main() => runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const Home()));

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int i = 0;
  final pages = const [LinksPage(), PhonePage(), ShortsPage()];
  @override
  Widget build(BuildContext c) => Scaffold(
        body: IndexedStack(index: i, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => setState(() => i = v),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.link), label: 'روابطي'),
            NavigationDestination(
                icon: Icon(Icons.phone_android), label: 'هاتفي'),
            NavigationDestination(
                icon: Icon(Icons.play_circle), label: 'شورتس'),
          ],
        ),
      );
}

// ---------- مشغل عمودي مشترك ----------
class Reel extends StatefulWidget {
  final Future<VideoPlayerController> Function() make;
  final Future<void> Function() onDownload;
  const Reel({super.key, required this.make, required this.onDownload});
  @override
  State<Reel> createState() => _ReelState();
}

class _ReelState extends State<Reel> {
  VideoPlayerController? c;
  bool busy = false;
  String? err;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final v = await widget.make();
        c = v;
        await v.initialize();
        v.setLooping(true);
        if (mounted) {
          setState(() {});
          v.play();
        }
      } catch (e) {
        if (mounted) setState(() => err = '$e');
      }
    }();
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = c;
    if (err != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(err!, textAlign: TextAlign.center)));
    }
    if (v == null || !v.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(fit: StackFit.expand, children: [
      GestureDetector(
        onTap: () => setState(() => v.value.isPlaying ? v.pause() : v.play()),
        child: Center(
            child: AspectRatio(
                aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))),
      ),
      Positioned(
        right: 16,
        bottom: 40,
        child: busy
            ? const CircularProgressIndicator()
            : IconButton.filled(
                icon: const Icon(Icons.download),
                onPressed: () async {
                  setState(() => busy = true);
                  try {
                    await widget.onDownload();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم الحفظ في المعرض')));
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('فشل التحميل: $e')));
                    }
                  }
                  if (mounted) setState(() => busy = false);
                },
              ),
      ),
    ]);
  }
}

// ---------- 1) روابطي ----------
class LinksPage extends StatefulWidget {
  const LinksPage({super.key});
  @override
  State<LinksPage> createState() => _LinksPageState();
}

class _LinksPageState extends State<LinksPage> {
  final urls = <String>[];
  final ctl = TextEditingController();

  Future<void> download(String link) async {
    final url = await resolveVideoUrl(link);
    if (url.toLowerCase().contains('.m3u8')) {
      throw 'هذا بث مجزأ (m3u8) ولا يمكن تحميله مباشرة';
    }
    final p =
        '${(await getTemporaryDirectory()).path}/${DateTime.now().millisecondsSinceEpoch}.mp4';
    await _dio.download(url, p);
    await Gal.putVideo(p);
  }

  @override
  Widget build(BuildContext c) => SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: ctl,
                      decoration: const InputDecoration(
                          hintText: 'الصق رابط الفيديو أو الصفحة'))),
              IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final u = ctl.text.trim();
                    if (u.isNotEmpty) setState(() => urls.add(u));
                    ctl.clear();
                  }),
            ]),
          ),
          Expanded(
            child: urls.isEmpty
                ? const Center(child: Text('أضف رابطاً للبدء'))
                : PageView.builder(
                    scrollDirection: Axis.vertical,
                    itemCount: urls.length,
                    itemBuilder: (_, k) => Reel(
                      key: ValueKey(urls[k]),
                      make: () async => VideoPlayerController.networkUrl(
                          Uri.parse(await resolveVideoUrl(urls[k]))),
                      onDownload: () => download(urls[k]),
                    ),
                  ),
          ),
        ]),
      );
}

// ---------- 2) هاتفي ----------
class PhonePage extends StatefulWidget {
  const PhonePage({super.key});
  @override
  State<PhonePage> createState() => _PhonePageState();
}

class _PhonePageState extends State<PhonePage> {
  List<AssetEntity> items = [];
  String? msg = 'جاري التحميل...';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final ps = await PhotoManager.requestPermissionExtend();
    if (!ps.hasAccess) {
      setState(() => msg = 'لازم تسمح بالوصول للفيديوهات');
      return;
    }
    final paths = await PhotoManager.getAssetPathList(
        type: RequestType.video, onlyAll: true);
    if (paths.isEmpty) {
      setState(() => msg = 'لا توجد فيديوهات');
      return;
    }
    final total = await paths.first.assetCountAsync;
    final all = await paths.first.getAssetListRange(start: 0, end: total);
    setState(() {
      items = all;
      msg = null;
    });
  }

  @override
  Widget build(BuildContext c) {
    if (msg != null) return Center(child: Text(msg!));
    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: items.length,
      itemBuilder: (_, k) => Reel(
        key: ValueKey(items[k].id),
        make: () async =>
            VideoPlayerController.file((await items[k].file) as File),
        onDownload: () async {
          final f = await items[k].file;
          await Gal.putVideo(f!.path);
        },
      ),
    );
  }
}

// ---------- 3) شورتس يوتيوب (تشغيل رسمي فقط) ----------
class ShortsPage extends StatefulWidget {
  const ShortsPage({super.key});
  @override
  State<ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<ShortsPage> {
  final ids = <String>[];
  final ctl = TextEditingController();

  String? extract(String s) {
    final m = RegExp(r'(?:shorts/|v=|youtu\.be/)([\w-]{11})').firstMatch(s);
    if (m != null) return m.group(1);
    return s.length == 11 ? s : null;
  }

  @override
  Widget build(BuildContext c) => SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: ctl,
                      decoration: const InputDecoration(
                          hintText: 'رابط يوتيوب شورتس'))),
              IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final id = extract(ctl.text.trim());
                    if (id != null) setState(() => ids.add(id));
                    ctl.clear();
                  }),
            ]),
          ),
          Expanded(
            child: ids.isEmpty
                ? const Center(child: Text('أضف رابط شورتس'))
                : PageView.builder(
                    scrollDirection: Axis.vertical,
                    itemCount: ids.length,
                    itemBuilder: (_, k) => _YtItem(id: ids[k]),
                  ),
          ),
        ]),
      );
}

class _YtItem extends StatefulWidget {
  final String id;
  const _YtItem({required this.id});
  @override
  State<_YtItem> createState() => _YtItemState();
}

class _YtItemState extends State<_YtItem> {
  late final YoutubePlayerController c = YoutubePlayerController.fromVideoId(
      videoId: widget.id,
      autoPlay: true,
      params: const YoutubePlayerParams(loop: true, showFullscreenButton: false));
  @override
  void dispose() {
    c.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: YoutubePlayer(controller: c, aspectRatio: 9 / 16));
}
