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
re-authenticate periodically using *crowd_auth_every*:

    class UserSession < Authlogic::Session::Base
      crowd_auth_every 10.minutes
    end


### Auto Registration

When authlogic_crowd encounters a valid Crowd user with no corresponding local
user, a new local user will be added by default.  You can disable
auto-registration in your Authlogic session model:

    class UserSession < Authlogic::Session::Base
      auto_register false
    end


### Auto Add Crowd Records

When a new local user is added, authlogic_crowd can add a corresponding user to
Crowd.  This is disabled by default.  To enable, configure your model:

    class User < ActiveRecord::Base
      acts_as_authentic do |c|
        c.add_crowd_records = true
      end
    end


### Disable Crowd

If you need to disable Crowd (in testing for example), use the `crowd_enabled`
setting:

    class User < ActiveRecord::Base
      acts_as_authentic do |c|
        c.crowd_enabled = false
      end
    end


## Callbacks

authlogic_crowd adds several callbacks that can be used to customize the
plugin.  Callbacks execute in the following order:

  before_create_from_crowd  
  before_sync_from_crowd  
  sync_from_crowd  
  after_sync_from_crowd  
  after_create_from_crowd  

  before_create_crowd_record  
  before_sync_to_crowd  
  sync_to_crowd  
  after_sync_to_crowd  
  after_create_crowd_record  

### before_sync_from_crowd, sync_from_crowd, after_sync_from_crowd

Called whenever a local record should be synchronized from Crowd.  Each time a
user logs in to your application via Crowd (with login credentials or the
token_key cookie), the local user record is synchronized with the Crowd record.

For example:

    class User < ActiveRecord::Base
      acts_as_authentic do |c|
        ...
        c.sync_from_crowd :update_from_crowd_record
      end

      def update_from_crowd_record
        self.email = self.crowd_record.email
        self.name = self.crowd_record.first_name + ' ' + self.crowd_record.last_name
      end
    end

### before_sync_to_crowd, sync_to_crowd, after_sync_to_crowd

Called whenever Crowd should be synchornized from a local record.

### before_create_from_crowd, after_create_from_crowd

Called when creating a new local record from a crowd record.  When
auto-registration is enabled new local users will be created automatically
when existing Crowd users log in to your application.

### before_create_crowd_record, after_create_crowd_record

Called when creating a new crowd record from a new local record.  These
callbacks are only executed if the `add_crowd_records` setting is enabled.
