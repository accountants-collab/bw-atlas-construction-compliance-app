import '../../settings/domain/app_settings.dart';
import '../../surveys/domain/models.dart';

String buildReportFileName({
  required AppSettings settings,
  required Survey survey,
  required String reportType,
  required String extension,
}) {
  final company = settings.companyProfile.companyName.trim().isEmpty
      ? 'Company'
      : settings.companyProfile.companyName.trim();
    final report = survey.reportName.trim().isNotEmpty
      ? survey.reportName.trim()
      : (survey.reference.trim().isNotEmpty ? survey.reference.trim() : 'Project');
  final date = _dateTag(DateTime.now());

  var name = settings.reportBranding.pdfFileNameFormat;
  name = name.replaceAll('{company}', company);
  name = name.replaceAll('{type}', reportType);
  name = name.replaceAll('{report}', report);
  name = name.replaceAll('{date}', date);

  final safe = _safeName(name);
  final ext = extension.startsWith('.') ? extension : '.$extension';
  return '$safe$ext';
}

String previewReportFileNameFormat({
  required AppSettings settings,
  required String reportType,
  required String reportName,
  required String extension,
}) {
  final company = settings.companyProfile.companyName.trim().isEmpty
      ? 'Company'
      : settings.companyProfile.companyName.trim();
  final date = _dateTag(DateTime.now());

  var name = settings.reportBranding.pdfFileNameFormat;
  name = name.replaceAll('{company}', company);
  name = name.replaceAll('{type}', reportType);
  name = name.replaceAll('{report}', reportName);
  name = name.replaceAll('{date}', date);

  final safe = _safeName(name);
  final ext = extension.startsWith('.') ? extension : '.$extension';
  return '$safe$ext';
}

String _dateTag(DateTime d) {
  final y = d.year.toString();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y$m$day';
}

String _safeName(String input) {
  var s = input
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .trim();
  s = s.replaceAll(RegExp(r'[ .]+$'), '');
  if (s.isEmpty) return 'Report';
  if (s.length > 96) s = s.substring(0, 96);
  return s;
}
