module AuthlogicCrowd
  module Session
    def self.included(klass)
      klass.send :prepend, InstanceMethods
      klass.class_eval do
        extend Config

        attr_accessor :new_registration

        persist :persist_by_yolk, :if => :authenticating_with_yolk?
        validate :validate_by_yolk, :if => [:authenticating_with_yolk?, :needs_yolk_validation?]
        before_destroy :logout_of_yolk, :if => :authenticating_with_yolk?
        before_persisting {|s| s.instance_variable_set('@persisted_by_yolk', false)}
        after_persisting(:if => [:authenticating_with_yolk?, :persisted_by_yolk?, :explicit_login_from_yolk_token?], :unless => :new_registration?) do |s|
          # The user was persisted via a yolk token (not an explicit login via username/password).
          # Simulate explicit login by executing "save" callbacks.
          s.run_callbacks :before_save
          s.run_callbacks s.new_session? ? :before_create : :before_update
          s.run_callbacks s.new_session? ? :after_create : :after_update
          s.run_callbacks :after_save
        end
        after_create(:if => :authenticating_with_yolk?, :unless => :new_registration?) do |s|
          synchronizer = s.yolk_synchronizer
          synchronizer.local_record = s.record
          synchronizer.yolk_record = s.yolk_record
          synchronizer.sync_from_yolk
        end
      end
    end

    # Configuration for the Yolk feature.
    module Config

      # How often should Yolk re-authorize (in seconds).  Default is 0 (always re-authorize)
      def yolk_auth_every(value = nil)
        rw_config(:yolk_auth_every, value, 0)
      end
      alias_method :yolk_auth_every=, :yolk_auth_every

      # Should a new local record be created for existing Yolk users with no
      # matching local record?
      # Default is true.
	    # Add this in your Session object if you need to disable auto-registration via Yolk
      def auto_register(value=true)
        auto_register_value(value)
      end

      def auto_register_value(value=nil)
        rw_config(:auto_register,value,true)
      end
      alias_method :auto_register=, :auto_register

      # Should login via a yolk token be treated as an explicit login?
      # If true, explicit login callbacks ({before,after}_{create,update,save})
      # will be triggered when a user is persisted.  If false, the user is
      # persisted but explicit login callbacks do not fire.
      # Default false
      def explicit_login_from_yolk_token(value=nil)
        rw_config(:explicit_login_from_yolk_token, value, false)
      end
      alias_method :explicit_login_from_yolk_token=, :explicit_login_from_yolk_token

      # Time after last_request_at (in seconds) in which the user token should
      # be refreshed without having to enter login credentials. Applies to users
      # that did not use the remember_me checkbox.
      # Default is 0 meaning no refreshing of user token
      def session_timeout_default(value=nil)
        rw_config(:session_timeout_default,value,0)
      end
      alias_method :session_timeout_default=, :session_timeout_default

      # Same as session_timeout_default but applies to users that used the
      # remember_me option.
      # Default is 0 meaning no refreshing of user token
      def session_timeout_remember_me(value=nil)
        rw_config(:session_timeout_remember_me,value,0)
      end
      alias_method :session_timeout_remember_me=, :session_timeout_remember_me
    end

    module InstanceMethods

      def initialize(*args)
        super(*args)
        @valid_yolk_user = {}
      end

      # Determines if the authenticated user is also a new registration.
      # For use in the session controller to help direct the most appropriate action to follow.
      def new_registration?
        new_registration || !new_registration.nil?
      end

      def auto_register?
        self.class.auto_register_value
      end

      def can_auto_register?(yolk_username)
        auto_register?
      end

      def explicit_login_from_yolk_token?
        !!self.class.explicit_login_from_yolk_token
      end

      def yolk_record
        if @valid_yolk_user[:user_token] && !@valid_yolk_user.has_key?(:record)
          begin
            @valid_yolk_user[:record] = yolk_client.get_user_by_token(@valid_yolk_user[:user_token])
            Rails.logger.info "YOLK :: #{@valid_yolk_user[:user_token]} : got user by token : #{@valid_yolk_user[:record].username}"
          rescue StandardError => error
            Rails.logger.info "YOLK :: #{@valid_yolk_user[:user_token]} : NO user by token : #{error.message}"
          end
        end

        @valid_yolk_user[:record]
      end

      def yolk_client
        @yolk_client ||= klass.yolk_client
      end

      def yolk_synchronizer
        @yolk_synchronizer ||= klass.yolk_synchronizer(yolk_client)
      end

      private

      def authenticating_with_yolk?
        klass.using_yolk? && (authenticated_by_yolk? || has_yolk_user_token? || has_yolk_credentials?)
      end

      # Use the Yolk to "log in" the user using the crowd.token_key
      # cookie/parameter.  If the token_key is valid and returns a valid Yolk
      # user, the find_by_login_method is called to find the appropriate local
      # user/record.
      #
      # If no *local* record is found and auto_register is enabled (default)
      # then automatically create *local* record for them.
      #
      # This method enables a Yolk user to log in without having to explicity
      # log in to this app.  Once a Yolk user has authenticated with this app
      # via this method, future requests usually use the Authlogic::Session
      # module to persist/find users.
      def persist_by_yolk
        clear_yolk_auth_cache
        return false unless has_yolk_user_token? && valid_yolk_user_token? && yolk_username
        self.unauthorized_record = find_or_create_record_from_yolk
        return false unless valid?
        @persisted_by_yolk = true
        true
      rescue StandardError => e
        Rails.logger.error "YOLK::ERROR[#{__method__}]: Unexpected error.  #{e}"
        Rails.logger.error e.backtrace
        return false
      end

      # Validates the current record/user with Yolk.  This validates the
      # crowd.token_key cookie/parameter and/or explicit credentials.
      #
      # If a crowd.token_key exists and matches a previously authenticated
      # token_key, this method will only verify the token with yolk if the
      # last authorization was more than yolk_auth_every seconds ago (see
      # the yolk_auth_every config option).
      def validate_by_yolk
        # Credentials trump a crowd.token_key.
        # We don't even attempt to authenticated from the token key if
        # credentials are present.
        if has_yolk_credentials?
          # HACK: Remove previous login/password errors since we are going to
          # try to validate them with yolk
          errors.delete(login_field.to_s)
          errors.delete(password_field.to_s)

          if valid_yolk_credentials?
            self.attempted_record = find_or_create_record_from_yolk
            unless self.attempted_record
              errors.add(login_field, I18n.t('error_messages.login_not_found', :default => "is not valid"))
            end
          else
            errors.add(login_field, I18n.t('error_messages.login_not_found', :default => "is not valid")) if !@valid_yolk_user[:username]
            errors.add(password_field, I18n.t('error_messages.password_invalid', :default => "is not valid")) if @valid_yolk_user[:username]
          end

        elsif has_yolk_user_token?
          # Regenerate token using last_username
          if should_auto_refresh_user_token?
            refresh_user_token
          end

          unless valid_yolk_user_token? && valid_yolk_username?
            errors[:base] << I18n.t('error_messages.crowd_invalid_user_token', :default => "invalid user token")
          end

        elsif authenticated_by_yolk?
          destroy
          errors[:base] << I18n.t('error_messages.crowd_missing_using_token', :default => "missing user token")
        end

        unless self.attempted_record && self.attempted_record.valid?
          errors[:base] << 'record is not valid'
        end

        if errors.count == 0
          # Set crowd.token_key cookie
          save_yolk_cookie

          set_etag_header

          # Cache yolk authorization to make future requests faster (if
          # yolk_auth_every config is enabled)
          cache_yolk_auth
        end
      rescue StandardError => e
        Rails.logger.warn "YOLK::ERROR[#{__method__}]: Unexpected error.  #{e}"
        Rails.logger.error e.backtrace
        errors[:base] << "Crowd error: #{e}"
      end

      # Validate the crowd.token_key (if one exists)
      # This only checks that the token is valid with Yolk.  It does not check
      # that the token belongs to a valid local user/record.
      def valid_yolk_user_token?
        unless @valid_yolk_user.has_key?(:user_token)
          @valid_yolk_user[:user_token] = nil
          user_token = yolk_user_token
          if user_token
            if yolk_client.is_valid_user_token?(user_token)
              Rails.logger.info "YOLK :: #{user_token} : valid token"
              @valid_yolk_user[:user_token] = user_token
            else
              Rails.logger.info "YOLK :: #{user_token} : NOT valid token"
            end
          end
        end
        !!@valid_yolk_user[:user_token]
      end

      # Validate username/password using Yolk.
      def valid_yolk_credentials?
        login = send(login_field)
        password = send("protected_#{password_field}")
        return false unless login && password

        unless @valid_yolk_user.has_key?(:credentials)
          @valid_yolk_user[:user_token] = nil

          # Authenticate using login/password
          user = yolk_client.authenticate_user(login, password)
          if user
            Rails.logger.info "YOLK :: #{login} : authenticated : #{user.inspect}" if user.token
            Rails.logger.error "YOLK :: #{login} : authenticated BUT NO TOKEN: #{user.inspect}" unless user.token
            @valid_yolk_user[:record] = user
            @valid_yolk_user[:user_token] = user.token
            @valid_yolk_user[:username] = login
          else
            Rails.logger.info "YOLK :: #{login} : NOT authenticated"
            # See if the login exists
            begin
              crecord = @valid_yolk_user[:record] = yolk_client.get_user(login)
              Rails.logger.info "YOLK :: #{login} : got user"
              @valid_yolk_user[:username] = crecord.username
            rescue StandardError => error
              Rails.logger.info "YOLK :: #{login} : NO user : #{error.message}"
              @valid_yolk_user[:username] = nil
            end
          end

          @valid_yolk_user[:credentials] = !!@valid_yolk_user[:user_token]
        end

        @valid_yolk_user[:credentials]
      end

      # Validate the yolk username against the current record
      def valid_yolk_username?
        record_login = send(login_field) || (unauthorized_record && unauthorized_record.login)

        # Use the last username if available to reduce yolk calls
        if @valid_yolk_user[:user_token] && @valid_yolk_user[:user_token] == controller.session[:"crowd.last_user_token"]
          yolk_login = controller.session[:"crowd.last_username"]
        end
        yolk_login = yolk_username unless yolk_login

        yolk_login && yolk_login == record_login
      end

      def yolk_username
        if @valid_yolk_user[:user_token] && !@valid_yolk_user.has_key?(:username)
          crecord = yolk_record
          @valid_yolk_user[:username] = crecord ? crecord.username : nil
        end

        @valid_yolk_user[:username]
      end

      def cache_yolk_auth
        if @valid_yolk_user[:user_token]
          controller.session[:"crowd.last_auth"] = Time.now
          controller.session[:"crowd.last_user_token"] = @valid_yolk_user[:user_token].dup
          controller.session[:"crowd.last_username"] = @valid_yolk_user[:username].dup if @valid_yolk_user[:username]
          Rails.logger.debug "YOLK: Cached yolk authorization (#{controller.session[:"crowd.last_username"]}).  Next authorization at #{Time.now + self.class.yolk_auth_every}." if self.class.yolk_auth_every.to_i > 0
        else
          clear_yolk_auth_cache
        end
      end

      # Clear cached crowd information
      def clear_yolk_auth_cache
        controller.session.delete("crowd.last_user_token")
        controller.session.delete("crowd.last_auth")
        controller.session.delete("crowd.last_username")
      end

      def save_yolk_cookie
        if @valid_yolk_user[:user_token] && @valid_yolk_user[:user_token] != (controller && controller.cookies[:"crowd.token_key"])
          controller.params.delete("crowd.token_key")
          controller.cookies[:"crowd.token_key"] = {
            :domain => yolk_cookie_info[:domain],
            :secure => yolk_cookie_info[:secure],
            :SameSite => 'None',
            :value => @valid_yolk_user[:user_token],
          }
        end
      end

      def set_etag_header
        if @valid_yolk_user[:user_token] && @valid_yolk_user[:user_token]
          controller.headers['ETag'] = "crowd.token_key=#{@valid_yolk_user[:user_token]}"
          Rails.logger.info "YOLK :: set ETag header : #{controller.headers['ETag']}"
        end
      end

      def destroy_yolk_cookie
        controller.cookies.delete(:"crowd.token_key", :domain => klass.yolk_cookie_info[:domain])
      end

      # When the yolk_auth_every config option is set and the user is logged
      # in via yolk, validation can be skipped in certain cases (token_key
      # matches last token_key and last authorization was less than
      # yolk_auth_every seconds).
      def needs_yolk_validation?
        res = true
        if !has_yolk_credentials? && authenticated_by_yolk? && self.class.yolk_auth_every.to_i > 0
          last_user_token = controller.session[:"crowd.last_user_token"]
          last_auth = controller.session[:"crowd.last_auth"]
          if last_user_token
            if !yolk_user_token
              Rails.logger.debug "YOLK: Re-authorization required.  Yolk token does not exist."
            elsif last_user_token != yolk_user_token
              Rails.logger.debug "YOLK: Re-authorization required.  Yolk token does match cached token."
            elsif last_auth && last_auth <= self.class.yolk_auth_every.seconds.ago
              Rails.logger.debug "YOLK: Re-authorization required.  Last authorization was at #{last_auth}."
            elsif !last_auth
              Rails.logger.info "YOLK: Re-authorization required.  Unable to determine last authorization time."
            else
              Rails.logger.info "YOLK: Authenticating from cache.  Next authorization at #{last_auth + self.class.yolk_auth_every}."
              res = false
            end
          end
        end
        res
      end

      def find_or_create_record_from_yolk
        return nil unless yolk_username
        record = search_for_record_from_yolk(find_by_login_method, yolk_username)

        if !record && auto_register? && can_auto_register?(yolk_username)
          synchronizer = yolk_synchronizer
          synchronizer.yolk_record = yolk_record
          record = synchronizer.create_record_from_yolk
          self.new_registration if record
        end

        record
      end

      def search_for_record_from_yolk(find_by_login_method, yolk_username)
        search_for_record(find_by_login_method, yolk_username)
      end

      # Logout of yolk and remove the yolk cookie.
      def logout_of_yolk
        if yolk_user_token
          # Send an invalidate call for single signout
          # Apparently there is no way of knowing if this was successful or not.
          begin
            yolk_client.invalidate_user_token(yolk_user_token)
            Rails.logger.info "YOLK :: #{yolk_user_token} : invalidated user token"
          rescue StandardError => e
            Rails.logger.error "YOLK::ERROR[#{__method__}]: #{e.message}"
            Rails.logger.error e.backtrace
          end
        end

        controller.params.delete("crowd.token_key")
        destroy_yolk_cookie
        clear_yolk_auth_cache
        true
      end

      def yolk_user_token
        controller && (controller.params["crowd.token_key"] || controller.cookies[:"crowd.token_key"] || yolk_user_token_etag)
      end

      def yolk_user_token_etag
        controller && controller.headers['ETag']&.match(/crowd.token_key=(.*)/)&.captures&.first
      end

      def authenticated_by_yolk?
        !!controller.session[:"crowd.last_user_token"]
      end

      def persisted_by_yolk?
        !!@persisted_by_yolk
      end

      def has_yolk_user_token?
        !!yolk_user_token
      end

      def has_yolk_credentials?
        login_field && password_field && (!send(login_field).nil? || !send("protected_#{password_field}").nil?)
      end

      # As Authlogic creates a cookie to know if the user wants to be remembered
      # returns true only if the cookie exists and it belongs to the logged in user.
      # For cookie_key see Authlogic::Session::Cookies::Config
      def should_remember_user?
        return false unless controller && controller.cookies[cookie_key].present?
        credentials_from_cookie = controller.cookies[cookie_key].split("::")[1]
        credentials_from_cookie == controller.session[cookie_key]
      end

      def refresh_user_token
        user_login = controller.session[:"crowd.last_username"]
        begin
          user_token = yolk_client.get_user_token(user_login)
          Rails.logger.info "YOLK :: #{user_login} : refreshed user token : #{user_token}"
          @valid_yolk_user[:user_token] = user_token
        rescue StandardError => error
          Rails.logger.error "YOLK :: #{user_login} : could not refresh user token : #{error.message}"
        end
      end

      def auto_refresh_user_token_for
        should_remember_user? ? self.class.session_timeout_remember_me : self.class.session_timeout_default
      end

      def should_auto_refresh_user_token?
        last_user_token = controller.session[:"crowd.last_user_token"]
        return false unless controller && controller.session[:last_request_at] && last_user_token == yolk_user_token
        controller.session[:last_request_at] >= auto_refresh_user_token_for.seconds.ago
      end
    end
  end
end
