require "ninix/install"

module NinixTest

  class InstallTest

    def initialize
      installer = Install::Installer.new()
      archive = File.expand_path("~/ukagaka/Ghost/Anko/Anko_re.nar")
      #archive = "http://altenotiz.sakura.ne.jp/ghost/exice_z102.zip"
      installer.install(archive, File.expand_path("~/TEST"))
    end
  end
end

NinixTest::InstallTest.new
