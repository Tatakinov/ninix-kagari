require_relative 'lib/ninix/version'

Gem::Specification.new do |spec|
  spec.name        = 'ninix-kagari'
  spec.version     = Version.NUMBER
  #spec.date        = ''
  spec.summary     = "Interactive fake-AI Ukagaka-compatible desktop mascot program"
  spec.description = <<-EOF
 "Ukagaka", also known as "Nanika", is a platform on which provides mascot
 characters for the user's desktop. "Ninix" is an Ukagaka-compatible
 program, but stop developing for a long time. "Ninix-aya" is derived
 from "Ninix" and improved a lot.
EOF
  spec.authors     = ["Tamito KAJIYAMA",
                   "MATSUMURA Namihiko",
                   "Shyouzou Sugitani",
                   "Shun-ichi TAHARA",
                   "ABE Hideaki",
                   "linjian",
                   "henryhu",
                   "Tatakinov"]
  spec.email       = 'tatakinov@gmail.com'
  spec.files       = Dir["lib/*.rb"]
  spec.files       += Dir['lib/ninix/*.rb']
  spec.files       += Dir['lib/ninix/dll/*.rb']
  spec.files       += Dir['locale/*/LC_MESSAGES/*.mo']
  spec.files       += %w(COPYING ChangeLog.ninix-aya README.md README.ninix-aya README.ninix-aya.en README.ninix SAORI)
  spec.bindir      = "exe"
  spec.executables << 'ninix-kagari'
  spec.homepage    = 'https://github.com/Tatakinov/ninix-kagari'
  spec.license     = 'GPL-2.0'
  spec.add_runtime_dependency 'narray', '~> 0.6', '>=0.6.1.1'
  spec.add_runtime_dependency 'gtk3', '~> 3.1', '>=3.1.0'
  #spec.add_runtime_dependency 'gstreamer', '~> 3.1', '>=3.1.0'
  spec.add_runtime_dependency 'gettext', '~> 3.2', '>=3.2.2'
  spec.add_runtime_dependency 'rubyzip', '~> 1.2', '>=1.2.0'
  #spec.add_runtime_dependency 'charlock_holmes', '~> 0.7', '>=0.7.3'
  #spec.executables << 'ninix-kagari'
  spec.required_ruby_version = '~> 2.0'
  #spec.requirements << 'Ghosts and Balloon'
end
