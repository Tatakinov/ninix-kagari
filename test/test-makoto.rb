require_relative "../lib/ninix/makoto"

module NinixTest

  class MakotoTest

    def initialize
      print("testing...\n")
      for i in 0...1000
        do_test()
      end
      do_test(:verbose => 1)
    end

    def do_test(verbose: 0)
      for test, expected in [['a(1)b', ['a1b']],
                             ['a(1|2)b', ['a1b', 'a2b']],
                             ['a(1)2b', ['ab', 'a1b', 'a11b']],
                             ['a(1|2)1b', ['ab', 'a1b', 'a2b']],
                             ['(1|2)(a|b)', ['1a', '1b', '2a', '2b']],
                             ['((1|2)|(a|b))', ['1', '2', 'a', 'b']],
                             ['()', ['']],
                             ['()2', ['']],
                             ['a()b', ['ab']],
                             ['a()2b', ['ab']],
                             ['a\(1\|2\)b', ['a(1|2)b']],
                             ['\((1|2)\)', ['(1)', '(2)']],
                             ['\(1)', ['(1)']],
                             ['a|b', ['a|b']],
                             # errornous cases
                             ['(1', ['(1']],
                             ['(1\)', ['(1\)']],
                             ['(1|2', ['(1|2']],
                             ['(1|2\)', ['(1|2\)']],
                             ['(1|2)(a|b', ['1(a|b', '2(a|b']],
                             ['((1|2)|(a|b)', ['((1|2)|(a|b)']],
                            ]
        result = Makoto.execute(test)
        print("'", test.to_s, "'", ' => ', "'", result.to_s, "'", ' ... ',) unless verbose.zero?
        begin
          if expected.nil?
            fail "assert" unless result == test
          else
            fail "assert" unless expected.include?(result)
          end
          print("OK\n") unless verbose.zero?
        rescue #AssertionError
          print("NG\n") unless verbose.zero?
          raise
        end
      end
    end
  end
end

NinixTest::MakotoTest.new
