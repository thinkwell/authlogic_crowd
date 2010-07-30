require "authlogic_crowd/acts_as_authentic"
require "authlogic_crowd/session"

ActiveRecord::Base.send(:include, AuthlogicCrowd::ActsAsAuthentic)
Authlogic::Session::Base.send(:include, AuthlogicCrowd::Session)