import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/session.dart';
import 'venue_code.dart';
import 'venue_page.dart';

/// Opens venue links (`trace://v/CODE`, `https://…/v/CODE`) from QR codes, NFC tags and the web (spec F-16).
/// A link that arrives before sign-in waits until the user is in.
class LinkHandler extends StatefulWidget {
  const LinkHandler({super.key, required this.navigator, required this.child});

  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  @override
  State<LinkHandler> createState() => _LinkHandlerState();
}

class _LinkHandlerState extends State<LinkHandler> {
  StreamSubscription<Uri>? _sub;
  String? _pending;
  late final Session _session = context.read<Session>();

  @override
  void initState() {
    super.initState();
    // The stream also delivers the link that launched the app.
    _sub = AppLinks().uriLinkStream.listen((uri) {
      final code = venueCodeFrom(uri.toString());
      if (code == null) return;
      _pending = code;
      _flush();
    }, onError: (_) {});
    _session.addListener(_flush);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _session.removeListener(_flush);
    super.dispose();
  }

  void _flush() {
    final code = _pending;
    final nav = widget.navigator.currentState;
    if (code == null || nav == null || _session.stage != SessionStage.ready) return;
    _pending = null;
    nav.push(MaterialPageRoute(builder: (_) => VenuePage(code: code)));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
