/// Optional Qur'an/Sunnah-grounded opening ("prestarter") for a will, offered as
/// an editable default a user may keep or clear. Plain text only — no HTML, no
/// markup, no code. Grounded in Qur'an 2:180 (the waṣiyya is prescribed), 2:132
/// (Ibrāhīm & Yaʿqūb: "die not except as Muslims"), the shahāda, and the ḥadīth
/// that a Muslim should not let two nights pass without a written will
/// (Ṣaḥīḥ al-Bukhārī 2738 / Muslim 1627). Non-sectarian, mainstream wording.
library;

/// Placeholder the app leaves for the user (or substitutes with their name).
const willOpeningNamePlaceholderEn = '[Full name]';
const willOpeningNamePlaceholderAr = '[الاسم الكامل]';

const _openingArPrimary = '''
بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ
الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ، وَالصَّلَاةُ وَالسَّلَامُ عَلَىٰ رَسُولِهِ الْكَرِيمِ.
أَشْهَدُ أَنْ لَا إِلَٰهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، وَأَشْهَدُ أَنَّ مُحَمَّدًا عَبْدُهُ وَرَسُولُهُ.
هَٰذِهِ وَصِيَّةُ [الاسم الكامل]. أُوصِي نَفْسِي وَأَهْلِي بِتَقْوَىٰ اللَّهِ، وَأَنْ يَلْزَمُوا دِينَ الْإِسْلَامِ حَتَّىٰ يَلْقَوُا اللَّهَ، كَمَا وَصَّىٰ إِبْرَاهِيمُ وَيَعْقُوبُ بَنِيهِمَا: «يَا بَنِيَّ إِنَّ اللَّهَ اصْطَفَىٰ لَكُمُ الدِّينَ فَلَا تَمُوتُنَّ إِلَّا وَأَنْتُمْ مُسْلِمُونَ».
وَأَشْهَدُ أَنَّ الْمَوْتَ حَقٌّ، وَأَنَّ السَّاعَةَ آتِيَةٌ لَا رَيْبَ فِيهَا. وَقَدْ كَتَبْتُ وَصِيَّتِي هَٰذِهِ وَأَنَا فِي صِحَّةٍ مِنْ عَقْلِي وَكَامِلِ اخْتِيَارِي.''';

const _openingArShort = '''
بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ. الْحَمْدُ لِلَّهِ، وَالصَّلَاةُ وَالسَّلَامُ عَلَىٰ رَسُولِ اللَّهِ.
أَشْهَدُ أَنْ لَا إِلَٰهَ إِلَّا اللَّهُ وَأَنَّ مُحَمَّدًا رَسُولُ اللَّهِ.
هَٰذِهِ وَصِيَّةُ [الاسم الكامل]: أُوصِي أَهْلِي بِتَقْوَىٰ اللَّهِ وَأَلَّا يَمُوتُوا إِلَّا وَهُمْ مُسْلِمُونَ. كَتَبْتُهَا وَأَنَا فِي صِحَّةِ عَقْلِي وَاخْتِيَارِي.''';

const _openingEnPrimary = '''
In the name of Allah, the Most Gracious, the Most Merciful.
All praise is due to Allah, Lord of all the worlds, and may peace and blessings be upon His noble Messenger. I bear witness that there is no god but Allah alone, without partner, and that Muhammad is His servant and Messenger.
This is the will of [Full name]. I counsel myself and my family to be mindful of Allah and to hold fast to Islam until they meet Him, as Ibrahim and Ya'qub counseled their children: "O my children, Allah has chosen this faith for you, so do not die except as Muslims (in submission to Him)." (Qur'an 2:132)
I bear witness that death is true and that the Hour is coming, without doubt. I have written this, my will, while of sound mind and full free choice.''';

const _openingEnShort = '''
In the name of Allah, the Most Gracious, the Most Merciful. All praise is due to Allah, and peace and blessings upon His Messenger. I bear witness that there is no god but Allah and that Muhammad is His Messenger.
This is the will of [Full name]. I counsel my family to be mindful of Allah and to remain Muslims until death. I have written it while of sound mind and by my own free choice.''';

/// Returns the opening text for the requested language and length. If [name] is
/// provided it replaces the placeholder; otherwise the placeholder is kept for
/// the user to fill.
String willOpeningText({required bool arabic, bool short = false, String? name}) {
  final base = arabic
      ? (short ? _openingArShort : _openingArPrimary)
      : (short ? _openingEnShort : _openingEnPrimary);
  final text = base.trim();
  if (name == null || name.trim().isEmpty) return text;
  final n = sanitizePlainText(name).trim();
  return text
      .replaceAll(willOpeningNamePlaceholderEn, n)
      .replaceAll(willOpeningNamePlaceholderAr, n);
}

/// Strips anything code-like from free text so the will body stays plain text:
/// removes HTML/XML tags and angle-bracket fragments, control characters (keeping
/// newlines/tabs), and collapses runs of blank lines. The rendered UI never
/// interprets markup, but this guarantees nothing code-like is stored either.
String sanitizePlainText(String input) {
  var s = input;
  // Drop tag-like sequences: <script>, </p>, <img …>, and stray angle fragments.
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  s = s.replaceAll(RegExp(r'[<>]'), '');
  // Remove control chars except tab (\x09) and newline (\x0A).
  s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  // Collapse 3+ newlines into a paragraph break.
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s;
}
