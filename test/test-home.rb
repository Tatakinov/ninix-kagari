require "ninix/home"

module NinixTest

  class HomeTest

    def initialize(path)
      re_alias = Regexp.new('^(sakura|kero|char[0-9]+)\.surface\.alias$') # XXX
      config = Home.load_config()
      if config == nil
        raise SystemExit('Home directory not found.\n')
      end
      ghosts, balloons, nekoninni, katochan, kinoko = config
      ghosts = Home.search_ghosts(target=nil, check_shiori=false) # over write
      # ghosts
      for key in ghosts.keys
        desc, shiori_dir, use_makoto, surface_set, prefix, shiori_dll, shiori_name = ghosts[key]
        print('GHOST ', '=' * 50, "\n")
        print("'", prefix, "'", "\n")
        for k, v in desc.each_entry
          print(k, ',', v, "\n")
        end
        print("\n")
        print("'", shiori_dir, "'", "\n")
        print(shiori_dll, "\n")
        print(shiori_name, "\n")
        print('use_makoto = ', use_makoto, "\n")
        if surface_set
          for name, surface_dir, desc, alias_, surface, tooltips in surface_set.values()
            print('-' * 50, "\n")
            print('surface: ', name, "\n")
            for k, v in desc.each_entry
              print(k, ',', v, "\n")
            end
            print("\n")
            for k, v in surface.each_entry
              print(k, ' = ', "'", v[0], "'", "\n")
              if not v[1].empty?
                for k1, v1 in v[1].each_entry
                  print(k1, ',', v1, "\n")
                end
              end
              print("\n")
            end
            if alias_
              buf = []
              for k, v in alias_.each_entry
                match = re_alias.match(k)
                if match
                  print([k, ':'].join(''), "\n")
                  for alias_id, alias_list in v.each_entry
                    print(alias_id, \
                          [' = [', alias_list.join(', '), ']'].join(''), "\n")
                  end
                  print("\n")
                else
                  buf << [k, v]
                end
              end
              if not buf.empty?
                print('filename alias:', "\n")
                for k, v in buf
                  print(k, ' = ', v, "\n")
                end
                print("\n")
              end
            end
          end
        end
      end
      # balloons
      for key in balloons.keys
        desc, balloon = balloons[key]
        print('BALLOON ', '=' * 50, "\n")
        for k, v in desc.each_entry
          print(k, ',', v, "\n")
        end
        print("\n")
        for k, v in balloon.each_entry
          print(k, ' = ', v[0], "\n")
          if not v[1].empty?
            for k1, v1 in v[1].each_entry
              print(k1, ',', v1, "\n")
            end
          end
          print("\n")
        end
      end
      # nekoninni
      for nekoninni_name, nekoninni_dir in nekoninni
        print('NEKONINNI ', '=' * 50, "\n")
        print('name = ', nekoninni_name, "\n")
        print("'", nekoninni_dir, "'", "\n")
      end
      # katochan
      for katochan_item in katochan
        print('KATOCHAN ', '=' * 50, "\n")
        for k, v in katochan_item.each_entry
          print(k, ',', v, "\n")
        end
      end
      # kinoko
      for kinoko_item in kinoko
        print('KINOKO ', '=' * 50, "\n")
        for k, v in kinoko_item.each_entry
          print(k, ',', v, "\n")
        end
      end
    end
  end
end

$:.unshift(File.dirname(__FILE__))

NinixTest::HomeTest.new(ARGV.shift)
