import 'package:flutter/material.dart';

class CustomTextHeading extends StatelessWidget {
  const CustomTextHeading(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => _CustomText(
    text: text,
    style: const TextStyle(
      fontFamily: 'GoogleSans',
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: Color(0xFFF4F4F5),
    ).merge(style),
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel,
  );
}

class CustomTextDescription extends StatelessWidget {
  const CustomTextDescription(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => _CustomText(
    text: text,
    style: const TextStyle(
      fontFamily: 'GoogleSans',
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: Color(0xFFD4D4D8),
      height: 1.45,
    ).merge(style),
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel,
  );
}

class CustomTextBody extends StatelessWidget {
  const CustomTextBody(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => _CustomText(
    text: text,
    style: const TextStyle(
      fontFamily: 'GoogleSans',
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: Color(0xFFF4F4F5),
      height: 1.4,
    ).merge(style),
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel,
  );
}

class CustomTextMuted extends StatelessWidget {
  const CustomTextMuted(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => _CustomText(
    text: text,
    style: const TextStyle(
      fontFamily: 'GoogleSans',
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: Color(0xFFA1A1AA),
      height: 1.35,
    ).merge(style),
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel,
  );
}

class _CustomText extends StatelessWidget {
  const _CustomText({
    required this.text,
    required this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
    semanticsLabel: semanticsLabel,
  );
}
