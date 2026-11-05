import 'engine.dart';
import 'errors.dart';
import 'format.dart';

/// Picks an engine per format. Register in priority order: the first engine
/// that supports a format wins, so put the high-fidelity engine first and a
/// lighter fallback after it.
class OfficeEngineRegistry {
  OfficeEngineRegistry._();
  static final OfficeEngineRegistry instance = OfficeEngineRegistry._();

  final List<OfficeEngine> _engines = [];

  void register(OfficeEngine engine) => _engines.add(engine);
  void clear() => _engines.clear();

  OfficeEngine pick(OfficeFormat format) {
    for (final e in _engines) {
      if (e.supports(format)) return e;
    }
    if (_engines.isEmpty) {
      throw const EngineUnavailableError('No office engine registered.');
    }
    throw UnsupportedFormatError('No engine supports ${format.name}.');
  }
}
