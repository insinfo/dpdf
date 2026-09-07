class PdfNameUtil {
  static String decodeName(List<int> content) {
    StringBuffer buf = StringBuffer();
    try {
      for (int k = 0; k < content.length; ++k) {
        int c = content[k];
        if (c == 35) {
          // '#'
          int c1 = content[k + 1];
          int c2 = content[k + 2];
          c = (getHex(c1) << 4) + getHex(c2);
          k += 2;
        }
        buf.writeCharCode(c);
      }
    } catch (e) {
      // Index out of range
    }
    return buf.toString();
  }

  static int getHex(int v) {
    if (v >= 48 && v <= 57) return v - 48; // '0'-'9'
    if (v >= 65 && v <= 70) return v - 65 + 10; // 'A'-'F'
    if (v >= 97 && v <= 102) return v - 97 + 10; // 'a'-'f'
    return 0;
  }
}
