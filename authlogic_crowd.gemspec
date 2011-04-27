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
  s.files = %w(
    .document
    .gitignore
    Gemfile
    Gemfile.lock
    README.rdoc
    Rakefile
    authlogic_crowd.gemspec
    lib/authlogic_crowd.rb
    lib/authlogic_crowd/acts_as_authentic.rb
    lib/authlogic_crowd/acts_as_authentic_callbacks.rb
    lib/authlogic_crowd/session.rb
    lib/authlogic_crowd/session_callbacks.rb
    lib/authlogic_crowd/version.rb
    test/helper.rb
    test/test_authlogic_crowd.rb
  )
  s.test_files = %w(
    test/helper.rb
    test/test_authlogic_crowd.rb
  )
  s.homepage = %q{http://github.com/lapluviosilla/authlogic_crowd}
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{Atlassian Crowd support for Authlogic}

  s.add_development_dependency(%q<thoughtbot-shoulda>, [">= 0"])
  s.add_development_dependency(%q<fcoury-matchy>, [">= 0"])
  s.add_development_dependency(%q<rr>, [">= 0"])
  s.add_runtime_dependency(%q<authlogic>, [">= 2.1.3", "< 3.0.0"])
  s.add_runtime_dependency(%q<simple_crowd>, [">= 1.0.0"])

end

