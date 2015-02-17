module AuthlogicCrowd
  module Session
    def self.included(klass)
      klass.class_eval do
        extend Config
        include InstanceMethods

        attr_accessor :new_registration

        persist :persist_by_crowd, :if => :authenticating_with_crowd?
        validate :validate_by_crowd, :if => [:authenticating_with_crowd?, :needs_crowd_validation?]
        before_destroy :logout_of_crowd, :if => :authenticating_with_crowd?
        before_persisting {|s| s.instance_variable_set('@persisted_by_crowd', false)}
        after_persisting(:if => [:authenticating_with_crowd?, :persisted_by_crowd?, :explicit_login_from_crowd_token?], :unless => :new_registration?) do |s|
          # The user was persisted via a crowd token (not an explicit login via username/password).
          # Simulate explicit login by executing "save" callbacks.
          s.before_save
          s.new_session? ? s.before_create : s.before_update
          s.new_session? ? s.after_create : s.after_update
          s.after_save
        end
        after_create(:if => :authenticating_with_crowd?, :unless => :new_registration?) do |s|
          synchronizer = s.crowd_synchronizer
          synchronizer.local_record = s.record
          synchronizer.crowd_record = s.crowd_record
          synchronizer.sync_from_crowd
        end
      end
    end

    # Configuration for the crowd feature.
    module Config

      # How often should Crowd re-authorize (in seconds).  Default is 0 (always re-authorize)
      def crowd_auth_every(value = nil)
        rw_config(:crowd_auth_every, value, 0)
      end
      alias_method :crowd_auth_every=, :crowd_auth_every

      # Should a new local record be created for existing Crowd users with no
      # matching local record?
      # Default is true.
	    # Add this in your Session object if you need to disable auto-registration via crowd
      def auto_register(value=true)
        auto_register_value(value)
      end

      def auto_register_value(value=nil)
        rw_config(:auto_register,value,true)
      end
      alias_method :auto_register=, :auto_register

      # Should login via a crowd token be treated as an explicit login?
      # If true, explicit login callbacks ({before,after}_{create,update,save})
      # will be triggered when a user is persisted.  If false, the user is
      # persisted but explicit login callbacks do not fire.
      # Default false
      def explicit_login_from_crowd_token(value=nil)
        rw_config(:explicit_login_from_crowd_token, value, false)
      end
      alias_method :explicit_login_from_crowd_token=, :explicit_login_from_crowd_token
    end

    module InstanceMethods

      def initialize(*args)
        super
        @valid_crowd_user = {}
      end

      # Determines if the authenticated user is also a new registration.
      # For use in the session controller to help direct the most appropriate action to follow.
      def new_registration?
        new_registration || !new_registration.nil?
      end

      def auto_register?
        self.class.auto_register_value
      end

      def can_auto_register?(crowd_username)
        auto_register?
      end

      def explicit_login_from_crowd_token?
        !!self.class.explicit_login_from_crowd_token
      end

      def crowd_record
        if @valid_crowd_user[:user_token] && !@valid_crowd_user.has_key?(:record)
          @valid_crowd_user[:record] = crowd_client.find_user_by_token(@valid_crowd_user[:user_token])
        end

        @valid_crowd_user[:record]
      end

      def crowd_client
        @crowd_client ||= klass.crowd_client
      end

      def crowd_synchronizer
        @crowd_synchronizer ||= klass.crowd_synchronizer(crowd_client)
      end

      private

      def authenticating_with_crowd?
        klass.using_crowd? && (authenticated_by_crowd? || has_crowd_user_token? || has_crowd_credentials?)
      end

      # Use the Crowd to "log in" the user using the crowd.token_key
      # cookie/parameter.  If the token_key is valid and returns a valid Crowd
      # user, the find_by_login_method is called to find the appropriate local
      # user/record.
      #
      # If no *local* record is found and auto_register is enabled (default)
      # then automatically create *local* record for them.
      #
      # This method enables a Crowd user to log in without having to explicity
      # log in to this app.  Once a Crowd user has authenticated with this app
      # via this method, future requests usually use the Authlogic::Session
      # module to persist/find users.
      def persist_by_crowd
        clear_crowd_auth_cache
        return false unless has_crowd_user_token? && valid_crowd_user_token? && crowd_username
        self.unauthorized_record = find_or_create_record_from_crowd
        return false unless valid?
        @persisted_by_crowd = true
        true
      rescue SimpleCrowd::CrowdError => e
        Rails.logger.warn "CROWD[#{__method__}]: Unexpected error.  #{e}"
        return false
      end

      # Validates the current record/user with Crowd.  This validates the
      # crowd.token_key cookie/parameter and/or explicit credentials.
      #
      # If a crowd.token_key exists and matches a previously authenticated
      # token_key, this method will only verify the token with crowd if the
      # last authorization was more than crowd_auth_every seconds ago (see
      # the crowd_auth_every config option).
      def validate_by_crowd
        # Credentials trump a crowd.token_key.
        # We don't even attempt to authenticated from the token key if
        # credentials are present.
        if has_crowd_credentials?
          # HACK: Remove previous login/password errors since we are going to
          # try to validate them with crowd
          errors.instance_variable_get('@errors').delete(login_field.to_s)
          errors.instance_variable_get('@errors').delete(password_field.to_s)

          if valid_crowd_credentials?
            self.attempted_record = find_or_create_record_from_crowd
            unless self.attempted_record
              errors.add(login_field, I18n.t('error_messages.login_not_found', :default => "is not valid"))
            end
          else
            errors.add(login_field, I18n.t('error_messages.login_not_found', :default => "is not valid")) if !@valid_crowd_user[:username]
            errors.add(password_field, I18n.t('error_messages.password_invalid', :default => "is not valid")) if @valid_crowd_user[:username]
          end

        elsif has_crowd_user_token?
          # Regenerate token using last_username
          if should_auto_refresh_user_token?
            refresh_user_token
            Rails.logger.debug "CROWD: Crowd user token refreshed."
          end
          
          unless valid_crowd_user_token? && valid_crowd_username?
            errors.add_to_base(I18n.t('error_messages.crowd_invalid_user_token', :default => "invalid user token"))
          end

        elsif authenticated_by_crowd?
          destroy
          errors.add_to_base(I18n.t('error_messages.crowd_missing_using_token', :default => "missing user token"))
        end

        unless self.attempted_record && self.attempted_record.valid?
          errors.add_to_base('record is not valid')
        end

        if errors.count == 0
          # Set crowd.token_key cookie
          save_crowd_cookie

          # Cache crowd authorization to make future requests faster (if
          # crowd_auth_every config is enabled)
          cache_crowd_auth
        end
      rescue SimpleCrowd::CrowdError => e
        Rails.logger.warn "CROWD[#{__method__}]: Unexpected error.  #{e}"
        errors.add_to_base("Crowd error: #{e}")
      end

      # Validate the crowd.token_key (if one exists)
      # Uses simple_crowd to verify the user token on the configured crowd server.
      # This only checks that the token is valid with Crowd.  It does not check
      # that the token belongs to a valid local user/record.
      def valid_crowd_user_token?
        unless @valid_crowd_user.has_key?(:user_token)
          @valid_crowd_user[:user_token] = nil
          user_token = crowd_user_token
          if user_token
            if crowd_client.is_valid_user_token?(user_token)
              @valid_crowd_user[:user_token] = user_token
            end
          end
        end
        !!@valid_crowd_user[:user_token]
      end

      # Validate username/password using Crowd.
      # Uses simple_crowd to verify credentials on the configured crowd server.
      def valid_crowd_credentials?
        login = send(login_field)
        password = send("protected_#{password_field}")
        return false unless login && password

        unless @valid_crowd_user.has_key?(:credentials)
          @valid_crowd_user[:user_token] = nil

          # Authenticate using login/password
          user_token = crowd_fetch {crowd_client.authenticate_user(login, password)}
          if user_token
            @valid_crowd_user[:user_token] = user_token
            @valid_crowd_user[:username] = login
          else
            # See if the login exists
            crecord = @valid_crowd_user[:record] = crowd_fetch {crowd_client.find_user_by_name(login)}
            @valid_crowd_user[:username] = crecord ? crecord.username : nil
          end

          # Attempt to find user with crowd email field instead of principal name
          if !@valid_crowd_user[:username] && login =~ Authlogic::Regex.email
            crecord = @valid_crowd_user[:record] = crowd_fetch {crowd_client.find_user_by_email(login)}
            if crecord
              user_token = crowd_fetch {crowd_client.authenticate_user(crecord.username, password)}
              @valid_crowd_user[:username] = crecord.username
              @valid_crowd_user[:user_token] = user_token if user_token
            end
          end

          @valid_crowd_user[:credentials] = !!@valid_crowd_user[:user_token]
        end

        @valid_crowd_user[:credentials]
      end

      # Validate the crowd username against the current record
      def valid_crowd_username?
        record_login = send(login_field) || (unauthorized_record && unauthorized_record.login)

        # Use the last username if available to reduce crowd calls
        if @valid_crowd_user[:user_token] && @valid_crowd_user[:user_token] == controller.session[:"crowd.last_user_token"]
          crowd_login = controller.session[:"crowd.last_username"]
        end
        crowd_login = crowd_username unless crowd_login

        crowd_login && crowd_login == record_login
      end

      def crowd_username
        if @valid_crowd_user[:user_token] && !@valid_crowd_user.has_key?(:username)
          crecord = crowd_record
          @valid_crowd_user[:username] = crecord ? crecord.username : nil
        end

        @valid_crowd_user[:username]
      end

      def cache_crowd_auth
        if @valid_crowd_user[:user_token]
          controller.session[:"crowd.last_auth"] = Time.now
          controller.session[:"crowd.last_user_token"] = @valid_crowd_user[:user_token].dup
          controller.session[:"crowd.last_username"] = @valid_crowd_user[:username].dup if @valid_crowd_user[:username]
          Rails.logger.debug "CROWD: Cached crowd authorization (#{controller.session[:"crowd.last_username"]}).  Next authorization at #{Time.now + self.class.crowd_auth_every}." if self.class.crowd_auth_every.to_i > 0
        else
          clear_crowd_auth_cache
        end
      end

      # Clear cached crowd information
      def clear_crowd_auth_cache
        controller.session.delete_if {|key, val| ["crowd.last_user_token", "crowd.last_auth", "crowd.last_username"].include?(key.to_s)}
      end

      def save_crowd_cookie
        if @valid_crowd_user[:user_token] && @valid_crowd_user[:user_token] != crowd_user_token
          controller.params.delete("crowd.token_key")
          controller.cookies[:"crowd.token_key"] = {
            :domain => crowd_cookie_info[:domain],
            :secure => crowd_cookie_info[:secure],
            :value => @valid_crowd_user[:user_token],
          }
        end
      end

      def destroy_crowd_cookie
        controller.cookies.delete(:"crowd.token_key", :domain => crowd_cookie_info[:domain])
      end

      # When the crowd_auth_every config option is set and the user is logged
      # in via crowd, validation can be skipped in certain cases (token_key
      # matches last token_key and last authorization was less than
      # crowd_auth_every seconds).
      def needs_crowd_validation?
        res = true
        if !has_crowd_credentials? && authenticated_by_crowd? && self.class.crowd_auth_every.to_i > 0
          last_user_token = controller.session[:"crowd.last_user_token"]
          last_auth = controller.session[:"crowd.last_auth"]
          if last_user_token
            if !crowd_user_token
              Rails.logger.debug "CROWD: Re-authorization required.  Crowd token does not exist."
            elsif last_user_token != crowd_user_token
              Rails.logger.debug "CROWD: Re-authorization required.  Crowd token does match cached token."
            elsif last_auth && last_auth <= self.class.crowd_auth_every.ago
              Rails.logger.debug "CROWD: Re-authorization required.  Last authorization was at #{last_auth}."
            elsif !last_auth
              Rails.logger.debug "CROWD: Re-authorization required.  Unable to determine last authorization time."
            else
              Rails.logger.debug "CROWD: Authenticating from cache.  Next authorization at #{last_auth + self.class.crowd_auth_every}."
              res = false
            end
          end
        end
        res
      end

      def find_or_create_record_from_crowd
        return nil unless crowd_username
        record = search_for_record_from_crowd(find_by_login_method, crowd_username)

        if !record && auto_register? && can_auto_register?(crowd_username)
          synchronizer = crowd_synchronizer
          synchronizer.crowd_record = crowd_record
          record = synchronizer.create_record_from_crowd
          self.new_registration if record
        end

        record
      end

      def search_for_record_from_crowd(find_by_login_method, crowd_username)
        search_for_record(find_by_login_method, crowd_username)
      end

      # Logout of crowd and remove the crowd cookie.
      def logout_of_crowd
        if crowd_user_token
          # Send an invalidate call for single signout
          # Apparently there is no way of knowing if this was successful or not.
          begin
            crowd_client.invalidate_user_token(crowd_user_token)
          rescue SimpleCrowd::CrowdError => e
            Rails.logger.debug "CROWD: logout_of_crowd #{e.message}"
          end
        end

        controller.params.delete("crowd.token_key")
        destroy_crowd_cookie
        clear_crowd_auth_cache
        true
      end

      def crowd_user_token
        controller && (controller.params["crowd.token_key"] || controller.cookies[:"crowd.token_key"])
      end

      def authenticated_by_crowd?
        !!controller.session[:"crowd.last_user_token"]
      end

      def persisted_by_crowd?
        !!@persisted_by_crowd
      end

      def has_crowd_user_token?
        !!crowd_user_token
      end

      def has_crowd_credentials?
        login_field && password_field && (!send(login_field).nil? || !send("protected_#{password_field}").nil?)
      end

      def crowd_cookie_info
        @crowd_cookie_info ||= crowd_client.get_cookie_info
      end
      
      # As Authlogic creates a cookie to know if the user wants to be remembered
      # returns true only if the cookie exists.
      # For cookie_key see Authlogic::Session::Cookies::Config
      def should_remember_user?
        controller && controller.cookies[cookie_key].present?
      end
      
      def refresh_user_token
        user_login = controller.session[:"crowd.last_username"]
        user_token = crowd_fetch {crowd_client.create_user_token(user_login)}
        @valid_crowd_user[:user_token] = user_token
      end
      
      def auto_refresh_user_token_for
        should_remember_user? ? self.class.remember_me_for : 30.minutes
      end
      
      def should_auto_refresh_user_token?
        return false unless controller && controller.session[:last_request_at]
        controller.session[:last_request_at] >= auto_refresh_user_token_for.ago
      end

      # Executes the given block, returning nil if a SimpleCrowd::CrowdError
      # ocurrs.
      def crowd_fetch
        begin
          yield
        rescue SimpleCrowd::CrowdError => e
          Rails.logger.debug "CROWD[#{caller[0][/`.*'/][1..-2]}]: #{e.message}"
          nil
        end
      end
    end
  end
end
