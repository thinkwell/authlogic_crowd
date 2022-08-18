# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib",__FILE__)
require 'authlogic_crowd/version'

Gem::Specification.new do |s|
  s.name        = %q{authlogic_crowd}
  s.version     = AuthlogicCrowd::VERSION.dup
  s.authors     = ["Paul Strong"]
  s.email       = %q{paul@thestrongfamily.org}
  s.homepage    = %q{http://github.com/thinkwell/authlogic_crowd}
  s.summary     = %q{Atlassian Crowd support for Authlogic}
  s.description = %q{Atlassian Crowd support for Authlogic}

  s.rubyforge_project = "authlogic_crowd"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency(%q<authlogic>, ["~> 6.4"])
  s.add_runtime_dependency(%q<simple_crowd>, [">= 1.1.0"])
  s.add_runtime_dependency(%q<yolk-client>, [">= 0.14.0"])

  s.add_development_dependency(%q<bundler>, [">= 1.0.21"])
  s.add_development_dependency(%q<rake>, [">= 0"])
end
