$:.push File.expand_path("../lib",__FILE__)
require 'authlogic_crowd/version'

Gem::Specification.new do |s|
  s.name = %q{authlogic_crowd}
  s.version = AuthlogicCrowd::VERSION.dup
  s.platform = Gem::Platform::RUBY
  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Paul Strong"]
  s.description = %q{Authlogic Crowd}
  s.email = %q{paul@thestrongfamily.org}
  s.extra_rdoc_files = [
    "README.rdoc"
  ]
  s.files = `git ls-files`.split("\n")
  s.test_files = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.homepage = %q{http://github.com/lapluviosilla/simple_crowd}
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{Atlassian Crowd support for Authlogic}

  s.add_development_dependency(%q<thoughtbot-shoulda>, [">= 0"])
  s.add_development_dependency(%q<fcoury-matchy>, [">= 0"])
  s.add_development_dependency(%q<rr>, [">= 0"])
  s.add_runtime_dependency(%q<authlogic>, [">= 2.1.3"])
  s.add_runtime_dependency(%q<simple_crowd>, [">= 0.1.6"])

end

