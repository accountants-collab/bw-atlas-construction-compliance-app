import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../storage/data/company_file_providers.dart';
import 'disclaimer_repository.dart';

final disclaimerRepositoryProvider = Provider<DisclaimerRepository>((ref) {
  return DisclaimerRepository(
    fileRepository: ref.read(companyFileRepositoryProvider),
  );
});