module AuthlogicCrowd
  module Session
    def self.included(klass)
      klass.class_eval do
        extend Config
        include Methods
      end
    end
    module Config

      # Single Signout (defaults to true)
      # @param [Boolean] value
      def crowd_sso(value=nil)
        rw_config(:crowd_sso, value, true)
      end
      alias_method :crowd_sso=, :crowd_sso
      
      def crowd_sso?
        crowd_sso
      end

      # Auto Register is enabled by default.
	  # Add this in your Session object if you need to disable auto-registration via crowd
      def auto_register(value=true)
        auto_register_value(value)
      end
      def auto_register_value(value=nil)
        rw_config(:auto_register,value,true)
      end
      alias_method :auto_register=,:auto_register

      def crowd_user_token= token
        session_user_token = controller.session[:"crowd.token_key"]
        cookie_user_token = crowd_sso? && controller.cookies[:"crowd.token_key"]
        cached_info = Rails.cache.read('crowd_cookie_info')
        @crowd_client ||= SimpleCrowd::Client.new({
          :service_url => klass.crowd_service_url,
          :app_name => klass.crowd_app_name,
          :app_password => klass.crowd_app_password})
        crowd_cookie_info ||= cached_info || @crowd_client.get_cookie_info
        controller.session[:"crowd.token_key"] = token unless session_user_token == token
        controller.cookies[:"crowd.token_key"] = {:domain => crowd_cookie_info[:domain],
                                                  :secure => crowd_cookie_info[:secure],
                                                  :value => token} unless cookie_user_token == token || !crowd_sso?
      end
      def crowd_user_token
        controller.params["crowd.token_key"] || controller.cookies[:"crowd.token_key"] || controller.session[:"crowd.token_key"]
      end
    end
    module Methods
      def self.included(klass)
        klass.class_eval do
          attr_accessor :new_registration
          validate :validate_by_crowd, :if => :authenticating_with_crowd?
          persist :validate_by_crowd, :if => :authenticating_with_crowd?
          after_create :sync_with_crowd, :if => :authenticating_with_crowd?
          before_destroy :logout_of_crowd, :if => [:authenticating_with_crowd?, :sso?]
        end
      end

      # Temporary storage of crowd record for syncing purposes
      attr_accessor :crowd_record

      # Determines if the authenticated user is also a new registration.
      # For use in the session controller to help direct the most appropriate action to follow.
      def new_registration?
        new_registration || !new_registration.nil?
      end

      # Determines if the authenticated user has a complete registration (no validation errors)
      # For use in the session controller to help direct the most appropriate action to follow.
      def registration_complete?
        attempted_record && attempted_record.valid?
      end

      def auto_register?
        self.class.auto_register_value
      end

      protected

      # Determines whether to use crowd to authenticate and validate the current request
      # For now we assume the app wants to use Crowd exclusively.
      # Use crowd authentication if tokens are present or if login/password is available but not valid or is blank in db
      # TODO: Add flexibility regarding multiple authentication methods and identity mapping
      def authenticating_with_crowd?
        errors.empty? &&
        !klass.crowd_app_name.blank? &&
        !klass.crowd_app_password.blank? &&
        ((login_field && (!send(login_field).nil? || !send("protected_#{password_field}").nil?)) ||
          controller.cookies[:"crowd.token_key"] || controller.session[:"crowd.token_key"] || controller.params["crowd.token_key"])
      end

      def authenticating_with_password?
        !authenticating_with_crowd? && login_field && (!send(login_field).nil? || !send("protected_#{password_field}").nil?)
      end

      def sso?
        self.class.crowd_sso
      end

#      def credentials
#        if authenticating_with_crowd?
#          details = {}
#          details[login_field.to_sym] = send(login_field)
#          details[password_field.to_sym] = "<protected>"
#          details[crowd_user_token_field.to_sym] = send(crowd_user_token_field)
#          details
#        else
#          super
#        end
#      end

      def credentials=(value)
        super
        values = value.is_a?(Array) ? value : [value]
        if values.first.is_a?(Hash)
          values.first.with_indifferent_access.slice(login_field, password_field).each do |field, value|
            next if value.blank?
            send("#{field}=", value)
          end
        end
      end

      private

      # Main session validation using Crowd user token.
      # Uses simple_crowd to verify the user token on the configured crowd server
      # If no *local* user is found and auto_register is enabled (default) then automatically create *local* user for them
      # TODO: Cleanup and figure out reason for duplicate calls
      def validate_by_crowd
        begin
        load_crowd_app_token
        login = send(login_field) || unauthorized_record.andand.login
        password = send("protected_#{password_field}")
        params_user_token = controller.params["crowd.token_key"]
        session_user_token = controller.session[:"crowd.token_key"]
        cookie_user_token = sso? && controller.cookies[:"crowd.token_key"]
        user_token = crowd_user_token

        # Lets see if the user passed in an email or a login using the db
        if !login.blank? && self.unauthorized_record.nil?
          self.unauthorized_record = klass.send(:login_or_email_equals, login).first
          # If passed in login equals the user email then get the REAL login used by crowd instead
          login = unauthorized_record.login if !unauthorized_record.nil? && login = unauthorized_record.email
        end

        if user_token && crowd_client.is_valid_user_token?(user_token)
        elsif login && password
          # Authenticate if we don't have token
          user_token = crowd_client.authenticate_user login, password
        else
          user_token = nil
        end

        raise "No user token" if user_token.blank?

        login = crowd_client.find_username_by_token user_token unless login && 
                (!cookie_user_token || session_user_token == cookie_user_token) &&
                (!params_user_token || session_user_token == params_user_token)
        
        self.class.crowd_user_token = user_token
        
        if !self.unauthorized_record.nil? && self.unauthorized_record.login == login
          self.attempted_record = self.unauthorized_record
        else
          self.attempted_record = klass.send(:"find_by_#{login_field}", login)
        end

        if !attempted_record
          # If auto_register enabled then create new user with crowd info
          if auto_register?
            crowd_user = crowd_client.find_user_by_token user_token
            self.attempted_record = klass.new :login => crowd_user.username, :email => crowd_user.email
            self.new_registration = true
            self.attempted_record.crowd_record = crowd_user
            # TODO: Pull Crowd data for intial user
            self.attempted_record.save_without_session_maintenance
          else
            errors.add_to_base("We did not find any accounts with that login. Enter your details and create an account.")
            return false
          end
        end
        rescue Exception => e
          errors.add_to_base("Authentication failed. Please try again")
          # Don't know why it doesn't work the first time,
          # but if we nil the session key here then the session doesn't get deleted
          # Leaving the token triggers the validation a second time and successfully destroys the session
          # REMOVED AS HACK
          # Hack to fix user_credentials not being deleted on session destroy
          controller.session[:"crowd.token_key"] = nil
          unless (send(login_field) || unauthorized_record.andand.login && send("protected_#{password_field}"))
            controller.current_user_session.destroy
            controller.session.clear
          end
          controller.cookies.delete :user_credentials
          controller.cookies.delete :"crowd.token_key", :domain => crowd_cookie_info[:domain] if sso?
          false
        end
      end

      def sync_with_crowd
        # If it's a new registration then the crowd data was just pulled, so skip syncing on login
        unless new_registration? || !self.attempted_record
          login = send(login_field) || (!attempted_record.nil? && attempted_record.login)
          user_token = controller.params["crowd.token_key"] || controller.cookies[:"crowd.token_key"] || controller.session[:"crowd.token_key"]
          crowd_user = if login
            crowd_client.find_user_by_name login
          elsif user_token
            crowd_client.find_user_by_token user_token
          end
          if crowd_user && before_sync
            self.crowd_record = crowd_user
            # Callbacks to sync data
            sync
            self.attempted_record.save
            after_sync
          end
        end
      end

      # Single Sign-out
      def logout_of_crowd
        # Send an invalidate call for single signout
        # Apparently there is no way of knowing if this was successful or not.
        crowd_client.invalidate_user_token crowd_user_token unless crowd_user_token.nil?
        # Remove cookie and session
        controller.session[:"crowd.token_key"] = nil
        controller.cookies.delete :"crowd.token_key", :domain => crowd_cookie_info[:domain] if sso?
        controller.cookies.delete :user_credentials
        true
      end


      def crowd_user_token
        self.class.crowd_user_token
      end
      def crowd_client
        @crowd_client ||= SimpleCrowd::Client.new(crowd_config)
      end
      def load_crowd_app_token
        cached_token = Rails.cache.read('crowd_app_token')
        crowd_client.app_token = cached_token unless cached_token.nil?
        Rails.cache.write('crowd_app_token', crowd_client.app_token) unless cached_token == crowd_client.app_token
      end
      def crowd_cookie_info
        unless @crowd_cookie_info
          cached_info = Rails.cache.read('crowd_cookie_info')
          @crowd_cookie_info ||= cached_info || crowd_client.get_cookie_info
          Rails.cache.write('crowd_cookie_info', @crowd_cookie_info) unless cached_info == @crowd_cookie_info
        end
        @crowd_cookie_info
      end
      def crowd_config
        {:service_url => klass.crowd_service_url,
          :app_name => klass.crowd_app_name,
          :app_password => klass.crowd_app_password}
      end
    end
  end
end