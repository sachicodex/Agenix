import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service for interacting with Google Gemini API for text optimization
class GeminiService {
  static const String _apiKey = 'AIzaSyC5MK7csZ1p8BDadgWtLEBhnyNgeQcJbCs';

  /// Optimize event title to be short, clear, and event-title friendly
  Future<String> optimizeTitle(String title) async {
    if (title.trim().isEmpty) {
      return title;
    }

    final prompt =
        '''
You are a professional text optimizer. Your task is to optimize the following event title for a Google Calendar event.

Rules:
- Make it short, clear, and professional
- Keep it under 60 characters
- Remove unnecessary words
- Return ONLY the optimized title text
- Do NOT include any explanations, labels, or prefixes
- Do NOT write "Optimized title:" or similar text
- Return ONLY the title itself

Original title: "$title"

Return only the optimized title:''';

    try {
      final response = await _callGeminiAPI(prompt);
      return _cleanAIResponse(response);
    } catch (e) {
      throw Exception('Failed to optimize title: $e');
    }
  }

  /// Optimize description based on title and existing description
  Future<String> optimizeDescription(String title, String description) async {
    if (title.trim().isEmpty) {
      return description;
    }

    final prompt =
        '''
You are a professional text optimizer. Your task is to optimize the following Google Calendar event description.

Rules:
- Make it clear, professional, and well-formatted
- Use the title as context
- Keep it concise but informative
- Format it properly for Google Calendar
- Return ONLY the optimized description text
- Do NOT include any explanations, labels, or prefixes
- Do NOT write "Here's a suitable description:" or "Optimized description:" or similar text
- Return ONLY the description itself

Event Title: "$title"
Current Description: "$description"

Return only the optimized description:''';

    try {
      final response = await _callGeminiAPI(prompt);
      return _cleanAIResponse(response);
    } catch (e) {
      throw Exception('Failed to optimize description: $e');
    }
  }

  /// Generate description automatically from title
  Future<String> generateDescription(String title) async {
    if (title.trim().isEmpty) {
      return '';
    }

    final prompt =
        '''
You are a professional content generator. Your task is to generate a description for a Google Calendar event based on the following title.

Rules:
- Make it professional, concise, and informative
- Keep it brief (2-3 sentences max)
- Format it properly for Google Calendar
- Return ONLY the description text
- Do NOT include any explanations, labels, or prefixes
- Do NOT write "Here's a suitable description:" or "Description:" or similar text
- Return ONLY the description itself

Event Title: "$title"

Return only the description:''';

    try {
      final response = await _callGeminiAPI(prompt);
      return _cleanAIResponse(response);
    } catch (e) {
      throw Exception('Failed to generate description: $e');
    }
  }

  /// Call Gemini API with the given prompt
  /// Uses official Google Gemini API format: https://ai.google.dev/gemini-api/docs
  /// Tries multiple model names as fallback
  Future<String> _callGeminiAPI(String prompt) async {
    // List of available models to try (in order of preference)
    // Based on official docs: https://ai.google.dev/gemini-api/docs
    final models = [
      'gemini-2.5-flash', // Most balanced model (recommended)
      'gemini-2.5-flash-lite', // Fastest and most cost-efficient
      'gemini-2.5-pro', // Powerful reasoning model
      'gemini-1.5-flash', // Fallback for older API keys
      'gemini-1.5-pro', // Fallback for older API keys
    ];

    Exception? lastError;

    for (final model in models) {
      try {
        // Official API endpoint format: v1beta/models/{model}:generateContent
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
        );

        final result = await _makeAPIRequest(url, prompt);
        return result;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        // If error is about model not found, try next model
        if (e.toString().contains('not found') ||
            e.toString().contains('not supported')) {
          continue; // Try next model
        }
        // For other errors (network, auth, etc.), throw immediately
        rethrow;
      }
    }

    // If all models failed, throw the last error
    throw lastError ?? Exception('All model configurations failed');
  }

  /// Make the actual API request
  /// Uses x-goog-api-key header as per official documentation
  Future<String> _makeAPIRequest(Uri url, String prompt) async {
    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.7,
        'topK': 40,
        'topP': 0.95,
        'maxOutputTokens': 1024,
      },
    };

    final response = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key':
                _apiKey, // Official format: header instead of query param
          },
          body: jsonEncode(requestBody),
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception(
              'Request timeout. Please check your internet connection and try again.',
            );
          },
        );

    if (response.statusCode != 200) {
      String errorMessage = 'Unknown error';
      try {
        final errorBody = jsonDecode(response.body);
        errorMessage =
            errorBody['error']?['message'] ??
            errorBody['error']?['status'] ??
            'API request failed';
      } catch (_) {
        errorMessage =
            'HTTP ${response.statusCode}: ${response.reasonPhrase ?? "Unknown error"}';
      }
      throw Exception('AI Service Error: $errorMessage');
    }

    final responseBody = jsonDecode(response.body);
    final candidates = responseBody['candidates'] as List?;

    if (candidates == null || candidates.isEmpty) {
      // Check for safety ratings or blocked content
      if (responseBody['promptFeedback'] != null) {
        throw Exception(
          'Content was blocked by safety filters. Please try different text.',
        );
      }
      throw Exception('No response from AI. Please try again.');
    }

    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;

    if (parts == null || parts.isEmpty) {
      throw Exception('Invalid response format from AI service.');
    }

    final text = parts[0]['text'] as String?;
    if (text == null || text.isEmpty) {
      throw Exception('Empty response from AI. Please try again.');
    }

    return text;
  }

  /// Clean AI response by removing common prefixes and explanatory text
  String _cleanAIResponse(String response) {
    String cleaned = response.trim();

    // Remove common prefixes that AI might add
    final prefixesToRemove = [
      "Here's a suitable description:",
      "Here is a suitable description:",
      "Here's the description:",
      "Description:",
      "Optimized title:",
      "Optimized description:",
      "Title:",
      "Event description:",
      "Event Description:",
      "Generated description:",
      "Here's the optimized title:",
      "Here's the optimized description:",
    ];

    for (final prefix in prefixesToRemove) {
      if (cleaned.toLowerCase().startsWith(prefix.toLowerCase())) {
        cleaned = cleaned.substring(prefix.length).trim();
        // Also remove any leading colon or dash that might remain
        cleaned = cleaned.replaceFirst(RegExp(r'^[:\-\s]+'), '');
      }
    }

    // Remove quotes if the entire response is wrapped in quotes
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }

    return cleaned.trim();
  }
}
