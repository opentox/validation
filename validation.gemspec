# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "opentox-validation"
  s.version     = File.read("./VERSION")
  s.authors     = ["Martin Gütlein"]
  s.email       = ["martin.guetlein@gmail.com"]
  s.homepage    = "http://github.com/OpenTox/validation"
  s.summary     = %q{opentox validation service}
  s.description = %q{opentox validation service}
  s.license     = 'GPL-3'
  #s.platform    = Gem::Platform::CURRENT

  s.rubyforge_project = "validation"

  s.files         = `git ls-files`.split("\n")
  #s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  #s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  #s.require_paths = ["lib"]
  s.required_ruby_version = '>= 1.9.2'

  # specify any dependencies here; for example:
  s.add_runtime_dependency "opentox-server"
  s.add_runtime_dependency "ohm", "=0.1.3"
  s.add_runtime_dependency "ohm-contrib", "=0.1.1"
  s.add_runtime_dependency "ruby-plot"
  s.add_runtime_dependency "rinruby"

  s.post_install_message = "Please configure your service in ~/.opentox/config/validation.rb"
end


