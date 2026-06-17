import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:fl_chart/fl_chart.dart';
import 'api/apiService.dart';

// 계측 모드 열거형 정의
enum MeasurementMode { bbox, point }

void main() async {
  // 메인 함수에서는 바인딩만 보장하고 정적인 대시보드를 즉시 띄웁니다.
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 유저 정보에서 확인된 진짜 PC 버전 Supabase 주소로 완벽 고정!
  const String supabaseUrl = 'https://lbbbgwizrpvtecbxavpr.supabase.co';

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      // 2. 방금 lbbbgwiz... 웹 대시보드 API 메뉴에서 복사해 온 진짜 Anon Key를 여기에 붙여넣으세요!
      publishableKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxiYmJnd2l6cnB2dGVjYnhhdnByIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc5ODcxNjksImV4cCI6MjA5MzU2MzE2OX0.GUN_rB-Tns4x-Io48nEbRJZk4rZxLHhkcmKYOwruYZI',
    );
  } catch (e) {
    debugPrint('Supabase initialization failed: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Premium Measurement System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.tealAccent,
        scaffoldBackgroundColor: const Color(0xFF0F0F12),
        useMaterial3: true,
      ),
      home: const MainDashboard(), // 첫 진입 화면을 대시보드로 변경
    );
  }
}

// 1. 새로운 정적 메인 대시보드 화면
class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  bool _isLoading = true;
  bool _isOnline = false;
  List<Map<String, dynamic>> _logs = [];
  String? _loggedInUserId;
  String? _userRole;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }

  void _subscribeToRealtime() {
    _unsubscribeFromRealtime();

    if (_loggedInUserId == null) return;

    try {
      final supabase = Supabase.instance.client;
      _realtimeChannel = supabase
          .channel('public:tb_measurement')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'fishlen',
            table: 'tb_measurement',
            callback: (payload) {
              final newRecord = payload.newRecord;
              final String? recordUser = newRecord['username'] as String?;
              
              if (recordUser == _loggedInUserId) {
                _fetchLogs();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '[🔔 실시간 계측 알림] 신규 물체(${newRecord['name']})가 계측 완료되었습니다! 치수: ${newRecord['measurement_value']}mm',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: Colors.tealAccent,
                      duration: const Duration(seconds: 4),
                    ),
                  );
                }
              }
            },
          );
      _realtimeChannel!.subscribe();
    } catch (e) {
      debugPrint('Realtime subscription error: $e');
    }
  }

  void _unsubscribeFromRealtime() {
    if (_realtimeChannel != null) {
      try {
        _realtimeChannel!.unsubscribe();
        Supabase.instance.client.removeChannel(_realtimeChannel!);
      } catch (_) {}
      _realtimeChannel = null;
    }
  }

  Future<void> _fetchLogs() async {
    if (_loggedInUserId == null) {
      setState(() {
        _logs = [];
        _isLoading = false;
        _isOnline = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      // 'tb_measurement' 테이블에서 현재 로그인한 사용자의 데이터를 가져옴
      final response = await supabase
          .from('tb_measurement')
          .select()
          .eq('username', _loggedInUserId!)
          .order('reg_dt', ascending: false);

      final List<dynamic> data = response;

      setState(() {
        _logs = data.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
        _isLoading = false;
        _isOnline = true;
      });
    } catch (e) {
      debugPrint('Supabase fetch error, fallback active: $e');
      setState(() {
        _isLoading = false;
        _isOnline = false;
        // Fallback 데이터 설정 (tb_measurement 스키마 필드 정렬)
        _logs = [
          {
            'id': 2026061,
            'name': 'Industrial Container (Fallback)',
            'measurement_value': 450.0,
            'sub_class_name': 'container',
            'is_trained': 'Y',
            'confidence': 0.94,
            'reg_dt': '2026-06-15 10:09:22',
            'username': _loggedInUserId
          },
          {
            'id': 2026062,
            'name': 'Structure BBOX (Fallback)',
            'measurement_value': 1200.0,
            'sub_class_name': 'structure',
            'is_trained': 'Y',
            'confidence': 0.89,
            'reg_dt': '2026-06-15 09:42:15',
            'username': _loggedInUserId
          },
          {
            'id': 2026063,
            'name': 'Point Angle Session (Fallback)',
            'measurement_value': 185.0,
            'sub_class_name': null,
            'is_trained': 'C',
            'confidence': 0.91,
            'reg_dt': '2026-06-15 08:15:30',
            'username': _loggedInUserId
          }
        ];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. 오늘 자정 시각 DateTime 생성
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);

    // 2. 오늘 날짜 데이터만 필터링 (reg_dt >= todayMidnight)
    final todayLogs = _logs.where((log) {
      final regDtStr = log['reg_dt'] as String?;
      if (regDtStr == null) return false;
      try {
        final regDt = DateTime.parse(regDtStr);
        return regDt.isAfter(todayMidnight) || regDt.isAtSameMomentAs(todayMidnight);
      } catch (_) {
        return false;
      }
    }).toList();

    // 2.5 최근 7일 날짜 리스트 및 통계 계산
    final List<DateTime> last7Days = List.generate(7, (index) {
      return DateTime(now.year, now.month, now.day).subtract(Duration(days: 6 - index));
    });

    final List<double> counts = List.filled(7, 0.0);
    for (int i = 0; i < 7; i++) {
      final targetDate = last7Days[i];
      final nextDate = targetDate.add(const Duration(days: 1));
      
      final count = _logs.where((log) {
        final regDtStr = log['reg_dt'] as String?;
        if (regDtStr == null) return false;
        try {
          final regDt = DateTime.parse(regDtStr);
          return (regDt.isAfter(targetDate) || regDt.isAtSameMomentAs(targetDate)) && regDt.isBefore(nextDate);
        } catch (_) {
          return false;
        }
      }).length;
      
      counts[i] = count.toDouble();
    }

    final spots = List.generate(7, (index) {
      return FlSpot(index.toDouble(), counts[index]);
    });

    String getXAxisLabel(double value) {
      final idx = value.toInt();
      if (idx >= 0 && idx < 7) {
        final date = last7Days[idx];
        return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      }
      return '';
    }

    // 3. 통계 수치 동적 계산
    final int todayCount = todayLogs.length;
    final int successCount = _logs.where((log) => log['is_trained'] != null).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161E),
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            // [왼쪽 영역]: 아이콘과 타이틀 세트
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.analytics_outlined,
                color: Colors.tealAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'JMS MEASURE LINK',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'SYSTEM CONTROL PANEL',
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.white38,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            // [가운데]: 공간 분리를 위한 Spacer
            const Spacer(),
            // [오른쪽 영역]: 로그인, 회원가입, ONLINE 뱃지
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_loggedInUserId == null) ...[
                  TextButton(
                    onPressed: _showLoginDialog,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '로그인',
                      style: TextStyle(
                        color: Colors.tealAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _showRegisterDialog,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '회원가입',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ] else ...[
                  Text(
                    _userRole == 'ADMIN' ? '🔒 Admin 모드' : '👤 $_loggedInUserId님',
                    style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () {
                      _unsubscribeFromRealtime();
                      setState(() {
                        _loggedInUserId = null;
                        _userRole = null;
                      });
                      _fetchLogs();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('[SUCCESS] 로그아웃 완료'),
                          backgroundColor: Colors.teal,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '로그아웃',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E24),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.wifi, 
                        color: _isOnline ? Colors.tealAccent : Colors.grey, 
                        size: 11
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isOnline ? 'ONLINE' : 'OFFLINE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: _isOnline ? Colors.tealAccent : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF16161E), Color(0xFF0F0F12)],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchLogs,
                color: Colors.tealAccent,
                backgroundColor: const Color(0xFF1E1E24),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section Title: Real-time Statistics
                      const Row(
                        children: [
                          Icon(Icons.bar_chart_rounded, color: Colors.tealAccent, size: 18),
                          SizedBox(width: 6),
                          Text(
                            '실시간 계측 통계',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 1. 상단/중앙 실시간 계측 요약 통계 위젯
                      Row(
                        children: [
                          _buildStatCard(
                            label: '오늘 총 계측',
                            value: '$todayCount 건',
                            icon: Icons.history_toggle_off_rounded,
                            color: Colors.tealAccent,
                          ),
                          const SizedBox(width: 10),
                          _buildStatCard(
                            label: '정상 연산 완료',
                            value: '$successCount 건',
                            icon: Icons.check_circle_outline_rounded,
                            color: Colors.tealAccent,
                          ),
                          const SizedBox(width: 10),
                          _buildStatCard(
                            label: '서버 통신',
                            value: _isOnline ? '정상' : '단절',
                            icon: _isOnline ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                            color: _isOnline ? Colors.tealAccent : Colors.grey,
                            isStatus: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 1.5 최근 7일 계측 추이 차트 섹션
                      _loggedInUserId == null
                          ? const SizedBox.shrink()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.show_chart_rounded, color: Colors.tealAccent, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      '최근 7일 계측 추이',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  height: 200,
                                  padding: const EdgeInsets.only(right: 20, left: 10, top: 15, bottom: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF16161E),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: _buildLineChart(last7Days, spots, getXAxisLabel),
                                ),
                              ],
                            ),

                      const SizedBox(height: 32),

                      // Section Title: Recent History
                      Row(
                        children: [
                          const Icon(Icons.list_alt_rounded, color: Colors.tealAccent, size: 18),
                          const SizedBox(width: 6),
                          const Text(
                            '최근 계측 및 연산 이력',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.refresh_rounded, color: Colors.tealAccent, size: 18),
                            onPressed: _fetchLogs,
                            tooltip: '실시간 DB 갱신',
                          ),
                          const Spacer(),
                          Text(
                            '총 ${_logs.length}개 로그',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.tealAccent.withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 2. 최근 계측 이력 및 연산 결과 리스트
                      _loggedInUserId == null
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 40.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.lock_outline_rounded, color: Colors.white24, size: 32),
                                    SizedBox(height: 12),
                                    Text(
                                      '로그인 후 실시간 콘솔 데이터를 확인하세요.',
                                      style: TextStyle(color: Colors.white38, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _isLoading
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 40.0),
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                                    ),
                                  ),
                                )
                              : _logs.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(vertical: 40.0),
                                        child: Text(
                                          '계측 이력이 존재하지 않습니다.',
                                          style: TextStyle(color: Colors.white38),
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _logs.length > 10 ? 10 : _logs.length,
                                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final log = _logs[index];
                                    
                                    // tb_measurement DB 컬럼 구조에 맞게 매핑
                                    final String id = log['id']?.toString() ?? '#Unknown';
                                    final String title = log['name'] ?? 'Unknown Object';
                                    
                                    final String isTrained = log['is_trained']?.toString() ?? 'N';
                                    final String status = isTrained == 'Y' ? '학습 완료' : (isTrained == 'C' ? '보정 완료' : '미계측');
                                    
                                    final String tag = log['sub_class_name'] != null ? 'BBOX' : 'POINT';
                                    final Color tagColor = tag == 'POINT' ? Colors.amber : Colors.tealAccent;
                                    
                                    final double confVal = (log['confidence'] as num?)?.toDouble() ?? 0.0;
                                    final String calculationTime = confVal > 0 ? '${(0.5 - confVal * 0.2).toStringAsFixed(2)}s' : '0.35s';
                                    
                                    final String regDt = log['reg_dt']?.toString() ?? 'N/A';
                                    final String logMessage = "[INFO] $regDt - Database Sync Log.\n"
                                        "[DBMS] Fetch from tb_measurement.\n"
                                        "[DATA] ID: $id\n"
                                        "[MODEL] Class: $title (${log['sub_class_name'] ?? 'N/A'})\n"
                                        "[CONFIDENCE] ${confVal > 0 ? (confVal * 100).toStringAsFixed(1) + '%' : 'N/A'}\n"
                                        "[MEASUREMENT] Value: ${log['measurement_value'] ?? '0.0'}mm";

                                    String specs = '';
                                    if (log['measurement_value'] != null) {
                                      specs = 'Value: ${log['measurement_value']}mm';
                                    } else {
                                      specs = 'No dimension specs';
                                    }

                                    return _buildHistoryCard(
                                      context: context,
                                      id: id,
                                      title: title,
                                      specs: specs,
                                      status: status,
                                      tag: tag,
                                      tagColor: tagColor,
                                      calculationTime: calculationTime,
                                      logMessage: logMessage,
                                    );
                                  },
                                ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
            
            // 3. 하단 메인 제어 액션 고정 배치
            Container(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 24.0),
              decoration: BoxDecoration(
                color: const Color(0xFF16161E),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
                border: const Border(
                  top: BorderSide(color: Colors.white10, width: 1),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      // 새로운 실시간 카메라 계측 화면 진입
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MeasurementCameraPage(
                            loggedInUserId: _loggedInUserId,
                          ),
                        ),
                      );
                      _fetchLogs();
                    },
                    icon: const Icon(Icons.videocam_rounded, size: 22),
                    label: const Text(
                      '실시간 계측 시작',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.black,
                      backgroundColor: Colors.tealAccent,
                      elevation: 4,
                      shadowColor: Colors.tealAccent.withOpacity(0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 통계 카드 빌더
  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool isStatus = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color.withOpacity(0.8), size: 18),
                if (isStatus)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.6),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 역사 카드 빌더 (PC/모바일 웹 테이블 이식) - 클릭 감지 및 다이얼로그 호출 연동
  Widget _buildHistoryCard({
    required BuildContext context,
    required String id,
    required String title,
    required String specs,
    required String status,
    required String tag,
    required Color tagColor,
    required String calculationTime,
    required String logMessage,
  }) {
    return GestureDetector(
      onTap: () => _showHistoryDetailsDialog(
        context,
        id: id,
        title: title,
        specs: specs,
        tag: tag,
        calculationTime: calculationTime,
        logMessage: logMessage,
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ID: $id',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white54,
                    fontFamily: 'monospace',
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tagColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tagColor.withOpacity(0.3), width: 1),
                  ),
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: tagColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  specs,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white38,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.tealAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      status,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.tealAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 세련된 다크 테마 개발자 콘솔형 상세 정보 팝업창
  void _showHistoryDetailsDialog(
    BuildContext context, {
    required String id,
    required String title,
    required String specs,
    required String tag,
    required String calculationTime,
    required String logMessage,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.tealAccent.withOpacity(0.3), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.terminal_rounded, color: Colors.tealAccent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'DASHBOARD LOG SYSTEM',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Colors.tealAccent.withOpacity(0.8),
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 24, thickness: 1),
                
                // Console Info Section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildConsoleRow('LOG_ID', id, color: Colors.amberAccent),
                      const SizedBox(height: 6),
                      _buildConsoleRow('TARGET', title, color: Colors.white),
                      const SizedBox(height: 6),
                      _buildConsoleRow('SPECS', specs, color: Colors.tealAccent),
                      const SizedBox(height: 6),
                      _buildConsoleRow('LATENCY', calculationTime, color: Colors.cyanAccent),
                      const SizedBox(height: 6),
                      _buildConsoleRow('MODE_TAG', tag, color: tag == 'BBOX' ? Colors.tealAccent : Colors.amber),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Server Log Title
                const Text(
                  'SERVER RESPONSES & STDOUT',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white38,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 6),
                
                // Server Log Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0F12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    logMessage,
                    style: const TextStyle(
                      color: Colors.tealAccent,
                      fontSize: 11,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Confirm Button
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLoginDialog() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.tealAccent.withOpacity(0.3), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.login_rounded, color: Colors.tealAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'SECURE LOGIN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.tealAccent.withOpacity(0.8),
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 24, thickness: 1),
                const Text(
                  '기존 PC 버전(tb_measurement_user) 계정으로 인증을 진행합니다.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'ID (Username)',
                    labelStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () async {
                      final username = usernameController.text.trim();
                      final password = passwordController.text;

                      if (username.isEmpty || password.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('[ERROR] ID와 비밀번호를 모두 입력해주세요.'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);

                      try {
                        final supabase = Supabase.instance.client;
                        final userRow = await supabase
                            .from('tb_measurement_user')
                            .select()
                            .eq('username', username)
                            .maybeSingle();

                        if (userRow == null) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('[ERROR] 인증 실패: 존재하지 않는 계정입니다.'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        final hashedPassword = userRow['password'] as String?;
                        if (hashedPassword == null || !BCrypt.checkpw(password, hashedPassword)) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('[ERROR] 인증 실패: 비밀번호가 일치하지 않습니다.'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        // 로그인 성공
                        final role = userRow['role'] as String?;
                        navigator.pop(); // 다이얼로그 닫기
                        
                        setState(() {
                          _loggedInUserId = username;
                          _userRole = role;
                        });

                        _fetchLogs();
                        _subscribeToRealtime();

                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('[SUCCESS] JMS 시스템 인증 성공'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('[ERROR] 인증 실패: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '로그인',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRegisterDialog() {
    final usernameController = TextEditingController();
    final nameController = TextEditingController();
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.tealAccent.withOpacity(0.3), width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_add_rounded, color: Colors.tealAccent, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'CREATE ACCOUNT',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.tealAccent.withOpacity(0.8),
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white10, height: 24, thickness: 1),
                const Text(
                  'BCrypt 해싱 암호화 메커니즘을 공유하는 신규 계정을 생성합니다.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: usernameController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'ID (Username)',
                    labelStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Name (Real Name)',
                    labelStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () async {
                      final username = usernameController.text.trim();
                      final name = nameController.text.trim();
                      final password = passwordController.text;

                      if (username.isEmpty || name.isEmpty || password.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('[ERROR] 모든 정보를 올바르게 입력해주세요.'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);

                      try {
                        final supabase = Supabase.instance.client;
                        
                        final existingUser = await supabase
                            .from('tb_measurement_user')
                            .select()
                            .eq('username', username)
                            .maybeSingle();

                        if (existingUser != null) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('[ERROR] 가입 실패: 이미 존재하는 ID입니다.'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                          return;
                        }

                        final hashedPassword = BCrypt.hashpw(password, BCrypt.gensalt());

                        await supabase.from('tb_measurement_user').insert({
                          'username': username,
                          'password': hashedPassword,
                          'name': name,
                          'role': 'USER',
                        });

                        navigator.pop();

                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('[SUCCESS] 신규 관리자 계정 생성 완료'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('[ERROR] 계정 생성 실패: $e'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '가입 완료',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLineChart(
    List<DateTime> last7Days,
    List<FlSpot> spots,
    String Function(double) getXAxisLabel,
  ) {
    double maxY = 5;
    for (final spot in spots) {
      if (spot.y > maxY) {
        maxY = spot.y;
      }
    }
    maxY = (maxY + 1).ceilToDouble();

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) {
            return const FlLine(
              color: Colors.white10,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY > 10 ? (maxY / 5).ceilToDouble() : 1,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(
                    color: Colors.white30,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.left,
                );
              },
              reservedSize: 28,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (value, meta) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    getXAxisLabel(value),
                    style: const TextStyle(
                      color: Colors.white30,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: false,
        ),
        minX: 0,
        maxX: 6,
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            gradient: const LinearGradient(
              colors: [
                Colors.tealAccent,
                Colors.teal,
              ],
            ),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(
              show: true,
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.tealAccent.withOpacity(0.2),
                  Colors.tealAccent.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsoleRow(String label, String value, {required Color color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: const TextStyle(
              color: Colors.white30,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}


// 2. 계측 및 카메라 화면 (실제 진입 시에만 카메라 모듈이 초기화됨)
class MeasurementScreen extends StatefulWidget {
  const MeasurementScreen({super.key});

  @override
  State<MeasurementScreen> createState() => _MeasurementScreenState();
}

class _MeasurementScreenState extends State<MeasurementScreen> {
  List<CameraDescription> _availableCameras = [];
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  int _selectedCameraIndex = 0;
  XFile? _capturedImage;
  bool _isCapturing = false;
  bool _isCameraLoading = true; // 카메라 초기화 대기 상태

  // 계측 모드 (기본값: BBOX 모드)
  MeasurementMode _currentMode = MeasurementMode.bbox;

  // Mock 데이터 상태 관리
  Rect? _mockBbox;
  String? _mockBboxLabel;
  List<Offset> _mockPoints = [];
  double? _mockDistance1;
  double? _mockDistance2;
  double? _mockAngle;

  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    // 화면에 진입한 시점에만 카메라 리스트를 조회하고 초기화합니다.
    _initCamerasAndController();
  }

  // 카메라 목록 조회 및 첫 렌즈로 초기화 진행
  Future<void> _initCamerasAndController() async {
    try {
      _availableCameras = await availableCameras();
      if (_availableCameras.isNotEmpty) {
        await _initializeCamera(_availableCameras[_selectedCameraIndex]);
      }
    } catch (e) {
      debugPrint('카메라 탐색 중 오류 발생: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCameraLoading = false;
        });
      }
    }
  }

  // 지정된 카메라로 컨트롤러를 초기화하는 함수
  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    if (_controller != null) {
      await _controller!.dispose();
    }

    _controller = CameraController(
      cameraDescription,
      ResolutionPreset.max,
      enableAudio: false,
    );

    try {
      setState(() {
        _initializeControllerFuture = _controller!.initialize();
      });
    } catch (e) {
      debugPrint('카메라 초기화 에러: $e');
    }
  }

  @override
  void dispose() {
    // 대시보드로 돌아갈 때 확실히 하드웨어 리소스 반환
    _controller?.dispose();
    super.dispose();
  }

  // 전면/후면 카메라 전환
  void _toggleCamera() {
    if (_availableCameras.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용 가능한 다른 카메라가 없습니다.')),
      );
      return;
    }
    setState(() {
      _selectedCameraIndex = (_selectedCameraIndex + 1) % _availableCameras.length;
      _clearMockData();
    });
    _initializeCamera(_availableCameras[_selectedCameraIndex]);
  }

  // 측정 Mock 데이터 초기화
  void _clearMockData() {
    setState(() {
      _mockBbox = null;
      _mockBboxLabel = null;
      _mockPoints.clear();
      _mockDistance1 = null;
      _mockDistance2 = null;
      _mockAngle = null;
    });
  }

  // 사진 촬영 및 계측 데이터 연동 로직
  Future<void> _takePictureAndMeasure(Size constraintSize) async {
    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
      _clearMockData();
    });

    // 1. 에뮬레이터 환경 대응용 Fallback 스케줄링
    if (_availableCameras.isEmpty) {
      await Future.delayed(const Duration(milliseconds: 800));
      _generateMockData(constraintSize);
      setState(() {
        _isCapturing = false;
      });
      return;
    }

    // 2. 물리 기기가 있는 경우의 실계측 및 API 연동 로직 실행
    try {
      await _initializeControllerFuture;
      final XFile image = await _controller!.takePicture();
      
      setState(() {
        _capturedImage = image;
      });

      const double dummyFocalLength = 50.0;
      const double dummyDistance = 120.5;

      final response = await _apiService.uploadImage(
        imageFile: File(image.path),
        focalLength: dummyFocalLength,
        distance: dummyDistance,
      );

      debugPrint('서버 응답 결과: $response');

      if (response != null && response['status'] == 200) {
        try {
          _parseServerResponse(response, constraintSize);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('서버 분석 완료! 실제 계측 데이터 오버레이가 활성화됩니다.'),
                backgroundColor: Colors.teal.shade700,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } catch (parseError) {
          debugPrint('응답 파싱 실패 (Fallback 실행): $parseError');
          _generateMockData(constraintSize);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('서버 분석 데이터 파싱 오류: $parseError (Mock 데이터 적용)'),
                backgroundColor: Colors.deepOrange.shade800,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        debugPrint('서버 응답 무효 (Fallback 실행)');
        _generateMockData(constraintSize);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('서버 응답 실패 (Mock 모드로 계측 시각화 적용)'),
              backgroundColor: Colors.deepOrange.shade800,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('촬영 및 전송 에러: $e');
      _generateMockData(constraintSize);
    } finally {
      setState(() {
        _isCapturing = false;
      });
    }
  }

  // 서버로부터 받아온 실제 응답 데이터를 파싱하여 화면 오버레이 상태 업데이트
  void _parseServerResponse(Map<String, dynamic> response, Size previewSize) {
    final double width = previewSize.width;
    final double height = previewSize.height;
    
    final List<dynamic>? data = response['data'];
    if (data == null || data.isEmpty) {
      throw Exception('서버 감지 데이터가 비어있습니다.');
    }

    final item = data.first;
    final String measurementType = item['measurement_type'] ?? 'BBOX';
    final boxData = item['box'];
    
    if (boxData == null) {
      throw Exception('BBOX 데이터가 응답에 포함되어 있지 않습니다.');
    }

    final double x1 = (boxData['x1'] as num).toDouble();
    final double y1 = (boxData['y1'] as num).toDouble();
    final double x2 = (boxData['x2'] as num).toDouble();
    final double y2 = (boxData['y2'] as num).toDouble();

    setState(() {
      if (measurementType == 'BBOX') {
        _mockBbox = Rect.fromLTRB(x1 * width, y1 * height, x2 * width, y2 * height);
        
        final double pixelWidth = (x2 - x1) * width;
        final double pixelHeight = (y2 - y1) * height;
        
        // Pinhole camera 공식 기반의 물리 크기 (mm) 역산 
        // distance: 120.5cm -> 1205mm, focalLength: 50mm
        final double calculatedW = ((pixelWidth * 1205) / (50.0 * 10)).roundToDouble();
        final double calculatedH = ((pixelHeight * 1205) / (50.0 * 10)).roundToDouble();
        final double calculatedD = (calculatedW * 0.65).roundToDouble();

        final String className = item['class_name'] ?? 'Object';
        final String? subClassName = item['sub_class_name'];
        final String labelName = subClassName != null ? '$className ($subClassName)' : className;

        _mockBboxLabel = "Object: $labelName\nW: ${calculatedW.toInt()}mm  H: ${calculatedH.toInt()}mm  D: ${calculatedD.toInt()}mm";
        _mockPoints.clear();
      } else {
        // THREE_POINT 모드인 경우
        _mockBbox = null;
        _mockBboxLabel = null;
        
        final List<dynamic>? segments = item['segments'];
        if (segments != null && segments.isNotEmpty) {
          if (segments.length >= 3) {
            // 대표 포인트 3개 추출 (처음, 중간, 끝)
            final int step = (segments.length / 3).floor();
            final pt1 = segments[0];
            final pt2 = segments[step];
            final pt3 = segments[segments.length - 1];
            _mockPoints = [
              Offset((pt1[0] as num).toDouble() * width, (pt1[1] as num).toDouble() * height),
              Offset((pt2[0] as num).toDouble() * width, (pt2[1] as num).toDouble() * height),
              Offset((pt3[0] as num).toDouble() * width, (pt3[1] as num).toDouble() * height),
            ];
          } else {
            _mockPoints = segments.map<Offset>((pt) {
              return Offset((pt[0] as num).toDouble() * width, (pt[1] as num).toDouble() * height);
            }).toList();
          }
        } else {
          // segments가 없으면 BBOX 기반으로 landmark 3점 생성
          _mockPoints = [
            Offset(width * (x1 + (x2 - x1) * 0.25), height * (y1 + (y2 - y1) * 0.35)),
            Offset(width * (x1 + (x2 - x1) * 0.50), height * (y1 + (y2 - y1) * 0.65)),
            Offset(width * (x1 + (x2 - x1) * 0.75), height * (y1 + (y2 - y1) * 0.40)),
          ];
        }

        // 거리 및 각도 계산
        if (_mockPoints.length >= 2) {
          final double d1Px = (_mockPoints[0] - _mockPoints[1]).distance;
          _mockDistance1 = ((d1Px * 1205) / (50.0 * 10)).roundToDouble();
        }
        if (_mockPoints.length >= 3) {
          final double d2Px = (_mockPoints[1] - _mockPoints[2]).distance;
          _mockDistance2 = ((d2Px * 1205) / (50.0 * 10)).roundToDouble();

          final v1 = Offset(_mockPoints[0].dx - _mockPoints[1].dx, _mockPoints[0].dy - _mockPoints[1].dy);
          final v2 = Offset(_mockPoints[2].dx - _mockPoints[1].dx, _mockPoints[2].dy - _mockPoints[1].dy);
          final double dotProduct = v1.dx * v2.dx + v1.dy * v2.dy;
          final double mag1 = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy);
          final double mag2 = math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy);
          if (mag1 * mag2 > 0) {
            final double angleRad = math.acos(dotProduct / (mag1 * mag2));
            _mockAngle = angleRad * (180 / math.pi);
          }
        }
      }
    });
  }


  // 모드별 가상 데이터 매핑 함수
  void _generateMockData(Size previewSize) {
    final double width = previewSize.width;
    final double height = previewSize.height;

    setState(() {
      if (_currentMode == MeasurementMode.bbox) {
        _mockBbox = Rect.fromLTWH(
          width * 0.15,
          height * 0.25,
          width * 0.7,
          height * 0.45,
        );
        _mockBboxLabel = "Object: Industrial Container\nW: 450mm  H: 300mm  D: 250mm";
      } else {
        _mockPoints = [
          Offset(width * 0.25, height * 0.35),
          Offset(width * 0.50, height * 0.65),
          Offset(width * 0.75, height * 0.40),
        ];
        
        _mockDistance1 = 185.0;
        _mockDistance2 = 210.0;
        
        final v1 = Offset(_mockPoints[0].dx - _mockPoints[1].dx, _mockPoints[0].dy - _mockPoints[1].dy);
        final v2 = Offset(_mockPoints[2].dx - _mockPoints[1].dx, _mockPoints[2].dy - _mockPoints[1].dy);
        final dotProduct = v1.dx * v2.dx + v1.dy * v2.dy;
        final mag1 = math.sqrt(v1.dx * v1.dx + v1.dy * v1.dy);
        final mag2 = math.sqrt(v2.dx * v2.dx + v2.dy * v2.dy);
        final angleRad = math.acos(dotProduct / (mag1 * mag2));
        _mockAngle = angleRad * (180 / math.pi);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F12),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(), // 대시보드로 복귀
        ),
        title: const Text(
          'MEASURE PANEL',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            color: Colors.tealAccent,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _clearMockData,
            tooltip: '계측 리셋',
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. 상단 모드 선택 토글
            _buildModeToggle(),

            // 2. 카메라 미리보기 + 계측 오버레이 영역
            Expanded(
              child: _isCameraLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F0F0F),
                            borderRadius: BorderRadius.circular(24.0),
                            border: Border.all(color: Colors.white10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.6),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildPreviewOrSimulator(),

                              if (_mockBbox != null || _mockPoints.isNotEmpty)
                                CustomPaint(
                                  size: previewSize,
                                  painter: MeasurementOverlayPainter(
                                    mode: _currentMode,
                                    bbox: _mockBbox,
                                    bboxLabel: _mockBboxLabel,
                                    points: _mockPoints,
                                    distance1: _mockDistance1,
                                    distance2: _mockDistance2,
                                    angle: _mockAngle,
                                  ),
                                ),

                              if (_isCapturing)
                                Container(
                                  color: Colors.black45,
                                  child: const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          '서버 분석 및 계측 데이터 연산 중...',
                                          style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // 3. 하단 컨트롤바
            LayoutBuilder(
              builder: (context, constraints) {
                final screenWidth = MediaQuery.of(context).size.width - 32;
                final screenHeight = MediaQuery.of(context).size.height * 0.6;
                final approximatePreviewSize = Size(screenWidth, screenHeight);

                return _buildControlBar(approximatePreviewSize);
              },
            ),
          ],
        ),
      ),
    );
  }

  // 모드 선택 토글 UI
  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _currentMode = MeasurementMode.bbox;
                    _clearMockData();
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _currentMode == MeasurementMode.bbox
                        ? Colors.tealAccent.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'BBOX 모드 (객체 계측)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _currentMode == MeasurementMode.bbox ? Colors.tealAccent : Colors.white60,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _currentMode = MeasurementMode.point;
                    _clearMockData();
                  });
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: _currentMode == MeasurementMode.point
                        ? Colors.tealAccent.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '포인트 모드 (구간/각도)',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _currentMode == MeasurementMode.point ? Colors.tealAccent : Colors.white60,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 기기 프리뷰 혹은 시뮬레이션 배경 그리기
  Widget _buildPreviewOrSimulator() {
    if (_availableCameras.isEmpty) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1F2937), Color(0xFF111827)],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0.1,
              child: GridPaper(
                color: Colors.tealAccent,
                divisions: 2,
                subdivisions: 4,
                interval: 100,
                child: Container(),
              ),
            ),
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.developer_board, size: 48, color: Colors.tealAccent),
                SizedBox(height: 12),
                Text(
                  'VIRTUAL CAMERA SIMULATOR',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white38, letterSpacing: 1.0),
                ),
                SizedBox(height: 4),
                Text(
                  '(에뮬레이터 감지 - 셔터 클릭 시 계측 Mock 활성화)',
                  style: TextStyle(fontSize: 11, color: Colors.white30),
                )
              ],
            ),
          ],
        ),
      );
    }

    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return Center(
            child: CameraPreview(_controller!),
          );
        } else {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.tealAccent),
            ),
          );
        }
      },
    );
  }

  // 하단 셔터 및 컨트롤 바
  Widget _buildControlBar(Size previewSize) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 32.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          GestureDetector(
            onTap: () {
              if (_capturedImage != null) {
                _showImageDetailsDialog(File(_capturedImage!.path));
              }
            },
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.white30, width: 1),
                image: _capturedImage != null
                    ? DecorationImage(
                        image: FileImage(File(_capturedImage!.path)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _capturedImage == null
                  ? const Icon(Icons.photo_outlined, color: Colors.white30)
                  : null,
            ),
          ),

          GestureDetector(
            onTap: () => _takePictureAndMeasure(previewSize),
            child: Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              padding: const EdgeInsets.all(4.0),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF121212),
                  border: Border.all(
                    color: _isCapturing ? Colors.tealAccent : Colors.white,
                    width: 4.0,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.camera_alt,
                    size: 30.0,
                    color: _isCapturing ? Colors.tealAccent : Colors.white,
                  ),
                ),
              ),
            ),
          ),

          IconButton(
            onPressed: _toggleCamera,
            icon: const Icon(Icons.flip_camera_ios_outlined),
            iconSize: 28,
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  void _showImageDetailsDialog(File file) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: const Text('촬영 원본 스크린', style: TextStyle(color: Colors.white)),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.file(file),
            ),
          ),
        );
      },
    );
  }
}

// BBOX 및 포인트 모드 오버레이용 CustomPainter
class MeasurementOverlayPainter extends CustomPainter {
  final MeasurementMode mode;
  final Rect? bbox;
  final String? bboxLabel;
  final List<Offset> points;
  final double? distance1;
  final double? distance2;
  final double? angle;

  MeasurementOverlayPainter({
    required this.mode,
    this.bbox,
    this.bboxLabel,
    required this.points,
    this.distance1,
    this.distance2,
    this.angle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mode == MeasurementMode.bbox && bbox != null) {
      _paintBbox(canvas);
    } else if (mode == MeasurementMode.point && points.isNotEmpty) {
      _paintPointsAndLines(canvas);
    }
  }

  void _paintBbox(Canvas canvas) {
    final paintBbox = Paint()
      ..color = Colors.tealAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final paintBboxFill = Paint()
      ..color = Colors.tealAccent.withOpacity(0.08)
      ..style = PaintingStyle.fill;

    canvas.drawRect(bbox!, paintBboxFill);
    canvas.drawRect(bbox!, paintBbox);

    final paintCorner = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    
    const double length = 20.0;
    canvas.drawLine(bbox!.topLeft, bbox!.topLeft + const Offset(length, 0), paintCorner);
    canvas.drawLine(bbox!.topLeft, bbox!.topLeft + const Offset(0, length), paintCorner);
    canvas.drawLine(bbox!.topRight, bbox!.topRight + const Offset(-length, 0), paintCorner);
    canvas.drawLine(bbox!.topRight, bbox!.topRight + const Offset(0, length), paintCorner);
    canvas.drawLine(bbox!.bottomLeft, bbox!.bottomLeft + const Offset(length, 0), paintCorner);
    canvas.drawLine(bbox!.bottomLeft, bbox!.bottomLeft + const Offset(0, -length), paintCorner);
    canvas.drawLine(bbox!.bottomRight, bbox!.bottomRight + const Offset(-length, 0), paintCorner);
    canvas.drawLine(bbox!.bottomRight, bbox!.bottomRight + const Offset(0, -length), paintCorner);

    if (bboxLabel != null) {
      final textSpan = TextSpan(
        text: bboxLabel,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12.0,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withOpacity(0.85),
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );

      textPainter.layout(maxWidth: bbox!.width);
      textPainter.paint(canvas, bbox!.topLeft + const Offset(8, -48));
    }
  }

  void _paintPointsAndLines(Canvas canvas) {
    final paintLine = Paint()
      ..color = Colors.tealAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final paintDot = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final paintDotOuter = Paint()
      ..color = Colors.tealAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paintLine);
    }

    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(points[i], 8.0, paintDot);
      canvas.drawCircle(points[i], 12.0, paintDotOuter);

      final textSpan = TextSpan(
        text: 'P${i + 1}',
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black54,
        ),
      );
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();
      textPainter.paint(canvas, points[i] + const Offset(14, -14));
    }

    if (points.length >= 2 && distance1 != null) {
      final midPoint1 = Offset(
        (points[0].dx + points[1].dx) / 2,
        (points[0].dy + points[1].dy) / 2,
      );
      _drawLabel(canvas, midPoint1, '${distance1!.toStringAsFixed(1)}mm');
    }

    if (points.length >= 3 && distance2 != null) {
      final midPoint2 = Offset(
        (points[1].dx + points[2].dx) / 2,
        (points[1].dy + points[2].dy) / 2,
      );
      _drawLabel(canvas, midPoint2, '${distance2!.toStringAsFixed(1)}mm');
    }

    if (points.length >= 3 && angle != null) {
      final anglePoint = points[1] + const Offset(-15, 25);
      _drawLabel(
        canvas,
        anglePoint,
        'Angle: ${angle!.toStringAsFixed(1)}°',
        bgColor: Colors.amber.shade900.withOpacity(0.95),
      );
    }
  }

  void _drawLabel(Canvas canvas, Offset position, String text, {Color? bgColor}) {
    final textSpan = TextSpan(
      text: ' $text ',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11.0,
        fontWeight: FontWeight.bold,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    final rect = Rect.fromLTWH(
      position.dx - textPainter.width / 2,
      position.dy - textPainter.height / 2,
      textPainter.width,
      textPainter.height,
    );

    final paintBg = Paint()
      ..color = bgColor ?? Colors.teal.shade900
      ..style = PaintingStyle.fill;

    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paintBg);
    textPainter.paint(canvas, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class MeasurementCameraPage extends StatefulWidget {
  final String? loggedInUserId;

  const MeasurementCameraPage({Key? key, this.loggedInUserId}) : super(key: key);

  @override
  State<MeasurementCameraPage> createState() => _MeasurementCameraPageState();
}

class _MeasurementCameraPageState extends State<MeasurementCameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  // 1. ToF/LiDAR 하드웨어 센서 기기 통신 스트림을 위한 EventChannel 정의
  static const EventChannel _sensorEventChannel = EventChannel('com.fishlen.measurement/sensor');
  StreamSubscription? _sensorSubscription;
  double _liveDistance = 120.5; // 센서 수신 거리의 기본값 초기화 (mm)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 2중 안전 장치: 앱 라이프사이클 옵저버 추가
    _initializeCamera();
    _startRealSensorStream(); // 진짜 하드웨어 센서 스트림 연결
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 백그라운드로 진입할 경우 센서 스트림 구독을 일시 중단하여 누수 예방
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _sensorSubscription?.cancel();
      _sensorSubscription = null;
    } else if (state == AppLifecycleState.resumed) {
      _startRealSensorStream();
    }
  }

  // 2. 진짜 하드웨어 ToF/LiDAR 센서 스트림 구독
  void _startRealSensorStream() {
    _sensorSubscription?.cancel(); // 중복 구독 방지
    _sensorSubscription = _sensorEventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (mounted && event is num) {
          setState(() {
            // 하드웨어 3D 센서 레이캐스팅으로부터 수신한 실제 물리 거리값 매핑
            _liveDistance = event.toDouble();
          });
        }
      },
      onError: (dynamic error) {
        debugPrint('Hardware ToF sensor stream error: $error');
      }
    );
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      
      // 스마트폰 후면 카메라 강제 설정
      CameraDescription selectedCamera = cameras.first;
      for (var camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
      );
      _initializeControllerFuture = _controller!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  // 3. 철저한 메모리 누수 방지 (가장 중요)
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // 라이프사이클 옵저버 해제
    _sensorSubscription?.cancel(); // ToF 센서 스트림 구독 해제
    _sensorSubscription = null;
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161E),
        title: const Text('실시간 ToF/LiDAR 거리 계측'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _controller == null || _initializeControllerFuture == null
                ? const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                : FutureBuilder<void>(
                    future: _initializeControllerFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done) {
                        return CameraPreview(_controller!);
                      } else {
                        return const Center(child: CircularProgressIndicator(color: Colors.tealAccent));
                      }
                    },
                  ),
          ),
          // 중앙 크로스헤어 + 실시간 센서 거리 디스플레이
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(Icons.add, color: Colors.tealAccent, size: 40),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.tealAccent, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.tealAccent.withValues(alpha: 0.2),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Text(
                    '🎯 센서 측정 거리: ${_liveDistance.toStringAsFixed(1)} mm',
                    style: const TextStyle(
                      color: Colors.tealAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 30,
            child: Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);

                  try {
                    final supabase = Supabase.instance.client;

                    // 3. UI 및 Supabase INSERT 스키마 확장 (measurement_val 컬럼에 실시간 센서 거리 저장)
                    await supabase.from('tb_measurement').insert({
                      'name': 'mouse',
                      'measurement_value': double.parse(_liveDistance.toStringAsFixed(1)),
                      'confidence': 0.92,
                      'is_trained': 'N',
                      'username': widget.loggedInUserId,
                    });

                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('[SUCCESS] ToF/LiDAR 센서 계측 로그가 Supabase에 저장되었습니다.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    navigator.pop();
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('[ERROR] 로그 전송 실패: $e'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.gps_fixed_rounded, color: Colors.black),
                label: const Text(
                  '🎯 센서 계측 및 로그 전송',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
