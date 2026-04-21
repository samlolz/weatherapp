import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────
const String _apiKey = '327d5d9b95366fa08419d332872d751f';
const String _baseUrl = 'https://api.openweathermap.org/data/2.5';
// ─────────────────────────────────────────────

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const WeatherApp());
}

// ─── MODELS ───────────────────────────────────

class HourlyForecast {
  final DateTime time;
  final double temp;
  final String condition;
  final int pop;

  HourlyForecast({
    required this.time,
    required this.temp,
    required this.condition,
    required this.pop,
  });
}

class DailyForecast {
  final DateTime date;
  final double minTemp;
  final double maxTemp;
  final String condition;
  final int pop;

  DailyForecast({
    required this.date,
    required this.minTemp,
    required this.maxTemp,
    required this.condition,
    required this.pop,
  });
}

class WeatherData {
  final String city;
  final String country;
  final double temp;
  final double feelsLike;
  final double tempMin;
  final double tempMax;
  final int humidity;
  final double windSpeed;
  final int visibility;
  final String description;
  final String condition;
  final bool isNight;
  final String summary;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;

  WeatherData({
    required this.city,
    required this.country,
    required this.temp,
    required this.feelsLike,
    required this.tempMin,
    required this.tempMax,
    required this.humidity,
    required this.windSpeed,
    required this.visibility,
    required this.description,
    required this.condition,
    required this.isNight,
    required this.summary,
    required this.hourly,
    required this.daily,
  });
}

// ─── APP ──────────────────────────────────────

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weather',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const WeatherScreen(),
    );
  }
}

// ─── SCREEN ───────────────────────────────────

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen>
    with TickerProviderStateMixin {
  WeatherData? _weather;
  bool _loading = false;
  String? _error;
  bool _isCelsius = true;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  late AnimationController _particleController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);

    _fetchWeatherByCity('Jakarta');
  }

  @override
  void dispose() {
    _particleController.dispose();
    _fadeController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Fetch by City Name ──
  Future<void> _fetchWeatherByCity(String city) async {
    if (city.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse(
          '$_baseUrl/weather?q=${Uri.encodeComponent(city.trim())}&appid=$_apiKey&units=metric'));
      if (res.statusCode != 200) {
        setState(() {
          _error = res.statusCode == 404
              ? 'Kota "$city" tidak ditemukan'
              : 'Error: ${res.statusCode}';
          _loading = false;
        });
        return;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      await _fetchWithCoords(
          (json['coord']['lat'] as num).toDouble(),
          (json['coord']['lon'] as num).toDouble(),
          json);
    } catch (e) {
      setState(() {
        _error = 'Tidak ada koneksi internet';
        _loading = false;
      });
    }
  }

  // ── Fetch by GPS ──
  Future<void> _fetchByGPS() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error = 'Aktifkan GPS terlebih dahulu';
          _loading = false;
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Izin lokasi ditolak';
          _loading = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      final res = await http.get(Uri.parse(
          '$_baseUrl/weather?lat=${pos.latitude}&lon=${pos.longitude}&appid=$_apiKey&units=metric'));
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Gagal mengambil data cuaca';
          _loading = false;
        });
        return;
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      await _fetchWithCoords(pos.latitude, pos.longitude, json);
    } catch (e) {
      setState(() {
        _error = 'Gagal mendapatkan lokasi';
        _loading = false;
      });
    }
  }

  // ── Fetch Forecast + Parse ──
  Future<void> _fetchWithCoords(
      double lat, double lon, Map<String, dynamic> currentJson) async {
    try {
      final res = await http.get(Uri.parse(
          '$_baseUrl/forecast?lat=$lat&lon=$lon&appid=$_apiKey&units=metric'));
      if (res.statusCode != 200) {
        setState(() {
          _error = 'Gagal mengambil forecast';
          _loading = false;
        });
        return;
      }
      final forecastJson = jsonDecode(res.body) as Map<String, dynamic>;
      final wd = _parse(currentJson, forecastJson);
      setState(() {
        _weather = wd;
        _loading = false;
      });
      _fadeController.forward(from: 0);
      if (_scrollController.hasClients) {
        _scrollController.animateTo(0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    } catch (e) {
      setState(() {
        _error = 'Gagal memproses data';
        _loading = false;
      });
    }
  }

  WeatherData _parse(
      Map<String, dynamic> current, Map<String, dynamic> forecastJson) {
    final dt = current['dt'] as int;
    final sunrise = current['sys']['sunrise'] as int;
    final sunset = current['sys']['sunset'] as int;
    final isNight = dt < sunrise || dt > sunset;
    final condition =
        (current['weather'][0]['main'] as String).toLowerCase();
    final description = current['weather'][0]['description'] as String;

    final list = forecastJson['list'] as List;

    // ── Hourly: next 8 slots (24h) ──
    final hourly = <HourlyForecast>[];
    for (int i = 0; i < math.min(8, list.length); i++) {
      final item = list[i] as Map<String, dynamic>;
      hourly.add(HourlyForecast(
        time: DateTime.fromMillisecondsSinceEpoch((item['dt'] as int) * 1000),
        temp: (item['main']['temp'] as num).toDouble(),
        condition: (item['weather'][0]['main'] as String).toLowerCase(),
        pop: ((item['pop'] as num? ?? 0) * 100).round(),
      ));
    }

    // ── Daily: group by calendar day ──
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in list) {
      final date = DateTime.fromMillisecondsSinceEpoch(
          (item['dt'] as int) * 1000);
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(key, () => []).add(item as Map<String, dynamic>);
    }

    final daily = <DailyForecast>[];
    for (final entry in grouped.entries) {
      final temps =
          entry.value.map((e) => (e['main']['temp'] as num).toDouble()).toList();
      final pops = entry.value
          .map((e) => ((e['pop'] as num? ?? 0) * 100).round())
          .toList();
      final conds = entry.value
          .map((e) => (e['weather'][0]['main'] as String).toLowerCase())
          .toList();
      final condCount = <String, int>{};
      for (final c in conds) {
        condCount[c] = (condCount[c] ?? 0) + 1;
      }
      final dominant =
          condCount.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      daily.add(DailyForecast(
        date: DateTime.parse(entry.key),
        minTemp: temps.reduce(math.min),
        maxTemp: temps.reduce(math.max),
        condition: dominant,
        pop: pops.reduce(math.max),
      ));
    }

    final summaryMap = {
      'clear': isNight
          ? 'Malam cerah, langit bersih. Suhu akan turun menjelang dini hari.'
          : 'Cuaca cerah sepanjang hari. Nikmati aktivitas outdoor dengan tetap terhidrasi.',
      'clouds':
          'Berawan sebagian. Sesekali matahari terlihat di sela-sela awan tebal.',
      'rain':
          'Hujan diprediksi berlanjut. Siapkan payung sebelum keluar rumah.',
      'drizzle': 'Gerimis ringan sepanjang hari. Jalanan mungkin licin, berhati-hati.',
      'thunderstorm':
          'Waspada badai petir. Hindari area terbuka dan pohon tinggi.',
      'snow':
          'Salju diperkirakan turun. Jaga kehangatan dan hati-hati di jalan.',
      'mist':
          'Kabut tebal mengurangi jarak pandang. Berkendara dengan hati-hati.',
      'haze':
          'Kabut asap menurunkan kualitas udara. Pertimbangkan penggunaan masker.',
    };

    return WeatherData(
      city: current['name'] as String,
      country: current['sys']['country'] as String,
      temp: (current['main']['temp'] as num).toDouble(),
      feelsLike: (current['main']['feels_like'] as num).toDouble(),
      tempMin: (current['main']['temp_min'] as num).toDouble(),
      tempMax: (current['main']['temp_max'] as num).toDouble(),
      humidity: current['main']['humidity'] as int,
      windSpeed: (current['wind']['speed'] as num).toDouble(),
      visibility: ((current['visibility'] as int? ?? 10000) / 1000).round(),
      description: description,
      condition: condition,
      isNight: isNight,
      summary: summaryMap[condition] ?? 'Kondisi cuaca $description hari ini.',
      hourly: hourly,
      daily: daily,
    );
  }

  // ── Helpers ──
  double _convert(double c) => _isCelsius ? c : c * 9 / 5 + 32;
  String _tempStr(double c) => '${_convert(c).round()}°';
  String get _unit => _isCelsius ? 'C' : 'F';

  List<Color> _bgColors() {
    final w = _weather;
    if (w == null) {
      return [const Color(0xFF1C2340), const Color(0xFF0D1226), const Color(0xFF060B1A)];
    }
    if (w.isNight) {
      return [const Color(0xFF1C2340), const Color(0xFF0D1226), const Color(0xFF060B1A)];
    }
    switch (w.condition) {
      case 'clear':
        return [const Color(0xFF3B6FD4), const Color(0xFF2855A8), const Color(0xFF1C3A7A)];
      case 'clouds':
        return [const Color(0xFF4A5568), const Color(0xFF2D3748), const Color(0xFF1A202C)];
      case 'rain':
      case 'drizzle':
        return [const Color(0xFF2C3E6B), const Color(0xFF1E2D4F), const Color(0xFF121C33)];
      case 'thunderstorm':
        return [const Color(0xFF1A1A2E), const Color(0xFF16213E), const Color(0xFF0F1B36)];
      case 'snow':
        return [const Color(0xFF6B8CAE), const Color(0xFF4A6D8C), const Color(0xFF2E4F6A)];
      default:
        return [const Color(0xFF3B4F7A), const Color(0xFF253659), const Color(0xFF151E36)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColors = _bgColors();
    return Scaffold(
      backgroundColor: bgColors.last,
      body: Stack(
        children: [
          // Animated gradient background
          AnimatedContainer(
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: bgColors,
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Particle layer
          if (_weather != null)
            AnimatedBuilder(
              animation: _particleController,
              builder: (_, __) => CustomPaint(
                painter: _ParticlePainter(
                  condition: _weather!.condition,
                  isNight: _weather!.isNight,
                  progress: _particleController.value,
                ),
                size: Size.infinite,
              ),
            ),

          // Main UI
          SafeArea(
            child: _loading
                ? _buildLoader()
                : _error != null
                    ? _buildError()
                    : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoader() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white60),
          const SizedBox(height: 16),
          Text(
            'Memuat cuaca...',
            style: GoogleFonts.dmSans(color: Colors.white60, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.white30),
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                  color: Colors.white, fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 28),
            _buildSearchBox(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final w = _weather!;
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 12),
            _buildSearchBox(),
            const SizedBox(height: 28),
            _buildHero(w),
            const SizedBox(height: 20),
            _buildGlassCard(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Text(
                  w.summary,
                  style: GoogleFonts.dmSans(
                      color: Colors.white, fontSize: 14, height: 1.65),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildHourlyCard(w),
            const SizedBox(height: 12),
            _buildDailyCard(w),
            const SizedBox(height: 12),
            _buildDetailGrid(w),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  // ─── SEARCH BOX ──────────────────────────────
  Widget _buildSearchBox() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(Icons.search_rounded,
                    color: Color(0xFF888888), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.dmSans(
                      color: const Color(0xFF111111),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Cari kota...',
                      hintStyle: GoogleFonts.dmSans(
                        color: const Color(0xFFAAAAAA),
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    cursorColor: const Color(0xFF3B6FD4),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _fetchWeatherByCity(val.trim());
                        _searchController.clear();
                      }
                    },
                    textInputAction: TextInputAction.search,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),

        // GPS
        _iconBtn(
          icon: Icons.my_location_rounded,
          color: const Color(0xFF3B6FD4),
          onTap: _fetchByGPS,
        ),
        const SizedBox(width: 10),

        // Toggle °C / °F
        GestureDetector(
          onTap: () => setState(() => _isCelsius = !_isCelsius),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '°$_unit',
                style: GoogleFonts.dmSans(
                  color: const Color(0xFF3B6FD4),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _iconBtn(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  // ─── HERO ────────────────────────────────────
  Widget _buildHero(WeatherData w) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_rounded,
                color: Colors.white70, size: 18),
            const SizedBox(width: 4),
            Text(
              '${w.city}, ${w.country}',
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black38, blurRadius: 8)],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _tempStr(w.temp),
          style: GoogleFonts.dmSerifDisplay(
            color: Colors.white,
            fontSize: 96,
            height: 1.0,
            shadows: [
              Shadow(
                  color: Colors.black.withOpacity(0.3), blurRadius: 20),
            ],
          ),
        ),
        Text(
          _capitalize(w.description),
          style: GoogleFonts.dmSans(
              color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w400),
        ),
        const SizedBox(height: 6),
        Text(
          'H:${_tempStr(w.tempMax)}  L:${_tempStr(w.tempMin)}',
          style: GoogleFonts.dmSans(color: Colors.white54, fontSize: 15),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(
            'Terasa seperti ${_tempStr(w.feelsLike)}',
            style: GoogleFonts.dmSans(color: Colors.white, fontSize: 13),
          ),
        ),
      ],
    );
  }

  // ─── HOURLY ──────────────────────────────────
  Widget _buildHourlyCard(WeatherData w) {
    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.access_time_rounded, 'PRAKIRAAN PER JAM'),
          const Divider(color: Colors.white12, height: 1),
          SizedBox(
            height: 112,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              itemCount: w.hourly.length,
              itemBuilder: (_, i) {
                final h = w.hourly[i];
                final isNow = i == 0;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 72,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: isNow
                        ? Colors.white.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        isNow ? Border.all(color: Colors.white30) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Text(
                        isNow ? 'Now' : _hourLabel(h.time),
                        style: GoogleFonts.dmSans(
                          color:
                              isNow ? Colors.white : Colors.white70,
                          fontSize: 12,
                          fontWeight: isNow
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      if (h.pop > 20)
                        Text(
                          '${h.pop}%',
                          style: GoogleFonts.dmSans(
                              color: const Color(0xFF7EC8E3), fontSize: 10),
                        )
                      else
                        const SizedBox(height: 14),
                      _condIcon(h.condition, size: 22),
                      Text(
                        _tempStr(h.temp),
                        style: GoogleFonts.dmSans(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── DAILY ───────────────────────────────────
  Widget _buildDailyCard(WeatherData w) {
    final days = w.daily.take(5).toList();
    final allMin = days.map((d) => d.minTemp).reduce(math.min);
    final allMax = days.map((d) => d.maxTemp).reduce(math.max);

    return _buildGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.calendar_today_rounded, 'PRAKIRAAN 5 HARI'),
          const Divider(color: Colors.white12, height: 1),
          ...days.asMap().entries.map((entry) {
            final i = entry.key;
            final d = entry.value;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(
                          i == 0 ? 'Today' : _dayLabel(d.date),
                          style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: d.pop > 20
                            ? Text(
                                '${d.pop}%',
                                style: GoogleFonts.dmSans(
                                    color: const Color(0xFF7EC8E3),
                                    fontSize: 12),
                              )
                            : null,
                      ),
                      _condIcon(d.condition, size: 20),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 36,
                        child: Text(
                          _tempStr(d.minTemp),
                          textAlign: TextAlign.right,
                          style: GoogleFonts.dmSans(
                              color: Colors.white54, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TempBar(
                          min: d.minTemp,
                          max: d.maxTemp,
                          globalMin: allMin,
                          globalMax: allMax,
                          condition: d.condition,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 36,
                        child: Text(
                          _tempStr(d.maxTemp),
                          style: GoogleFonts.dmSans(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < days.length - 1)
                  const Divider(
                      color: Colors.white10,
                      height: 1,
                      indent: 16,
                      endIndent: 16),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ─── DETAIL GRID ─────────────────────────────
  Widget _buildDetailGrid(WeatherData w) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.25,
      children: [
        _detailTile(
          icon: Icons.water_drop_rounded,
          label: 'KELEMBABAN',
          value: '${w.humidity}%',
          sub: w.humidity > 70
              ? 'Tinggi'
              : w.humidity > 40
                  ? 'Normal'
                  : 'Rendah',
        ),
        _detailTile(
          icon: Icons.air_rounded,
          label: 'ANGIN',
          value: '${w.windSpeed.toStringAsFixed(1)} m/s',
          sub: '${(w.windSpeed * 3.6).toStringAsFixed(0)} km/jam',
        ),
        _detailTile(
          icon: Icons.visibility_rounded,
          label: 'VISIBILITAS',
          value: '${w.visibility} km',
          sub: w.visibility >= 10
              ? 'Sangat Jelas'
              : w.visibility >= 5
                  ? 'Cukup'
                  : 'Terbatas',
        ),
        _detailTile(
          icon: Icons.thermostat_rounded,
          label: 'TERASA SEPERTI',
          value: _tempStr(w.feelsLike),
          sub: w.feelsLike > w.temp ? 'Lebih Panas' : 'Lebih Sejuk',
        ),
      ],
    );
  }

  Widget _detailTile({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
  }) {
    return _buildGlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white54, size: 13),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    style: GoogleFonts.dmMono(
                        color: Colors.white54, fontSize: 10, letterSpacing: 1),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: GoogleFonts.dmSerifDisplay(
                  color: Colors.white, fontSize: 30),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: GoogleFonts.dmSans(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ─── GLASS CARD ──────────────────────────────
  Widget _buildGlassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.18)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _cardHeader(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 13),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmMono(
                color: Colors.white54, fontSize: 11, letterSpacing: 1.5),
          ),
        ],
      ),
    );
  }

  // ─── SMALL HELPERS ───────────────────────────
  Widget _condIcon(String condition, {double size = 22}) {
    final map = <String, IconData>{
      'clear': Icons.wb_sunny_rounded,
      'clouds': Icons.cloud_rounded,
      'rain': Icons.grain_rounded,
      'drizzle': Icons.water_drop_rounded,
      'thunderstorm': Icons.bolt_rounded,
      'snow': Icons.ac_unit_rounded,
      'mist': Icons.blur_on_rounded,
      'haze': Icons.blur_circular_rounded,
      'fog': Icons.blur_on_rounded,
    };
    final colorMap = <String, Color>{
      'clear': const Color(0xFFFFD700),
      'clouds': const Color(0xFFB0BEC5),
      'rain': const Color(0xFF7EC8E3),
      'drizzle': const Color(0xFF81D4FA),
      'thunderstorm': const Color(0xFFFFEE58),
      'snow': Colors.white,
      'mist': const Color(0xFFCFD8DC),
      'haze': const Color(0xFFD7CCC8),
      'fog': const Color(0xFFCFD8DC),
    };
    return Icon(
      map[condition] ?? Icons.cloud_rounded,
      color: colorMap[condition] ?? Colors.white70,
      size: size,
    );
  }

  String _hourLabel(DateTime dt) {
    final h = dt.hour;
    final period = h >= 12 ? 'PM' : 'AM';
    final hour = h == 0 ? 12 : h > 12 ? h - 12 : h;
    return '$hour$period';
  }

  String _dayLabel(DateTime dt) {
    const d = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return d[dt.weekday % 7];
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ─── TEMP BAR ─────────────────────────────────

class _TempBar extends StatelessWidget {
  final double min, max, globalMin, globalMax;
  final String condition;

  const _TempBar({
    required this.min,
    required this.max,
    required this.globalMin,
    required this.globalMax,
    required this.condition,
  });

  @override
  Widget build(BuildContext context) {
    final range = (globalMax - globalMin).clamp(0.1, double.infinity);
    final leftFrac = ((min - globalMin) / range).clamp(0.0, 1.0);
    final barWidth = ((max - min) / range).clamp(0.05, 1.0);

    final barColors = <String, List<Color>>{
      'clear': [const Color(0xFFFFAB40), const Color(0xFFFFD740)],
      'rain': [const Color(0xFF4FC3F7), const Color(0xFF0288D1)],
      'drizzle': [const Color(0xFF81D4FA), const Color(0xFF4FC3F7)],
      'snow': [const Color(0xFFE1F5FE), Colors.white],
      'thunderstorm': [const Color(0xFFCE93D8), const Color(0xFF9C27B0)],
    };
    final colors = barColors[condition] ??
        [const Color(0xFF80CBC4), const Color(0xFF26A69A)];

    return LayoutBuilder(builder: (_, constraints) {
      final total = constraints.maxWidth;
      return Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Positioned(
            left: leftFrac * total,
            width: barWidth * total,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(colors: colors),
              ),
            ),
          ),
        ],
      );
    });
  }
}

// ─── PARTICLE PAINTER ────────────────────────

class _ParticlePainter extends CustomPainter {
  final String condition;
  final bool isNight;
  final double progress;

  _ParticlePainter(
      {required this.condition,
      required this.isNight,
      required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (isNight) _drawStars(canvas, size);
    switch (condition) {
      case 'rain':
      case 'drizzle':
        _drawRain(canvas, size);
        break;
      case 'snow':
        _drawSnow(canvas, size);
        break;
      case 'clear':
        if (!isNight) _drawSunRays(canvas, size);
        break;
    }
  }

  void _drawStars(Canvas canvas, Size size) {
    final rng = math.Random(42);
    for (int i = 0; i < 70; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * 0.55;
      final r = rng.nextDouble() * 1.5 + 0.4;
      final twinkle = (math.sin(progress * math.pi * 2 + i * 0.7) + 1) / 2;
      final paint = Paint()
        ..color = Colors.white.withOpacity(0.2 + 0.6 * twinkle);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _drawRain(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final paint = Paint()
      ..color = const Color(0xFF7EC8E3).withOpacity(0.45)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 35; i++) {
      final x = rng.nextDouble() * size.width;
      final baseY = rng.nextDouble() * size.height;
      final y = (baseY + progress * size.height) % size.height;
      canvas.drawLine(Offset(x, y), Offset(x - 3, y + 16), paint);
    }
  }

  void _drawSnow(Canvas canvas, Size size) {
    final rng = math.Random(13);
    final paint = Paint()..color = Colors.white.withOpacity(0.65);
    for (int i = 0; i < 30; i++) {
      final x = rng.nextDouble() * size.width +
          math.sin(progress * math.pi * 2 + i) * 12;
      final baseY = rng.nextDouble() * size.height;
      final y = (baseY + progress * size.height * 0.5) % size.height;
      canvas.drawCircle(Offset(x, y), rng.nextDouble() * 3 + 1, paint);
    }
  }

  void _drawSunRays(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFD700).withOpacity(0.05)
      ..style = PaintingStyle.fill;
    final cx = size.width * 0.82;
    const cy = 60.0;
    for (int i = 0; i < 8; i++) {
      final angle = progress * math.pi * 2 / 8 + i * math.pi / 4;
      final path = Path()
        ..moveTo(cx, cy)
        ..lineTo(cx + math.cos(angle - 0.12) * size.width * 1.5,
            cy + math.sin(angle - 0.12) * size.width * 1.5)
        ..lineTo(cx + math.cos(angle + 0.12) * size.width * 1.5,
            cy + math.sin(angle + 0.12) * size.width * 1.5)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.progress != progress || old.condition != condition;
}