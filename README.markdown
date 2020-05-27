Authlogic Crowd
===============

Authlogic Crowd is an extension of the Authlogic library to add Atlassian Crowd
support.  We have only tested this plugin with Authlogic 2.x and Rails 2.x.


## Installation

Add the gem to your Gemfile:

    gem 'authlogic_crowd'

and run `bundle`.


## Configuration

In your model class, add Crowd configuration:

    class User < ActiveRecord::Base
      acts_as_authentic do |c|
        c.crowd_service_url = "http://mycrowdapp:8095/crowd"
        c.crowd_app_name = "testapp"
        c.crowd_app_password = "testpass"
      end
    end


## Usage

When a user logs in via your existing login form, the user's credentials will
be authenticated with Crowd.  authlogic_crowd will also authenticate users with
an existing Crowd token_key cookie.

authlogic_crowd acts as an *additional* authentication plugin.  Other
authentication plugins will be tried in the order in which they were
registered.  Thus, if your model contains password fields used by the
built-in `Password` authentication module, Authlogic will attempt to
authenticate via local passwords first.  If this fails, it will move on to
authenticate via Crowd.  If you want to skip internal password checking, you
should set internal password fields to `nil`.


### Re-authenticate Every x Seconds

By default, authlogic_crowd authenticates the Crowd token key cookie on every
request.  You can tell the module to cache authentication and only
re-authenticate periodically using *yolk_auth_every*:

    class UserSession < Authlogic::Session::Base
      yolk_auth_every 10.minutes
    end


### Auto Registration

When a Crowd user logs in with no corresponding local user, a new local user
will be added by default.  You can disable auto-registration with the
`auto_register` setting in your Authlogic session:

    class UserSession < Authlogic::Session::Base
      auto_register false
    end


### Auto Add Crowd Records

When a new local user is added, authlogic_crowd can add a corresponding user to
Crowd.  This is disabled by default.  To enable, use the `add_yolk_records`
setting:

    class User < ActiveRecord::Base
      acts_as_authentic do |c|
        c.add_yolk_records = true
      end
    end


### Auto Update Crowd Records

When a local user is updated, authlogic_crowd will update the corresponding
Crowd user.  This is enabled by default.  To disable, use the
`update_yolk_records` setting:

    class User < ActiveRecord::Base
      acts_as_authentic do |c|
        c.update_yolk_records = false
      end
    end


### Disable Crowd

If you need to disable Crowd (in testing for example), use the `yolk_enabled`
setting:

    class User < ActiveRecord::Base
      acts_as_authentic do |c|
        c.yolk_enabled = false
      end
    end


## Callbacks

authlogic_crowd adds several callbacks that can be used to customize the
plugin.  Callbacks execute in the following order:

  before_create_from_yolk  
  before_sync_from_yolk  
  sync_from_yolk  
  after_sync_from_yolk  
  after_create_from_yolk  

  before_create_yolk_record  
  before_sync_to_yolk  
  sync_to_yolk  
  after_sync_to_yolk  
  after_create_yolk_record  


### before_sync_from_yolk, sync_from_yolk, after_sync_from_yolk

Called whenever a local record should be synchronized from Crowd.  Each time a
user logs in to your application via Crowd (with login credentials or the
token_key cookie), the local user record is synchronized with the Crowd record.

For example:

    class User < ActiveRecord::Base
      acts_as_authentic do |c|
        c.sync_from_yolk :update_from_yolk_record
      end

      def update_from_yolk_record
        self.email = self.yolk_record.email
        self.name = self.yolk_record.first_name + ' ' + self.yolk_record.last_name
      end
    end


### before_sync_to_yolk, sync_to_yolk, after_sync_to_yolk

Called whenever Crowd should be synchornized from a local record.

For example:

    class User < ActiveRecord::Base
      acts_as_authentic do |c|
        c.sync_to_yolk :update_yolk_record
      end

      def update_yolk_record
        self.yolk_record = self.email
        self.yolk_record.display_name = self.name
        self.yolk_record.first_name = self.first_name
        self.yolk_record.last_name = self.last_name
      end
    end


### before_create_from_yolk, after_create_from_yolk

Called when creating a new local record from a crowd record.  When
auto-registration is enabled new local users will be created automatically
when existing Crowd users log in to your application.


### before_create_yolk_record, after_create_yolk_record

Called when creating a new crowd record from a new local record.  These
callbacks are only executed if the `add_yolk_records` setting is enabled.
