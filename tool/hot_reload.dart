import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final base = args.isNotEmpty ? args.first : 'http://127.0.0.1:55358/OGMbLaJfQg4=/';
  final root = base.endsWith('/') ? base : '$base/';
  final vmRes = await HttpClient().getUrl(Uri.parse('${root}getVM'));
  final vmBody = jsonDecode(await (await vmRes.close()).transform(utf8.decoder).join()) as Map;
  final isolates = (vmBody['result'] as Map)['isolates'] as List;
  final main = isolates.cast<Map>().firstWhere(
        (i) => i['name'] == 'main',
        orElse: () => isolates.first as Map,
      );
  final iid = main['id'] as String;
  stdout.writeln('isolate $iid');

  final uri = Uri.parse(root);
  final wsUrl = '${uri.scheme == 'https' ? 'wss' : 'ws'}://${uri.authority}${uri.path}ws';
  final ws = await WebSocket.connect(wsUrl);
  var id = 0;
  Future<Map> call(String method, [Map? params]) async {
    final myId = ++id;
    ws.add(jsonEncode({'jsonrpc': '2.0', 'id': myId, 'method': method, 'params': params ?? {}}));
    await for (final raw in ws) {
      final msg = jsonDecode(raw as String) as Map;
      if (msg['id'] == myId) return msg;
    }
    throw StateError('no response');
  }

  final reload = await call('reloadSources', {'isolateId': iid, 'pause': false, 'force': true});
  stdout.writeln('reloadSources: ${const JsonEncoder.withIndent('  ').convert(reload)}');
  final success = ((reload['result'] as Map?)?['success'] as bool?) ?? false;
  if (success) {
    final reass = await call('ext.flutter.reassemble', {'isolateId': iid});
    stdout.writeln('reassemble: ${jsonEncode(reass)}');
  }
  await ws.close();
  exit(success ? 0 : 1);
}
