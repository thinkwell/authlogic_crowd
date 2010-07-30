module AuthlogicCrowd
  module Session
    def self.included(klass)
      klass.class_eval do
        extend Config
        include Methods
      end
    end
    module Config
      # **REQUIRED**
      #
      # Specify your crowd service url.
      # @param [String] url to use when calling Crowd
      def crowd_service_url(url=nil)
        rw_config(:crowd_service_url, url, "http://localhost:8095/crowd/services/SecurityServer")
      end
      alias_method :crowd_service_url=, :crowd_service_url

      # **REQUIRED**
      #
      # Specify your crowd app name.
      # @param [String] name of app to use when calling Crowd
      def crowd_app_name(name=nil)
        rw_config(:crowd_app_name, name, nil)
      end
      alias_method :crowd_app_name=, :crowd_app_name

      # **REQUIRED**
      #
      # Specify your crowd app password.
      # @param [String] password Plain-text password for crowd app validation
      def crowd_app_password(password=nil)
        rw_config(:crowd_app_password, password, nil)
      end
      alias_method :crowd_app_password=, :crowd_app_password

      def crowd_user_token_field(value = nil)
        rw_config(:crowd_user_token_field, value, :crowd_user_token)
      end
      alias_method :crowd_user_token_field=, :crowd_user_token_field
    end
    module Methods
      def self.included(klass)
        klass.class_eval do
          attr_accessor :new_registration
          validate :validate_by_crowd, :if => :authenticating_with_crowd?
          before_destroy :logout_of_crowd, :if => :authenticating_with_crowd?
        end
      end

      def initialize(*args)
        if crowd_user_token_field
          self.class.send(:attr_writer, crowd_user_token_field) if !respond_to?("#{crowd_user_token_field}=")
          self.class.send(:attr_reader, crowd_user_token_field) if !respond_to?(crowd_user_token_field)
        end
        super *args
      end

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

      protected

      # Determines whether to use crowd to authenticate and validate the current request
      # For now we assume the app wants to use Crowd exclusively.
      # TODO: Add flexibility regarding multiple authentication methods and identity mapping
      def authenticating_with_crowd?
        errors.empty? &&
        !self.class.crowd_app_name.blank? &&
        !self.class.crowd_app_password.blank? &&
        (login_field && (!send(login_field).nil? || !send("protected_#{password_field}").nil?) ||
          controller.cookies[:"crowd.token_key"] || controller.session[:"crowd.token_key"])
      end

      def authenticating_with_password?
        !authenticating_with_crowd? && login_field && (!send(login_field).nil? || !send("protected_#{password_field}").nil?)
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
      # TODO: Create user on crowd side if nonexistant(?)
      def validate_by_crowd
        begin
        load_crowd_app_token
        login = send(login_field)
        password = send("protected_#{password_field}")
        session_user_token = controller.session[:"crowd.token_key"]
        cookie_user_token = controller.cookies[:"crowd.token_key"]
        user_token = session_user_token || cookie_user_token

        if user_token && crowd_client.is_valid_user_token?(user_token)
        elsif login && password
          # Authenticate if we don't have token
          user_token = crowd_client.authenticate_user login, password
        else
          user_token = nil
        end

        if user_token.blank?
          errors.add_to_base("Authentication failed. Please try again.")
          return false
        end

        login = crowd_client.find_user_name_by_token user_token unless login

        send(:"#{crowd_user_token_field}=", user_token) if send(crowd_user_token_field).nil?
        controller.session[:"crowd.token_key"] = user_token unless session_user_token == user_token
        controller.cookies[:"crowd.token_key"] = {:domain => crowd_cookie_info[:domain],
                                                  :secure => crowd_cookie_info[:secure],
                                                  :value => user_token} unless cookie_user_token == user_token
        
        if !self.unauthorized_record.nil? && self.unauthorized_record.login == login
          self.attempted_record = self.unauthorized_record
        else
          self.attempted_record = klass.send(:"find_by_#{login_field}", login)
        end

        if !attempted_record
          errors.add_to_base("We did not find any accounts with that login. Enter your details and create an account.")
          return false
        end
        rescue Exception => e
          errors.add_to_base("Authentication failed. Please try again")
          return false
        end
      end

      def logout_of_crowd
        # Send an invalidate call
        # Apparently there is no way of knowing if this was successful or not.
        crowd_client.invalidate_user_token crowd_user_token unless crowd_user_token.nil?
        # Remove cookie and session
        controller.session[:"crowd.token_key"] = nil
        controller.cookies.delete :"crowd.token_key", :domain => crowd_cookie_info[:domain]
      end

      def crowd_client
        @crowd_client ||= SimpleCrowd::Client.new(crowd_config)
      end
      def crowd_user_token
        controller.session[:"crowd.token_key"]|| controller.cookies[:"crowd.token_key"] || send(crowd_user_token_field)
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
        {:service_url => self.class.crowd_service_url,
          :app_name => self.class.crowd_app_name,
          :app_password => self.class.crowd_app_password}
      end
      def crowd_user_token_field; self.class.crowd_user_token_field; end
    end
  end
end