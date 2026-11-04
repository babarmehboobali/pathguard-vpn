String flagEmoji(String countryCode) {
  if (countryCode.length != 2 || countryCode.toLowerCase() == 'any') {
    return '🌐';
  }
  final code = countryCode.toUpperCase();
  return String.fromCharCodes([
    code.codeUnitAt(0) + 127397,
    code.codeUnitAt(1) + 127397,
  ]);
}
