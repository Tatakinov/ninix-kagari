# coding: utf-8
require "ninix/dll/ssu"

module NinixTest

  class SSUTest

    def initialize
      saori = SSU::Saori.new
      saori.setup
      saori.request("") # XXX
      print(saori.execute(nil, 'CP932'), "\n")
      #OK#print(saori.execute(['is_empty'], 'CP932'), "\n")
      #OK#print(saori.execute(['is_empty', "TEST"], 'CP932'), "\n")
      #OK#print(saori.execute(['is_empty', ""], 'CP932'), "\n")
      #OK#print(saori.execute(['is_digit', "0"], 'CP932'), "\n")
      #OK#print(saori.execute(['is_digit', "A"], 'CP932'), "\n")
      #OK#print(saori.execute(['is_alpha', "9A"], 'CP932'), "\n")
      #OK#print(saori.execute(['is_alpha', "A"], 'CP932'), "\n")
      #OK#print(saori.execute(['is_alpha', "asceSfq"], 'CP932'), "\n")
      #OK#print(saori.execute(['length', ""], 'CP932'), "\n")
      #OK#print(saori.execute(['length', "1sasa9"], 'CP932'), "\n")
      #OK#print(saori.execute(['substr', "testAAA", "２"], 'CP932'), "\n")
      #OK#print(saori.execute(['substr', "testAAA", "２", "４"], 'CP932'), "\n")
      #OK#print(saori.execute(['sprintf', "%2dtest%stest%.3f", "1", "23", "0.1"], 'CP932'), "\n") # sprintf
      #OK#print(saori.execute(['zen2han', "１"], 'CP932'), "\n")
      #OK#print(saori.execute(['zen2han', "＋"], 'CP932'), "\n")
      #OK#print(saori.execute(['han2zen', "1"], 'CP932').encode("UTF-8"), "\n")
      #OK#print(saori.execute(['han2zen', "-"], 'CP932').encode("UTF-8"), "\n")
      #OK#print(saori.execute(['if', "１ < ２", "A"], 'CP932'), "\n")
      #OK#print(saori.execute(['if', "１ >= ２", "B"], 'CP932'), "\n")
      #OK#print(saori.execute(['if', "１ == ２", "C", "D"], 'CP932'), "\n")
      #OK#print(saori.execute(['if', "１ != ２", "E", "F"], 'CP932'), "\n")
      #OK#print(saori.execute(['if', "１ ＜ ２", "G"], 'CP932'), "\n")
      #OK#print(saori.execute(['unless', "1 == 2", "H", "I"], 'CP932'), "\n")
      #OK#print(saori.execute(['iflist', "1", ">= ２", "L1", "== 2", "L2", " != ２", "L3", "＜ ２", "L4"], 'CP932'), "\n") # iflist
      #OK#print(saori.execute(['nswitch', "3", "S1", "S2", "S3", "S4"], 'CP932'), "\n")
      #OK#print(saori.execute(['count', "ABCDFEABRTRZAWABAB", "AB"], 'CP932'), "\n")
      #OK#print(saori.execute(['compare', "AVD", "ADV"], 'CP932'), "\n")
      #OK#print(saori.execute(['compare', "AAC", "AAC"], 'CP932'), "\n")
      #OK#print(saori.execute(['compare_head', "ABC", "A8CDEF"], 'CP932'), "\n")
      #OK#print(saori.execute(['compare_head', "ABC", "ABCDEF"], 'CP932'), "\n")
      #OK#print(saori.execute(['compare_tail', "ABC", "ABCDEF"], 'CP932'), "\n")
      #OK#print(saori.execute(['compare_tail', "ABC", "DEFABC"], 'CP932'), "\n")
      #OK#print(saori.execute(['erase', "DFABEACAB", "AB"], 'CP932'), "\n")
      #OK#print(saori.execute(['erase', "ADEGARCAH", "AB"], 'CP932'), "\n")
      #OK#print(saori.execute(['erase_first', "DFABEACAB", "AB"], 'CP932'), "\n")
      #OK#print(saori.execute(['erase_first', "ADEGARCAH", "AB"], 'CP932'), "\n")
      #OK#print(saori.execute(['replace', "DFABEACAB", "AB", "XT"], 'CP932'), "\n")
      #OK#print(saori.execute(['replace', "ADEGARCAH", "AB", "XT"], 'CP932'), "\n")
      #OK#print(saori.execute(['replace_first', "DFABEACAB", "AB", "XT"], 'CP932'), "\n")
      #OK#print(saori.execute(['replace_first', "ADEGARCAH", "AB", "XT"], 'CP932'), "\n")
      #OK#print(saori.execute(['split', "DFABEACAB", "AB"], 'CP932'), "\n")
      #OK#print(saori.execute(['split', "DFABEACABX", "AB"], 'CP932'), "\n")
      #OK#print(saori.execute(['split', "DFABEACABX", "AB", "1"], 'CP932'), "\n")
      #OK#print(saori.execute(['switch', "3", "1", "S1", "2", "S2", "3", "S3", "4", "S4"], 'CP932'), "\n")
      # Not implemented yet
      #print(saori.execute(['', ""], 'CP932'), "\n") # kata2hira
      #print(saori.execute(['', ""], 'CP932'), "\n") # hira2kata
      #print(saori.execute(['', ""], 'CP932'), "\n") # calc
      #print(saori.execute(['', ""], 'CP932'), "\n") # calc_float
      saori.finalize
    end
  end
end

NinixTest::SSUTest.new()
