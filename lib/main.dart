import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const R4MApp());
}

const Color bg = Color(0xFF0B0E14);
const Color panel = Color(0xFF131923);
const Color purple = Color(0xFFA78BFA);
const Color muted = Color(0xFF929BAD);

class R4MApp extends StatelessWidget {
  const R4MApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'R4M Downloader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
          brightness: Brightness.dark,
          surface: panel,
        ),
        useMaterial3: true,
        fontFamily: 'Arial',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0D131D),
          hintStyle: const TextStyle(color: muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2B3545)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2B3545)),
          ),
        ),
      ),
      home: const DownloaderPage(),
    );
  }
}

class DownloaderPage extends StatefulWidget {
  const DownloaderPage({super.key});

  @override
  State<DownloaderPage> createState() => _DownloaderPageState();
}

class _DownloaderPageState extends State<DownloaderPage> {
  final _url = TextEditingController();
  final _dio = Dio();
  String _quality = '1080p';
  String _format = 'MP4';
  bool _playlist = false;
  bool _busy = false;
  double _progress = 0;
  String _status = 'Ready for a link';
  String _log = 'R4M Downloader initialized.';
  String? _savedPath;
  Process? _process;
  CancelToken? _cancelToken;

  bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() => _log = '${DateTime.now().toLocal().toString().substring(11, 19)}  $line\n$_log');
  }

  Future<Directory> _downloadDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}R4M Downloads');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _safeFilename(String input) {
    final cleaned = input.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return cleaned.isEmpty ? 'r4m_download' : cleaned;
  }

  Future<void> _start() async {
    final url = _url.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !['http', 'https'].contains(uri.scheme)) {
      _message('Enter a valid http:// or https:// URL.');
      return;
    }
    if (_mobile && _playlist) {
      _message('Playlist mode is currently available through the desktop yt-dlp engine only.');
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Preparing download…';
      _savedPath = null;
    });
    _appendLog('Starting ${_mobile ? "direct media" : "desktop yt-dlp"} download.');

    try {
      if (_desktop) {
        await _downloadWithYtDlp(url);
      } else if (_mobile) {
        await _downloadDirect(url);
      } else {
        throw UnsupportedError('This platform is not supported.');
      }
    } catch (e) {
      _appendLog('ERROR: $e');
      if (mounted) setState(() => _status = 'Download failed');
      _message('Download failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _process = null;
      _cancelToken = null;
    }
  }

  Future<void> _downloadWithYtDlp(String url) async {
    final dir = await _downloadDirectory();
    final height = switch (_quality) {
      '720p' => '720',
      '1080p' => '1080',
      '1440p' => '1440',
      '2160p' => '2160',
      _ => '99999',
    };
    final args = <String>[
      '--newline',
      '--progress',
      '--windows-filenames',
      '-o',
      '${dir.path}${Platform.pathSeparator}%(title).180B [%(id)s].%(ext)s',
    ];
    if (!_playlist) args.add('--no-playlist');
    if (_format == 'MP3') {
      args.addAll(['-f', 'bestaudio/best', '-x', '--audio-format', 'mp3', '--audio-quality', '192K']);
    } else {
      args.addAll([
        '-f',
        'bestvideo[height<=$height]+bestaudio/best[height<=$height]/best',
        '--merge-output-format',
        _format.toLowerCase(),
      ]);
    }
    args.add(url);

    final executable = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
    _appendLog('Launching $executable. Make sure yt-dlp is installed and on PATH.');
    final process = await Process.start(executable, args, runInShell: Platform.isWindows);
    _process = process;

    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _appendLog(line);
      final match = RegExp(r'(\d+(?:\.\d+)?)%').firstMatch(line);
      if (match != null && mounted) {
        final value = double.tryParse(match.group(1)!) ?? 0;
        setState(() {
          _progress = (value / 100).clamp(0, 1);
          _status = 'Downloading… ${value.toStringAsFixed(1)}%';
        });
      }
    });
    process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((dynamic event) => _appendLog(event.toString()));

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      throw Exception('yt-dlp exited with code $exitCode. Check Activity for details.');
    }
    if (mounted) {
      setState(() {
        _progress = 1;
        _status = 'Download complete';
        _savedPath = dir.path;
      });
    }
    _appendLog('Saved files in ${dir.path}');
  }

  Future<void> _downloadDirect(String url) async {
    final uri = Uri.parse(url);
    final dir = await _downloadDirectory();
    final pathPart = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'download';
    final filename = _safeFilename(pathPart.contains('.') ? pathPart : '$pathPart.${_format.toLowerCase()}');
    final destination = '${dir.path}${Platform.pathSeparator}$filename';
    _cancelToken = CancelToken();

    await _dio.download(
      url,
      destination,
      cancelToken: _cancelToken,
      options: Options(
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 30),
        sendTimeout: const Duration(minutes: 2),
      ),
      onReceiveProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          if (total > 0) {
            _progress = (received / total).clamp(0, 1);
            _status = 'Downloading… ${(_progress * 100).toStringAsFixed(1)}%';
          } else {
            _status = 'Downloading… ${(received / (1024 * 1024)).toStringAsFixed(1)} MB';
          }
        });
      },
    );
    if (mounted) {
      setState(() {
        _progress = 1;
        _status = 'Download complete';
        _savedPath = destination;
      });
    }
    _appendLog('Saved direct media file to $destination');
  }

  Future<void> _cancel() async {
    _cancelToken?.cancel('Cancelled by user');
    final process = _process;
    if (process != null) {
      process.kill();
    }
    if (mounted) setState(() => _status = 'Cancellation requested');
    _appendLog('Cancellation requested.');
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  void dispose() {
    _url.dispose();
    _dio.close(force: true);
    _process?.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 720;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 18, vertical: 24),
              children: [
                _header(),
                const SizedBox(height: 22),
                _panel(
                  title: 'MEDIA LINK',
                  child: TextField(
                    controller: _url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'Paste a permitted video or direct media URL…',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _panel(title: 'DOWNLOAD SETTINGS', child: _settings(wide)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _start,
                        icon: const Icon(Icons.download_rounded),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Start download'),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: purple,
                          foregroundColor: const Color(0xFF140F24),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    if (_busy) ...[
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _cancel,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text('Cancel'),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                _panel(
                  title: 'DOWNLOAD PROGRESS',
                  trailing: Text('${(_progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: purple, fontWeight: FontWeight.bold)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 10,
                          backgroundColor: const Color(0xFF0A1018),
                          color: purple,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(_status, style: const TextStyle(color: muted)),
                      if (_savedPath != null) ...[
                        const SizedBox(height: 6),
                        SelectableText('Saved: $_savedPath',
                            style: const TextStyle(color: Color(0xFF67E2AD), fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _panel(
                  title: 'ACTIVITY',
                  trailing: IconButton(
                    tooltip: 'Clear activity',
                    onPressed: () => setState(() => _log = ''),
                    icon: const Icon(Icons.delete_outline, size: 19, color: muted),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 110, maxHeight: 190),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D131D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF273244)),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(_log,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFB9C3D3))),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Use only for content you own or are authorized to download. R4M does not bypass DRM, paywalls, login restrictions, or site access controls.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF707B8D), fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(color: purple, borderRadius: BorderRadius.circular(14)),
          child: const Text('R4M', style: TextStyle(color: Color(0xFF100D1C), fontSize: 18, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 13),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('R4M Downloader', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Your personal media manager', style: TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF142B25),
            border: Border.all(color: const Color(0xFF245540)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(_busy ? 'WORKING' : 'READY',
              style: const TextStyle(color: Color(0xFF67E2AD), fontSize: 10, fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }

  Widget _settings(bool wide) {
    final quality = DropdownButtonFormField<String>(
      value: _quality,
      decoration: const InputDecoration(labelText: 'Video quality'),
      items: ['720p', '1080p', '1440p', '2160p', 'Best available']
          .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
      onChanged: _busy ? null : (v) => setState(() => _quality = v ?? _quality),
    );
    final format = DropdownButtonFormField<String>(
      value: _format,
      decoration: const InputDecoration(labelText: 'Output format'),
      items: ['MP4', 'MKV', 'MP3']
          .map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
      onChanged: _busy ? null : (v) => setState(() => _format = v ?? _format),
    );
    return Column(
      children: [
        if (wide)
          Row(children: [Expanded(child: quality), const SizedBox(width: 12), Expanded(child: format)])
        else ...[
          quality,
          const SizedBox(height: 12),
          format,
        ],
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _playlist,
          onChanged: _busy ? null : (v) => setState(() => _playlist = v ?? false),
          title: const Text('Download entire playlist (desktop engine only)', style: TextStyle(fontSize: 13)),
          controlAffinity: ListTileControlAffinity.leading,
          activeColor: purple,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _desktop
                ? 'Desktop mode: uses yt-dlp installed on this computer.'
                : 'Mobile mode: downloads direct media-file URLs only. Webpage extraction is not available in this build.',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _panel({required String title, required Widget child, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: panel,
        border: Border.all(color: const Color(0xFF242D3B)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: const TextStyle(color: Color(0xFFAAB3C3), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const Spacer(),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }
}
