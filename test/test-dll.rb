require_relative "../lib/ninix/dll"

module NinixTest

  class DLLTest

    def initialize()
      shiori_lib = DLL::Library.new('shiori')
      instance = shiori_lib.request(['AYA', 'aya.dll'])
      print(instance, "\n")
      instance = shiori_lib.request(['Kawari', 'kawari.dll'])
      print(instance, "\n")
      saori_lib = DLL::Library.new('saori')
      instance = saori_lib.request('Hanayu')
      print(instance, "\n")
      instance = saori_lib.request('bln')
      print(instance, "\n")
      if instance
        result = instance.request("GET Version\nCharset : UTF-8\nArgument: arg1\nArgument : arg2")
        print(result, "\n")
        result = instance.request("EXECUTE\nCharset : CP932\nArgument: arg1\nArgument : arg2")
        print(result, "\n")
      end
    end
  end
end

NinixTest::DLLTest.new()
