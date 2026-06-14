class ArtItem {
  final int code; // 1..24 (not all numbers used in your table, but we keep int)
  final String title;

  const ArtItem(this.code, this.title);

  String get codeLabel => code.toString().padLeft(2, '0'); // 01, 02...
  String get display => 'ART $codeLabel - $title';
}

const artCatalog = <ArtItem>[
  ArtItem(1, 'Lipping Repair'),
  ArtItem(2, 'Over Recessed Hardware'),
  ArtItem(3, 'Door Frame Joints'),
  ArtItem(4, 'Door Gaps Incorrect to Specification'),
  ArtItem(5, 'Closer Not Operating Correctly'),
  ArtItem(6, 'Door Leaf Out of Alignment'),
  ArtItem(7, 'Moisture Content Too High'),
  ArtItem(8, 'Hinges Dropped or Damaged'),
  ArtItem(10, 'Operational Maintenance'),
  ArtItem(11, 'Damaged Perimeter Seals'),
  ArtItem(12, 'Misaligned Matching Hardware'),
  ArtItem(13, 'Hinge Fixings Are Loose or missing'),
  ArtItem(14, 'Damaged Glazing and Glass'),
  ArtItem(16, 'Replacement or Refitting Architrave and Sealing'),
  ArtItem(17, 'Replacement Door Leaf'),
  ArtItem(18, 'Recommendation for Replacement Doorset'),
  ArtItem(19, 'Fire Door Signage'),
  ArtItem(20, 'Replacement Door Frame'),
  ArtItem(21, 'Repair Door Frame'),
  ArtItem(22, 'Smoke Control'),
  ArtItem(23, 'Calling In Expertise'),
  ArtItem(24, 'Ineffectual Fixings'),
];