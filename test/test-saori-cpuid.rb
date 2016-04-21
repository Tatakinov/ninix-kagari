require_relative "../lib/ninix/dll/saori_cpuid"

module NinixTest

  class CpuidTest

    def initialize
      saori = Saori_cpuid::Saori.new
      saori.setup
      saori.request("") # XXX
      print(saori.execute(nil), "\n")
      print(saori.execute(["platform", 0]), "\n")
      print(saori.execute(["platform", 1]), "\n")
      print(saori.execute(["os.name", 1]), "\n")
      print(saori.execute(["os.version", 1]), "\n")
      print(saori.execute(["os.build", 1]), "\n")
      print(saori.execute(["cpu.num", 1]), "\n")
      saori.finalize
    end
  end
end

NinixTest::CpuidTest.new()
