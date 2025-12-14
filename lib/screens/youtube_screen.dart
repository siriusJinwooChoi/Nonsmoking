/*
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class YoutubeScreen extends StatelessWidget {
  const YoutubeScreen({super.key});

  Future<void> _launchYoutubeSearch(String query) async {
    final url = Uri.parse('https://www.youtube.com/results?search_query=$query');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('금연 유튜브 영상'),
        backgroundColor: Colors.red,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '실시간 금연 관련 영상을 확인해보세요!',
              style: TextStyle(fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _launchYoutubeSearch("금연"),
              icon: const Icon(Icons.play_circle_fill),
              label: const Text('금연 영상 검색하기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            )
          ],
        ),
      ),
    );
  }
}
 */
/* //서버 기반 코드(aws)
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher_string.dart';

class YoutubeScreen extends StatefulWidget {
  const YoutubeScreen({super.key});

  @override
  State<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends State<YoutubeScreen> {
  List<dynamic> videos = [];
  bool isLoading = true;
  String errorMessage = '';

  // ✅ EC2 서버 주소 (본인의 퍼블릭 IP나 도메인으로 교체)
  final String serverUrl = 'http://13.124.52.76:3000/api/youtube/curated';

  @override
  void initState() {
    super.initState();
    fetchVideos();
  }

  Future<void> fetchVideos() async {
    try {
      final response = await http.get(Uri.parse(serverUrl));
      if (response.statusCode == 200) {
        setState(() {
          videos = json.decode(response.body);
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = '서버 오류: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = '에러 발생: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);

    // YouTube 앱으로 먼저 시도
    if (await canLaunchUrl(uri)) {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        // 실패 시 브라우저로 fallback
        await launchUrl(uri, mode: LaunchMode.inAppWebView);
      }
    } else {
      // 최종 실패 시
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('유튜브를 열 수 없습니다: $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('추천 유튜브 영상'),
        backgroundColor: Colors.redAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : errorMessage.isNotEmpty
            ? Center(child: Text(errorMessage))
            : ListView.separated(
          itemCount: videos.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            final video = videos[index];
            return ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(video['title']),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _launchUrl(video['url']),
            );
          },
        ),
      ),
    );
  }
}*/
/*
//********** 최종 Youtube screen 코드 **********
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

class YoutubeScreen extends StatefulWidget {
  const YoutubeScreen({super.key});

  @override
  State<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends State<YoutubeScreen> {
  List<dynamic> videos = [];
  bool isLoading = true;
  String errorMessage = '';

  final String apiKey = 'YOUR_API_KEY'; // 🔐 여기에 발급한 API 키 입력
  final String keyword = '금연';

  @override
  void initState() {
    super.initState();
    fetchVideos();
  }

  Future<void> fetchVideos() async {
    final apiUrl =
        'https://www.googleapis.com/youtube/v3/search?part=snippet&q=$keyword&type=video&order=date&maxResults=10&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        setState(() {
          videos = jsonData['items'];
          isLoading = false;
        });
      } else {
        setState(() {
          errorMessage = 'API 오류: ${response.statusCode}';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = '예외 발생: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _launchYoutube(String videoId) async {
    final url = 'https://www.youtube.com/watch?v=$videoId';
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('유튜브 실행 실패: $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('실시간 금연 유튜브 추천'),
        backgroundColor: Colors.redAccent,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(child: Text(errorMessage))
          : ListView.builder(
        itemCount: videos.length,
        itemBuilder: (context, index) {
          final video = videos[index];
          final snippet = video['snippet'];
          final videoId = video['id']['videoId'];
          return ListTile(
            leading: Image.network(snippet['thumbnails']['default']['url']),
            title: Text(snippet['title']),
            subtitle: Text(snippet['channelTitle']),
            trailing: const Icon(Icons.play_circle_outline),
            onTap: () => _launchYoutube(videoId),
          );
        },
      ),
    );
  }
}
*/