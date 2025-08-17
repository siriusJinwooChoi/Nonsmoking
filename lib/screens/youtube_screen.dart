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

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';

// ✅ 영상 아이템 모델 클래스
class YoutubeVideo {
  final String videoId;
  final String title;
  final String channelTitle;
  final String thumbnail;

  YoutubeVideo({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.thumbnail,
  });

  factory YoutubeVideo.fromJson(Map<String, dynamic> json) {
    return YoutubeVideo(
      videoId: json['videoId'],
      title: json['title'],
      channelTitle: json['channelTitle'],
      thumbnail: json['thumbnail'],
    );
  }
}

// ✅ 서버에서 영상 리스트 가져오기
Future<List<YoutubeVideo>> fetchYoutubeVideos() async {
  const String serverUrl = 'http://localhost:3000/api/youtube/curated'; // <-- 여기를 본인의 서버 IP로 수정하세요
  final response = await http.get(Uri.parse(serverUrl));

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    final List items = data['items'];
    return items.map((item) => YoutubeVideo.fromJson(item)).toList();
  } else {
    throw Exception('서버에서 영상 목록을 불러오지 못했습니다.');
  }
}

// ✅ 유튜브 영상 화면
class YoutubeScreen extends StatefulWidget {
  const YoutubeScreen({super.key});

  @override
  State<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends State<YoutubeScreen> {
  late Future<List<YoutubeVideo>> futureVideos;

  @override
  void initState() {
    super.initState();
    futureVideos = fetchYoutubeVideos();
  }

  // 유튜브 링크 열기
  Future<void> _launchYoutube(String videoId) async {
    final url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
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
        title: const Text('추천 유튜브 영상'),
        backgroundColor: Colors.redAccent,
      ),
      body: FutureBuilder<List<YoutubeVideo>>(
        future: futureVideos,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('에러 발생: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('영상이 없습니다.'));
          }

          final videos = snapshot.data!;
          return ListView.builder(
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final video = videos[index];
              return ListTile(
                leading: Image.network(video.thumbnail, width: 100, fit: BoxFit.cover),
                title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(video.channelTitle),
                onTap: () => _launchYoutube(video.videoId),
              );
            },
          );
        },
      ),
    );
  }
}