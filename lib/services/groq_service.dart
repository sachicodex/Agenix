import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_key_storage_service.dart';

/// Service for interacting with Groq API for text optimization
/// Groq API Documentation: https://console.groq.com/docs
class GroqService {
  final ApiKeyStorageService _apiKeyStorage = ApiKeyStorageService();

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
      final response = await _callGroqAPI(prompt);
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
      final response = await _callGroqAPI(prompt);
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
      final response = await _callGroqAPI(prompt);
      return _cleanAIResponse(response);
    } catch (e) {
      throw Exception('Failed to generate description: $e');
    }
  }

  /// Call Groq API with the given prompt
  /// Uses Groq API format: https://console.groq.com/docs
  /// Uses llama-3.1-8b-instant model for fast, high-quality text generation
  Future<String> _callGroqAPI(String prompt) async {
    const model =
        'llama-3.1-8b-instant'; // Fast and efficient text generation model

    final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');

    return await _makeAPIRequest(url, prompt, model);
  }

  /// Make the actual API request to Groq
  /// Uses Authorization header with Bearer token as per Groq API documentation
  Future<String> _makeAPIRequest(Uri url, String prompt, String model) async {
    // Get API key from storage
    final apiKey = await _apiKeyStorage.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw Exception(
        'AI API key not configured. Please set up your API key in Settings.',
      );
    }

    // Groq API uses OpenAI-compatible format
    final requestBody = {
      'model': model,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
      'max_tokens': 1024,
      'top_p': 0.95,
    };

    final response = await http
        .post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey', // Groq uses Bearer token
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
      String? retryAfter;

      try {
        final errorBody = jsonDecode(response.body);
        errorMessage =
            errorBody['error']?['message'] ??
            errorBody['error']?['type'] ??
            'API request failed';

        // Extract rate limit information
        if (response.statusCode == 429) {
          retryAfter = errorBody['error']?['retry_after']?.toString();
          final rateLimitInfo = errorBody['error']?['rate_limit'];
          if (rateLimitInfo != null) {
            errorMessage += '\n\nRate Limit Details:';
            if (rateLimitInfo['limit'] != null) {
              errorMessage += '\n* Limit: ${rateLimitInfo['limit']}';
            }
            if (rateLimitInfo['remaining'] != null) {
              errorMessage += '\n* Remaining: ${rateLimitInfo['remaining']}';
            }
            if (rateLimitInfo['reset'] != null) {
              errorMessage += '\n* Resets at: ${rateLimitInfo['reset']}';
            }
          }
          if (retryAfter != null) {
            errorMessage += '\n\nPlease retry in ${retryAfter}s.';
          }
        }

        // Handle quota exceeded
        if (errorMessage.toLowerCase().contains('quota') ||
            errorMessage.toLowerCase().contains('billing')) {
          errorMessage +=
              '\n\nPlease check your Groq API plan and billing details at: https://console.groq.com/settings/billing';
        }
      } catch (_) {
        errorMessage =
            'HTTP ${response.statusCode}: ${response.reasonPhrase ?? "Unknown error"}';
      }

      throw Exception('AI Service Error: $errorMessage');
    }

    final responseBody = jsonDecode(response.body);
    final choices = responseBody['choices'] as List?;

    if (choices == null || choices.isEmpty) {
      throw Exception('No response from AI. Please try again.');
    }

    final message = choices[0]['message'] as Map<String, dynamic>?;
    final content = message?['content'] as String?;

    if (content == null || content.isEmpty) {
      throw Exception('Empty response from AI. Please try again.');
    }

    return content;
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
