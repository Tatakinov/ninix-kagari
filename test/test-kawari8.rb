# coding: utf-8
require "fiddle/import"

module Test
  extend Fiddle::Importer
  dlload "/usr/lib/games/ninix-aya/_kawari8.so"
  extern "int load(const char *, long)"
  extern "char *request(const char *, long *)"
  extern "int unload()"
end

path = ARGV[0].to_s.encode("Shift_JIS")
#print path, "\n"
Test.load(path, path.bytesize)
test_text = "NOTIFY SHIORI/3.0\r\nCharset: Shift_JIS\r\nID: TEST                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           日本語\r\n\r\n".encode("Shift_JIS")
test_len = [test_text.bytesize].pack("q")
result = Test.request(test_text, test_len)
print result.to_s.force_encoding("Shift_JIS").encode("UTF-8")
Test.unload()
