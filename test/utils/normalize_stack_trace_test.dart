import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inspector_kit/src/utils/log_formatters.dart';

void main() {
  group('normalizeStackTrace', () {
    test('collapses framework internals but keeps boundaries', () {
      final stackTrace = '''
#0      MyWidget.build (package:my_app/main.dart:10:12)
#1      StatelessElement.build (package:flutter/src/widgets/framework.dart:4701:27)
#2      ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:4630:15)
#3      Element.rebuild (package:flutter/src/widgets/framework.dart:4343:5)
#4      BuildOwner.buildScope (package:flutter/src/widgets/framework.dart:2536:19)
#5      WidgetsBinding.drawFrame (package:flutter/src/widgets/binding.dart:883:20)
#6      RendererBinding._handlePersistentFrameCallback (package:flutter/src/rendering/binding.dart:363:5)
#7      SchedulerBinding._invokeFrameCallback (package:flutter/src/scheduler/binding.dart:1145:15)
<asynchronous suspension>
#8      App.main (package:my_app/main.dart:5:2)
''';

      final result = normalizeStackTrace(stackTrace);

      expect(result, contains('MyWidget.build'));
      expect(result, contains('StatelessElement.build'));
      expect(result, contains('[... 5 frames of framework internals]'));
      expect(result, contains('SchedulerBinding._invokeFrameCallback'));
      expect(result, contains('<-- async gap -->'));
      expect(result, contains('App.main'));
    });

    test('does not collapse when there are 2 or less framework internals', () {
      final stackTrace = '''
#0      MyWidget.build (package:my_app/main.dart:10:12)
#1      StatelessElement.build (package:flutter/src/widgets/framework.dart:4701:27)
#2      ComponentElement.performRebuild (package:flutter/src/widgets/framework.dart:4630:15)
#3      App.main (package:my_app/main.dart:5:2)
''';

      final result = normalizeStackTrace(stackTrace);

      expect(result, contains('MyWidget.build'));
      expect(result, contains('StatelessElement.build'));
      expect(result, contains('ComponentElement.performRebuild'));
      expect(result, isNot(contains('[...')));
      expect(result, contains('App.main'));
    });
  });
}
