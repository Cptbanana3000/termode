/// Path translation utility for translating Windows paths to Git Bash/POSIX paths.
String translateToPosixPath(String path) {
  if (path.isEmpty) return path;

  // 1. Normalize backslashes to forward slashes
  var result = path.replaceAll('\\', '/');

  // 2. Handle drive letters (e.g., C:/path -> /c/path, D:/path -> /d/path)
  final driveRegex = RegExp(r'^([a-zA-Z]):/');
  final match = driveRegex.firstMatch(result);
  if (match != null) {
    final drive = match.group(1)!.toLowerCase();
    result = '/$drive/${result.substring(3)}';
  }

  // 3. Handle drive letters without trailing slash (e.g. C: -> /c)
  final driveBareRegex = RegExp(r'^([a-zA-Z]):$');
  final matchBare = driveBareRegex.firstMatch(result);
  if (matchBare != null) {
    final drive = matchBare.group(1)!.toLowerCase();
    result = '/$drive';
  }

  // 4. Quote paths safely if they contain spaces
  if (result.contains(' ')) {
    if (!((result.startsWith("'") && result.endsWith("'")) ||
          (result.startsWith('"') && result.endsWith('"')))) {
      result = "'$result'";
    }
  }

  return result;
}
