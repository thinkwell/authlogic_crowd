require "authlogic_crowd/acts_as_authentic"
require "authlogic_crowd/session"
require "authlogic_crowd/session_callbacks"
require "authlogic_crowd/acts_as_authentic_callbacks"

ActiveRecord::Base.send(:include, AuthlogicCrowd::ActsAsAuthentic)
ActiveRecord::Base.send(:include, AuthlogicCrowd::ActsAsAuthenticCallbacks)
Authlogic::Session::Base.send(:include, AuthlogicCrowd::Session)
Authlogic::Session::Base.send(:include, AuthlogicCrowd::SessionCallbacks)