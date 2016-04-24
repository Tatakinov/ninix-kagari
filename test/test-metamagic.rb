require_relative "../lib/ninix/metamagic.rb"

module NinixTest

  class TEST_Meme < MetaMagic::Meme

    def create_menuitem(data)
      return data => 'menu'
    end
  end

  class DummyGhost

    def new_(*data)
      print "NEW: ", data.to_s, "\n"
    end
  end

  class TEST_Holon < MetaMagic::Holon

    def create_menuitem(data)
      return data => 'menu'
    end

    def create_instance(data)
      return DummyGhost.new
    end
  end

  class MetaMagicTest

    def initialize
      meme = TEST_Meme.new('meta')
      meme.baseinfo = 'base'
      meme.key = ''
      meme.menuitem = ''
      print("Meme: \n")
      print("  KEY: ")
      print(meme.key)
      print("\n")
      print("  BASE INFO: ")
      print(meme.baseinfo)
      print("\n")
      print("  MENU ITEM: ")
      print(meme.menuitem)
      print("\n")

      holon = TEST_Holon.new('magic')
      holon.baseinfo = 'base'
      holon.key = ''
      holon.menuitem = ''
      holon.instance = ''
      print("HOLON: \n")
      print("  KEY: ")
      print(holon.key)
      print("\n")
      print("  BASE INFO: ")
      print(holon.baseinfo)
      print("(should be nil)\n")
      print("  MENU ITEM: ")
      print(holon.menuitem)
      print("\n")
      print("  INSTANCE: ")
      print(holon.instance)
      print("\n")
    end
  end
end

NinixTest::MetaMagicTest.new
