# coding: utf-8
require "fiddle/import"

module Test
  extend Fiddle::Importer
  dlload "libshiori.so" #"_kawari8.so"
  extern "int load(const char *, long)"
  extern "char *request(const char *, long *)"
  extern "int unload()"
end

path = ARGV[0].to_s.encode("Shift_JIS")
#print path, "\n"
path_ptr = Fiddle::Pointer.malloc(
  path.bytesize + 1,
  freefunc=nil # Kawari8 will free this pointer
)
Test.load(path_ptr, path.bytesize)
test_text = "NOTIFY SHIORI/3.0\r\nCharset: Shift_JIS\r\nID: TEST                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           日本語\r\n\r\n".encode("Shift_JIS")
test_len = [test_text.bytesize].pack("l!")
test_ptr = Fiddle::Pointer.malloc(
  test_text.bytesize + 1,
  freefunc=nil # Kawari8 will free this pointer
)
test_ptr[0, test_text.bytesize] = test_text
result = Test.request(test_ptr, test_len)
test_len, = test_len.unpack("l!")
#print result.methods.sort, "\n"
print result[0, test_len].to_s.force_encoding("Shift_JIS").encode("UTF-8")
Test.unload()
