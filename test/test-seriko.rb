require "ninix/config"
require "ninix/seriko"

module NinixTest

  class SerikoTest

    # find ~/.ninix -name 'surface*a.txt' | xargs ruby seriko.rb
    def initialize(list_path)
#      if len(sys.argv) == 1
#        print('Usage:', sys.argv[0], '[surface??a.txt ...]')
#      end
      for filename in list_path
        print('Reading', filename, '...', "\n")
        for actor in Seriko.get_actors(NConfig.create_from_file(filename))
          print('#', actor.get_id().to_i.to_s, "\n")
          #print(actor.__class__.__name__,)
          print('(', actor.get_interval(), ')', "\n")
          print('number of patterns = ', actor.get_patterns().length, "\n")
          for pattern in actor.get_patterns()
            print('surface=', pattern[0], ', interval=', pattern[1].to_i.to_s, ', method=', pattern[2], ', args=', pattern[3], "\n")
          end
        end
        for actor in Seriko.get_mayuna(NConfig.create_from_file(filename))
          print('#', actor.get_id().to_i.to_s, "\n")
          #print(actor.__class__.__name__,)
          print('(', actor.get_interval(), ')', "\n")
          print('number of patterns =', actor.get_patterns().length, "\n")
          for pattern in actor.get_patterns()
            print('surface=', pattern[0], ', interval=', pattern[1].to_i.to_s, ', method=', pattern[2], ', args=', pattern[3], "\n")
          end
        end
      end
    end
  end
end

NinixTest::SerikoTest.new(ARGV)
