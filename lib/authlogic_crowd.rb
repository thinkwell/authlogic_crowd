require "authlogic_crowd/acts_as_authentic"
require "authlogic_crowd/session"
require "authlogic_crowd/acts_as_authentic_callbacks"
require "authlogic_crowd/yolk_synchronizer"

ActiveRecord::Base.send(:include, AuthlogicCrowd::ActsAsAuthentic)
Authlogic::Session::Base.send(:include, AuthlogicCrowd::Session)
