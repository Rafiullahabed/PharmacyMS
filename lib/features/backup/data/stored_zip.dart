import 'dart:convert';
import 'dart:typed_data';
import '../domain/backup.dart';

/// Format v1 deliberately uses only ZIP STORE: bounded parsing, no decompression
/// or extraction, and exactly two regular files. See docs/BACKUP_FORMAT.md.
class StoredZip {
  static const names = ['manifest.json', 'data.json'];
  static final _crcTable = List<int>.generate(256, (i) {
    var c = i;
    for (var bit = 0; bit < 8; bit++) {
      c = (c >>> 1) ^ ((c & 1) == 1 ? 0xedb88320 : 0);
    }
    return c;
  });
  static int crc32(List<int> bytes) {
    var crc = 0xffffffff;
    for (final byte in bytes) {
      crc = (crc >>> 8) ^ _crcTable[(crc ^ byte) & 255];
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
  }

  static Uint8List encode(Map<String, Uint8List> files) {
    final output = BytesBuilder(copy: false),
        directory = BytesBuilder(copy: false);
    var offset = 0;
    for (final name in names) {
      final data = files[name]!, label = utf8.encode(name), crc = crc32(data);
      final local = ByteData(30);
      void l16(int p, int n) => local.setUint16(p, n, Endian.little);
      void l32(int p, int n) => local.setUint32(p, n, Endian.little);
      l32(0, 0x04034b50);
      l16(4, 20);
      l16(6, 0x800);
      l16(12, 33);
      l32(14, crc);
      l32(18, data.length);
      l32(22, data.length);
      l16(26, label.length);
      output.add(local.buffer.asUint8List());
      output.add(label);
      output.add(data);
      final central = ByteData(46);
      void c16(int p, int n) => central.setUint16(p, n, Endian.little);
      void c32(int p, int n) => central.setUint32(p, n, Endian.little);
      c32(0, 0x02014b50);
      c16(4, 20);
      c16(6, 20);
      c16(8, 0x800);
      c16(14, 33);
      c32(16, crc);
      c32(20, data.length);
      c32(24, data.length);
      c16(28, label.length);
      c32(42, offset);
      directory.add(central.buffer.asUint8List());
      directory.add(label);
      offset += 30 + label.length + data.length;
    }
    final size = directory.length;
    output.add(directory.takeBytes());
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(8, 2, Endian.little)
      ..setUint16(10, 2, Endian.little)
      ..setUint32(12, size, Endian.little)
      ..setUint32(16, offset, Endian.little);
    output.add(end.buffer.asUint8List());
    return output.takeBytes();
  }

  static Map<String, Uint8List> decode(Uint8List bytes) {
    if (bytes.length > maxBackupBytes) {
      throw const BackupException('This backup exceeds the 64 MiB file limit.');
    }
    const invalid = BackupException(
      'This is not a complete supported backup ZIP. Choose the original backup file.',
    );
    void require(bool ok) {
      if (!ok) throw invalid;
    }

    require(bytes.length >= 22);
    final b = ByteData.sublistView(bytes);
    int u16(int p) {
      require(p >= 0 && p + 2 <= bytes.length);
      return b.getUint16(p, Endian.little);
    }

    int u32(int p) {
      require(p >= 0 && p + 4 <= bytes.length);
      return b.getUint32(p, Endian.little);
    }

    final end = bytes.length - 22;
    require(
      u32(end) == 0x06054b50 &&
          u16(end + 4) == 0 &&
          u16(end + 6) == 0 &&
          u16(end + 8) == 2 &&
          u16(end + 10) == 2 &&
          u16(end + 20) == 0,
    );
    final directory = u32(end + 16), directorySize = u32(end + 12);
    require(directory + directorySize == end);
    var central = directory, local = 0;
    final result = <String, Uint8List>{};
    for (var i = 0; i < 2; i++) {
      require(central + 46 <= end && u32(central) == 0x02014b50);
      final flags = u16(central + 8),
          method = u16(central + 10),
          size = u32(central + 24),
          nameSize = u16(central + 28),
          extra = u16(central + 30),
          comment = u16(central + 32);
      if (method != 0) {
        throw const BackupException(
          'This backup uses unsupported compression. Select the original unmodified backup ZIP.',
        );
      }
      require(
        (flags == 0 || flags == 0x800) &&
            u16(central + 6) <= 20 &&
            u16(central + 34) == 0 &&
            extra == 0 &&
            comment == 0 &&
            u32(central + 20) == size &&
            u32(central + 42) == local &&
            central + 46 + nameSize <= end,
      );
      final attributes = u32(central + 38);
      final unixType = (attributes >>> 16) & 0xf000;
      require(
        (attributes & 0x10) == 0 && (unixType == 0 || unixType == 0x8000),
      );
      final name = utf8.decode(
        bytes.sublist(central + 46, central + 46 + nameSize),
      );
      require(names.contains(name) && !result.containsKey(name));
      require(size <= (name == 'manifest.json' ? 65536 : maxPayloadBytes));
      require(
        local + 30 <= directory &&
            u32(local) == 0x04034b50 &&
            u16(local + 4) <= 20 &&
            u16(local + 6) == flags &&
            u16(local + 8) == method &&
            u32(local + 14) == u32(central + 16) &&
            u32(local + 18) == size &&
            u32(local + 22) == size &&
            u16(local + 26) == nameSize &&
            u16(local + 28) == 0,
      );
      final start = local + 30 + nameSize, finish = start + size;
      require(
        finish <= directory &&
            utf8.decode(bytes.sublist(local + 30, start)) == name,
      );
      final data = Uint8List.sublistView(bytes, start, finish);
      require(crc32(data) == u32(central + 16));
      result[name] = data;
      local = finish;
      central += 46 + nameSize;
    }
    require(local == directory && central == end && result.length == 2);
    return result;
  }
}
