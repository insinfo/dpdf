import 'alphabet_numbering.dart';

class GreekAlphabetNumbering {
  static const int ALPHABET_LENGTH = 24;
  static final List<String> ALPHABET_LOWERCASE =
      List.generate(ALPHABET_LENGTH, (i) {
    int code = 945 + i + (i > 16 ? 1 : 0);
    return String.fromCharCode(code);
  });
  static final List<String> ALPHABET_UPPERCASE =
      List.generate(ALPHABET_LENGTH, (i) {
    int code = 913 + i + (i > 16 ? 1 : 0);
    return String.fromCharCode(code);
  });

  static String toGreekAlphabetNumberLowerCase(int number) {
    return AlphabetNumbering.toAlphabetNumber(number, ALPHABET_LOWERCASE);
  }

  static String toGreekAlphabetNumberUpperCase(int number) {
    return AlphabetNumbering.toAlphabetNumber(number, ALPHABET_UPPERCASE);
  }

  static String toGreekAlphabetNumber(int number, bool upperCase,
      [bool symbolFont = false]) {
    String result = upperCase
        ? toGreekAlphabetNumberUpperCase(number)
        : toGreekAlphabetNumberLowerCase(number);
    if (symbolFont) {
      StringBuffer symbolFontStr = StringBuffer();
      for (int i = 0; i < result.length; i++) {
        symbolFontStr.write(_getSymbolFontChar(result[i]));
      }
      return symbolFontStr.toString();
    } else {
      return result;
    }
  }

  static String _getSymbolFontChar(String unicodeCharStr) {
    int code = unicodeCharStr.codeUnitAt(0);
    switch (code) {
      case 913:
        return 'A'; // ALFA
      case 914:
        return 'B'; // BETA
      case 915:
        return 'G'; // GAMMA
      case 916:
        return 'D'; // DELTA
      case 917:
        return 'E'; // EPSILON
      case 918:
        return 'Z'; // ZETA
      case 919:
        return 'H'; // ETA
      case 920:
        return 'Q'; // THETA
      case 921:
        return 'I'; // IOTA
      case 922:
        return 'K'; // KAPPA
      case 923:
        return 'L'; // LAMBDA
      case 924:
        return 'M'; // MU
      case 925:
        return 'N'; // NU
      case 926:
        return 'X'; // XI
      case 927:
        return 'O'; // OMICRON
      case 928:
        return 'P'; // PI
      case 929:
        return 'R'; // RHO
      case 931:
        return 'S'; // SIGMA
      case 932:
        return 'T'; // TAU
      case 933:
        return 'U'; // UPSILON
      case 934:
        return 'F'; // PHI
      case 935:
        return 'C'; // CHI
      case 936:
        return 'Y'; // PSI
      case 937:
        return 'W'; // OMEGA

      case 945:
        return 'a'; // alfa
      case 946:
        return 'b'; // beta
      case 947:
        return 'g'; // gamma
      case 948:
        return 'd'; // delta
      case 949:
        return 'e'; // epsilon
      case 950:
        return 'z'; // zeta
      case 951:
        return 'h'; // eta
      case 952:
        return 'q'; // theta
      case 953:
        return 'i'; // iota
      case 954:
        return 'k'; // kappa
      case 955:
        return 'l'; // lambda
      case 956:
        return 'm'; // mu
      case 957:
        return 'n'; // nu
      case 958:
        return 'x'; // xi
      case 959:
        return 'o'; // omicron
      case 960:
        return 'p'; // pi
      case 961:
        return 'r'; // rho
      case 962:
        return 'V'; // sigma
      case 963:
        return 's'; // sigma
      case 964:
        return 't'; // tau
      case 965:
        return 'u'; // upsilon
      case 966:
        return 'f'; // phi
      case 967:
        return 'c'; // chi
      case 968:
        return 'y'; // psi
      case 969:
        return 'w'; // omega
      default:
        return ' ';
    }
  }
}
