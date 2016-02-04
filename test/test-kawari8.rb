# coding: utf-8
require "fiddle/import"

module Test
  extend Fiddle::Importer
  dlload "libshiori.so" #"_kawari8.so"
  extern "int so_library_init()"
  extern "int so_library_cleanup()"
  extern "unsigned int so_create(const char *, long)"
  extern "int so_dispose(unsigned int)"
  extern "const char *so_request(unsigned int, const char *, long *)"
  extern "void so_free(unsigned int, const char *)"
end

Test.so_library_init()

path = ARGV[0].to_s.encode("Shift_JIS")
#print path, "\n"
handle = Test.so_create(path, path.bytesize)
test_text = "NOTIFY SHIORI/3.0\r\nCharset: Shift_JIS\r\nID: TEST                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           日本語\r\n\r\n".encode("Shift_JIS")
test_len = [test_text.bytesize].pack("l!")
result = Test.so_request(handle, test_text, test_len)
test_len, = test_len.unpack("l!")
#print result.methods.sort, "\n"
print result[0, test_len].to_s.force_encoding("Shift_JIS").encode("UTF-8")
Test.so_free(handle, result)

Test.so_dispose(handle)
Test.so_library_cleanup()
