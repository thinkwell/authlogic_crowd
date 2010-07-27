require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'matchy'
require 'rr'

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'authlogic_crowd'

class Test::Unit::TestCase
  include RR::Adapters::TestUnit
end
