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
Test.load(path, path.length)
test_text = "NOTIFY SHIORI/3.0\r\nID: TEST\r\n\r\n".encode("Shift_JIS")
test_len = test_text.length.to_s
result = Test.request(test_text, test_len)
print result.to_s.force_encoding("Shift_JIS").encode("UTF-8")
Test.unload()
