import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'company_file_repository.dart';

final companyFileRepositoryProvider = Provider<CompanyFileRepository>((ref) {
  return CompanyFileRepository();
});
