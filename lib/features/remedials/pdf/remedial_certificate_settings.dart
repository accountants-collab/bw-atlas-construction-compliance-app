class RemedialCertificateSettings {
  final String companyDisplayName;
  final String approvedMaintainerName;
  final String approvedMaintainerNumber;
  final String rmaRegisterReference;
  final String defaultSignatureImage;
  final String declarationText;

  const RemedialCertificateSettings({
    required this.companyDisplayName,
    required this.approvedMaintainerName,
    required this.approvedMaintainerNumber,
    required this.rmaRegisterReference,
    required this.defaultSignatureImage,
    required this.declarationText,
  });
}

const defaultRemedialCertificateSettings = RemedialCertificateSettings(
  companyDisplayName: 'BW Atlas',
  approvedMaintainerName: '',
  approvedMaintainerNumber: '',
  rmaRegisterReference: 'RMA-058',
  defaultSignatureImage: 'assets/branding/default_signature.png',
  declarationText:
      'I certify that the remedial maintenance works described in this certificate have been completed in line with the recorded defects, photographic evidence, and the maintenance scope approved for this project. The maintained doorsets are fit for service subject to ongoing inspection and planned maintenance.',
);
