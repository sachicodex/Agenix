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
You are a Google Calendar event title rewriter.

Goal: Improve the title to sound natural, simple, and human — WITHOUT changing meaning.

Core Rules:
- Preserve the exact context and intent from the original title.
- Keep important keywords (project name, topic, person, task, deadline, location if present).
- Remove unnecessary filler words.
- Keep it short and clean (under 100 characters when possible).

Meeting/Call Word Rule (VERY IMPORTANT):
- If the original title contains words like "meeting", "call", "sync", "discussion", "session", or "interview",
  you may keep or slightly refine them.
- If the original title does NOT contain or clearly imply them, DO NOT add those words.

Hard Don’ts:
- Do NOT invent new context.
- Do NOT add new people, platforms, time, or locations.
- If unsure, return the original text unchanged.
- Output ONLY the final title text. No quotes. No labels.

Original title: "$title"

Return ONLY the improved title:
''';

    try {
      final response = await _callGroqAPI(prompt);
      return _cleanAIResponse(response);
    } catch (e) {
      throw Exception('Failed to optimize title: $e');
    }
  }

  /// Optimize description based on original user title, AI-generated title, and existing description
  Future<String> optimizeDescription(
    String originalUserTitle,
    String aiGeneratedTitle,
    String description,
  ) async {
    if (originalUserTitle.trim().isEmpty && aiGeneratedTitle.trim().isEmpty) {
      return description;
    }

    final prompt =
        '''
You are a Google Calendar event description editor.

Goal: Rewrite the description to be clearer, well-structured, and human-friendly — WITHOUT changing meaning.

Rules:
- Use the titles as context.
- Preserve all important details from the current description (links, names, agenda, notes).
- Improve readability using short lines or bullet points if helpful.
- Keep it concise and professional.

Meeting/Call Word Rule:
- If the titles or description already contain words like "meeting", "call", "sync", or similar,
  you may keep them.
- If they are not present or clearly implied, DO NOT add them.

Hard Don’ts:
- Do NOT invent new details.
- Do NOT change the purpose of the event.
- If unsure, return the original description unchanged.
- Output ONLY the final description text. No quotes. No labels.

Original User Title: "$originalUserTitle"
AI-Generated Title: "$aiGeneratedTitle"

Current Description:
"$description"

Return ONLY the improved description:
''';

    try {
      final response = await _callGroqAPI(prompt);
      return _cleanAIResponse(response);
    } catch (e) {
      throw Exception('Failed to optimize description: $e');
    }
  }

  /// Generate description automatically from original user title and AI-generated title
  Future<String> generateDescription(
    String originalUserTitle,
    String aiGeneratedTitle,
  ) async {
    if (originalUserTitle.trim().isEmpty && aiGeneratedTitle.trim().isEmpty) {
      return '';
    }

    final prompt =
        '''
You generate short Google Calendar event descriptions.

Goal: Create a natural, simple, human-sounding description based strictly on the titles.

Rules:
- 1–2 short sentences (maximum 3).
- Match the exact meaning of the titles.
- Do NOT invent new details (no time, date, platform, people, or location unless provided).
- Keep it friendly and clear.

Meeting/Call Word Rule:
- Only use words like "meeting", "call", "session", or "discussion" if they already exist in the titles.

Hard Rule:
- If unsure about context, return a minimal neutral description that reflects only the given words.
- Output ONLY the description text. No quotes. No labels.

Original User Title: "$originalUserTitle"
AI-Generated Title: "$aiGeneratedTitle"

Return ONLY the description:
''';

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
