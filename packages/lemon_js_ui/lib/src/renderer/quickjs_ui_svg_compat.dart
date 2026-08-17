// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

final RegExp _alphaMaskPattern = RegExp(
  r'<mask\b[^>]*(?:mask-type\s*:\s*alpha|mask-type\s*=\s*["\x27]alpha["\x27])[^>]*>[\s\S]*?</mask>',
  caseSensitive: false,
);

final RegExp _blackFillPattern = RegExp(
  r'fill\s*=\s*(["\x27])(?:black|#000(?:000)?)\1',
  caseSensitive: false,
);

/// Normalizes SVG alpha masks for vector_graphics, which currently treats
/// mask colors as luminance even when the SVG declares `mask-type:alpha`.
///
/// In an alpha mask black and white with the same opacity are equivalent. The
/// rewrite is intentionally limited to black fills inside declared alpha masks
/// so ordinary visible black artwork is never changed.
String normalizeJsUiSvg(String source) {
  return source.replaceAllMapped(_alphaMaskPattern, (match) {
    return match.group(0)!.replaceAllMapped(_blackFillPattern, (fill) {
      return 'fill=${fill.group(1)}white${fill.group(1)}';
    });
  });
}

final class JsUiSvgStringLoader extends SvgStringLoader {
  const JsUiSvgStringLoader(super.svg);

  @override
  String provideSvg(void message) =>
      normalizeJsUiSvg(super.provideSvg(message));
}

final class JsUiSvgAssetLoader extends SvgAssetLoader {
  const JsUiSvgAssetLoader(super.assetName);

  @override
  String provideSvg(ByteData? message) =>
      normalizeJsUiSvg(super.provideSvg(message));
}

final class JsUiSvgNetworkLoader extends SvgNetworkLoader {
  const JsUiSvgNetworkLoader(super.url, {super.headers});

  @override
  String provideSvg(Uint8List? message) =>
      normalizeJsUiSvg(super.provideSvg(message));
}
