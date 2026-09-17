import 'package:hotkeypad_host/src/steam_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseLibraryFolderPaths', () {
    test('extracts every library path, unescaping doubled backslashes', () {
      const vdf = r'''
"libraryfolders"
{
	"0"
	{
		"path"		"D:\\Steam"
		"label"		""
		"contentid"		"5138037834324674691"
		"apps"
		{
			"1245620"		"55123337185"
		}
	}
	"1"
	{
		"path"		"E:\\SteamLibrary"
		"apps"
		{
		}
	}
}
''';

      expect(parseLibraryFolderPaths(vdf), [r'D:\Steam', r'E:\SteamLibrary']);
    });

    test('returns nothing for text with no path key', () {
      expect(parseLibraryFolderPaths('"libraryfolders"\n{\n}\n'), isEmpty);
    });
  });

  group('parseAppManifest', () {
    test('reads appid and name out of a real manifest', () {
      const acf = r'''
"AppState"
{
	"appid"		"1245620"
	"universe"		"1"
	"LauncherPath"		"D:\\Steam\\steam.exe"
	"name"		"ELDEN RING"
	"StateFlags"		"4"
	"installdir"		"ELDEN RING"
}
''';

      final result = parseAppManifest(acf);

      expect(result?.appId, '1245620');
      expect(result?.name, 'ELDEN RING');
    });

    test('returns null when appid is missing', () {
      const acf = '"AppState"\n{\n\t"name"\t\t"Missing Id"\n}\n';
      expect(parseAppManifest(acf), isNull);
    });

    test('returns null when name is missing', () {
      const acf = '"AppState"\n{\n\t"appid"\t\t"123"\n}\n';
      expect(parseAppManifest(acf), isNull);
    });

    test('returns null for an empty name', () {
      const acf = '"AppState"\n{\n\t"appid"\t\t"123"\n\t"name"\t\t""\n}\n';
      expect(parseAppManifest(acf), isNull);
    });
  });
}
