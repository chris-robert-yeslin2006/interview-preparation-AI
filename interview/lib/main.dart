// lib/main.dart
//
// pubspec.yaml (add these):
// dependencies:
//   flutter:
//     sdk: flutter
//   http: ^1.2.2
//   speech_to_text: ^6.6.2
//   flutter_tts: ^3.8.3
//
// iOS: add microphone permission to ios/Runner/Info.plist:
// <key>NSMicrophoneUsageDescription</key><string>Speech input for interview.</string>
// Android: add to AndroidManifest.xml:
// <uses-permission android:name="android.permission.RECORD_AUDIO"/>

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InterviewApp());
}

const kApiBase = 'http://127.0.0.1:8000'; // FastAPI base URL

class InterviewApp extends StatelessWidget {
  const InterviewApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Interview Agent',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const StartScreen(),
    );
  }
}

/// ======================
/// Data models
/// ======================
class StartPayload {
  final String company;
  final String role;
  final String interviewType; // HR / Technical / Coding
  final int maxQuestions;
  final String candidateName;
  StartPayload({
    required this.company,
    required this.role,
    required this.interviewType,
    required this.maxQuestions,
    required this.candidateName,
  });
  Map<String, dynamic> toJson() => {
        'company': company,
        'role': role,
        'interview_type': interviewType,
        'max_questions': maxQuestions,
        'candidate_name': candidateName,
      };
}

class StartResponse {
  final String question;
  final int questionNumber;
  final int totalQuestions;
  final String sessionId;
  StartResponse({
    required this.question,
    required this.questionNumber,
    required this.totalQuestions,
    required this.sessionId,
  });
  factory StartResponse.fromJson(Map<String, dynamic> j) => StartResponse(
        question: j['question'] ?? '',
        questionNumber: j['question_number'] ?? 1,
        totalQuestions: j['total_questions'] ?? 1,
        sessionId: j['session_id'] ?? '',
      );
}

class AnswerPayload {
  final String answer;
  final String sessionId;
  AnswerPayload({required this.answer, required this.sessionId});
  Map<String, dynamic> toJson() => {'answer': answer, 'session_id': sessionId};
}

class AnswerResponse {
  final String question;
  final int questionNumber;
  final int totalQuestions;
  final String sessionId;
  final bool interviewComplete;
  final int? currentScore;
  final String? currentFeedback;
  final Map<String, dynamic>? finalResults;
  AnswerResponse({
    required this.question,
    required this.questionNumber,
    required this.totalQuestions,
    required this.sessionId,
    required this.interviewComplete,
    this.currentScore,
    this.currentFeedback,
    this.finalResults,
  });
  factory AnswerResponse.fromJson(Map<String, dynamic> j) => AnswerResponse(
        question: j['question'] ?? '',
        questionNumber: j['question_number'] ?? 1,
        totalQuestions: j['total_questions'] ?? 1,
        sessionId: j['session_id'] ?? '',
        interviewComplete: j['interview_complete'] ?? false,
        currentScore: j['current_score'],
        currentFeedback: j['current_feedback'],
        finalResults: j['final_results'],
      );
}

class ResultsResponse {
  final String sessionId;
  final Map<String, dynamic> context;
  final String startTime;
  final String endTime;
  final double durationMinutes;
  final int totalScore;
  final double averageScore;
  final int maxPossibleScore;
  final double percentage;
  final List<dynamic> detailedResults;
  ResultsResponse({
    required this.sessionId,
    required this.context,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.totalScore,
    required this.averageScore,
    required this.maxPossibleScore,
    required this.percentage,
    required this.detailedResults,
  });
  factory ResultsResponse.fromJson(Map<String, dynamic> j) => ResultsResponse(
        sessionId: j['session_id'],
        context: j['context'],
        startTime: j['start_time'],
        endTime: j['end_time'],
        durationMinutes: (j['duration_minutes'] ?? 0).toDouble(),
        totalScore: j['total_score'] ?? 0,
        averageScore: (j['average_score'] ?? 0).toDouble(),
        maxPossibleScore: j['max_possible_score'] ?? 0,
        percentage: (j['percentage'] ?? 0).toDouble(),
        detailedResults: (j['detailed_results'] ?? []) as List<dynamic>,
      );
}

/// ======================
/// API client helpers
/// ======================
Future<StartResponse> apiStartInterview(StartPayload payload) async {
  final r = await http.post(
    Uri.parse('$kApiBase/start'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(payload.toJson()),
  );
  if (r.statusCode != 200) {
    throw Exception('Start failed: ${r.body}');
  }
  final j = jsonDecode(r.body);
  if (j['error'] != null) throw Exception(j['error']);
  return StartResponse.fromJson(j);
}

Future<AnswerResponse> apiSendAnswer(AnswerPayload payload) async {
  final r = await http.post(
    Uri.parse('$kApiBase/answer'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(payload.toJson()),
  );
  if (r.statusCode != 200) {
    throw Exception('Answer failed: ${r.body}');
  }
  final j = jsonDecode(r.body);
  if (j['error'] != null) throw Exception(j['error']);
  return AnswerResponse.fromJson(j);
}

Future<ResultsResponse> apiGetResults(String sessionId) async {
  final r = await http.get(Uri.parse('$kApiBase/results/$sessionId'));
  if (r.statusCode != 200) throw Exception('Results failed: ${r.body}');
  final j = jsonDecode(r.body);
  if (j['error'] != null) throw Exception(j['error']);
  return ResultsResponse.fromJson(j);
}

Future<String> apiSaveLog(String sessionId) async {
  final r = await http.post(Uri.parse('$kApiBase/save_interview/$sessionId'));
  if (r.statusCode != 200) throw Exception('Save failed: ${r.body}');
  final j = jsonDecode(r.body);
  if (j['error'] != null) throw Exception(j['error']);
  return j['message'] ?? 'Saved.';
}

/// ======================
/// Start Screen (form)
/// ======================
class StartScreen extends StatefulWidget {
  const StartScreen({super.key});
  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController(text: 'Google');
  final _role = TextEditingController(text: 'Software Engineer');
  final _name = TextEditingController(text: 'Chris');
  final _maxQ = TextEditingController(text: '5');
  String _type = 'Technical';
  bool _loading = false;

  @override
  void dispose() {
    _company.dispose();
    _role.dispose();
    _name.dispose();
    _maxQ.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final payload = StartPayload(
        company: _company.text.trim(),
        role: _role.text.trim(),
        interviewType: _type,
        maxQuestions: int.tryParse(_maxQ.text.trim())?.clamp(1, 20) ?? 5,
        candidateName: _name.text.trim(),
      );
      final res = await apiStartInterview(payload);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InterviewScreen(
            sessionId: res.sessionId,
            totalQuestions: res.totalQuestions,
            firstQuestion: res.question,
            questionNumber: res.questionNumber,
            interviewType: _type,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Start failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    return Scaffold(
      appBar: AppBar(title: const Text('AI Interview – Setup')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Your Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            Padding(padding: pad),
            TextFormField(
              controller: _company,
              decoration: const InputDecoration(
                labelText: 'Company',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            Padding(padding: pad),
            TextFormField(
              controller: _role,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            Padding(padding: pad),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Interview Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'HR', child: Text('HR')),
                DropdownMenuItem(value: 'Technical', child: Text('Technical')),
                DropdownMenuItem(value: 'Coding', child: Text('Coding')),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'Technical'),
            ),
            Padding(padding: pad),
            TextFormField(
              controller: _maxQ,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max Questions (1–20)',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1 || n > 20) return 'Enter 1–20';
                return null;
              },
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _start,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_circle_fill),
              label: const Text('Start Interview'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ======================
/// Interview Screen
/// ======================
class InterviewScreen extends StatefulWidget {
  final String sessionId;
  final int totalQuestions;
  final String firstQuestion;
  final int questionNumber;
  final String interviewType;
  const InterviewScreen({
    super.key,
    required this.sessionId,
    required this.totalQuestions,
    required this.firstQuestion,
    required this.questionNumber,
    required this.interviewType,
  });

  @override
  State<InterviewScreen> createState() => _InterviewScreenState();
}

class _InterviewScreenState extends State<InterviewScreen> {
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  bool _listening = false;
  bool _sending = false;
  String _answerText = '';
  final _manualCtrl = TextEditingController();

  int _qNumber = 1;
  String _currentQuestion = '';
  final List<_Turn> _turns = []; // for bubbles
  int? _lastScore;
  String? _lastFeedback;

  @override
  void initState() {
    super.initState();
    _currentQuestion = widget.firstQuestion;
    _qNumber = widget.questionNumber;

    // speak the first question
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak(_currentQuestion);
      _turns.add(_Turn(role: TurnRole.assistant, text: _currentQuestion));
      setState(() {});
    });
  }

  @override
  void dispose() {
    _manualCtrl.dispose();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    // Pause listening to avoid echo
    if (_listening) await _stopListening();
    await _tts.stop();
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.98);
    await _tts.speak(text);
  }

  Future<void> _startListening() async {
    final ok = await _speech.initialize(
      onStatus: (s) {},
      onError: (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Mic error: ${e.errorMsg}')));
      },
    );
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech not available')),
      );
      return;
    }
    setState(() {
      _listening = true;
      _answerText = '';
    });
    await _speech.listen(
      localeId: 'en_US',
      onResult: (r) {
        setState(() => _answerText = r.recognizedWords);
      },
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _listening = false);
  }

  Future<void> _sendAnswer(String text) async {
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);

    try {
      _turns.add(_Turn(role: TurnRole.user, text: text));
      final res = await apiSendAnswer(
        AnswerPayload(answer: text, sessionId: widget.sessionId),
      );

      // show evaluation for this answer (if provided)
      _lastScore = res.currentScore;
      _lastFeedback = res.currentFeedback;

      if (res.interviewComplete) {
        // final message and navigate to results
        _turns.add(_Turn(role: TurnRole.assistant, text: res.question));
        await _speak(res.question);
        if (!mounted) return;
        final results = await apiGetResults(widget.sessionId);
        if (!mounted) return;
        // optionally save log
        String? savedMsg;
        try {
          savedMsg = await apiSaveLog(widget.sessionId);
        } catch (_) {}
        // go to summary screen
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ResultsScreen(results: results, saveMsg: savedMsg),
          ),
        );
        return;
      }

      // next question
      _currentQuestion = res.question;
      _qNumber = res.questionNumber;
      _turns.add(_Turn(role: TurnRole.assistant, text: _currentQuestion));
      await _speak(_currentQuestion);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _answerText = '';
        _manualCtrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _qNumber / widget.totalQuestions;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.interviewType} Interview'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Center(
              child: Text('Q $_qNumber / ${widget.totalQuestions}'),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: progress.clamp(0, 1)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: _turns.length + ((_lastScore != null || _lastFeedback != null) ? 1 : 0),
              itemBuilder: (context, index) {
                // After each answer show feedback card
                if (index == _turns.length && (_lastScore != null || _lastFeedback != null)) {
                  return _FeedbackCard(score: _lastScore, feedback: _lastFeedback);
                }
                final t = _turns[index];
                final isUser = t.role == TurnRole.user;
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.indigo.shade100 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      t.text,
                      style: const TextStyle(fontSize: 15.5, height: 1.3),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualCtrl,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Type your answer or use the mic…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _sending ? null : () => _sendAnswer(_manualCtrl.text),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  tooltip: 'Send',
                ),
                const SizedBox(width: 4),
                FloatingActionButton.small(
                  onPressed: _listening ? _stopListening : _startListening,
                  child: Icon(_listening ? Icons.stop : Icons.mic),
                ),
              ],
            ),
          ),
          if (_listening || _answerText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _answerText.isEmpty ? 'Listening…' : _answerText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ),
                  if (_answerText.isNotEmpty)
                    TextButton(
                      onPressed: _sending ? null : () => _sendAnswer(_answerText),
                      child: const Text('Submit'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum TurnRole { user, assistant }

class _Turn {
  final TurnRole role;
  final String text;
  _Turn({required this.role, required this.text});
}

class _FeedbackCard extends StatelessWidget {
  final int? score;
  final String? feedback;
  const _FeedbackCard({this.score, this.feedback});

  @override
  Widget build(BuildContext context) {
    if (score == null && (feedback == null || feedback!.isEmpty)) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.assessment),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (score != null)
                    Text('Score: $score / 10', style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (feedback != null && feedback!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Feedback: $feedback'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ======================
/// Results Screen
/// ======================
class ResultsScreen extends StatelessWidget {
  final ResultsResponse results;
  final String? saveMsg;
  const ResultsScreen({super.key, required this.results, this.saveMsg});

  @override
  Widget build(BuildContext context) {
    final items = results.detailedResults;
    return Scaffold(
      appBar: AppBar(title: const Text('Interview Results')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session: ${results.sessionId}', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  Text('Role: ${results.context['role']} @ ${results.context['company']}'),
                  const SizedBox(height: 6),
                  Text('Type: ${results.context['interview_type']}'),
                  const SizedBox(height: 6),
                  Text('Duration: ${results.durationMinutes} mins'),
                  const SizedBox(height: 6),
                  Text('Total Score: ${results.totalScore}/${results.maxPossibleScore}'),
                  const SizedBox(height: 6),
                  Text('Average: ${results.averageScore}  (${results.percentage}%)'),
                  if (saveMsg != null) ...[
                    const SizedBox(height: 8),
                    Text(saveMsg!, style: TextStyle(color: Colors.green.shade700)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Detailed Q&A', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final row in items)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Q${row['question_number']}: ${row['question']}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text('Your answer: ${row['answer']}'),
                    const SizedBox(height: 6),
                    Text('Score: ${row['score']}'),
                    const SizedBox(height: 4),
                    Text('Feedback: ${row['feedback']}'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const StartScreen()),
              (r) => false,
            ),
            icon: const Icon(Icons.replay),
            label: const Text('Restart'),
          ),
        ],
      ),
    );
  }
}
