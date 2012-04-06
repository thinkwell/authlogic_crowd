module AuthlogicCrowd
  module ActsAsAuthentic
    # Adds in the neccesary modules for acts_as_authentic to include and also disabled password validation if
    # Crowd is being used.
    def self.included(klass)
      klass.class_eval do
        extend Config
        extend ClassMethods
        add_acts_as_authentic_module(Methods)
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

      def crowd_enabled(value=nil)
        rw_config(:crowd_enabled, value, true)
      end
      alias_method :crowd_enabled=, :crowd_enabled
    end

    module ClassMethods
      def crowd_config
        {
          :service_url => crowd_service_url,
          :app_name => crowd_app_name,
          :app_password => crowd_app_password,
        }
      end

      def crowd_client
        SimpleCrowd::Client.new(crowd_config)
      end

      def crowd_app_token(crowd_client=self.crowd_client)
        return crowd_client.app_token if crowd_client.app_token
        Rails.cache.fetch('crowd_app_token') do
          # Strings returned by crowd contain singleton methods which cannot
          # be serialized into the Rails.cache.  Duping the strings removes the
          # singleton methods.
          crowd_client.app_token = crowd_client.authenticate_application
          crowd_client.app_token.dup
        end
      end

      def crowd_cookie_info(crowd_client=self.crowd_client)
        Rails.cache.fetch('crowd_cookie_info') do
          # Strings returned by crowd contain singleton methods which cannot
          # be serialized into the Rails.cache.  Do a shallow dup of each string
          # in the returned hash
          crowd_client.get_cookie_info.inject({}) do |cookie_info, (key, val)|
            cookie_info[key] = val ? val.dup : val
            cookie_info
          end
        end
      end

      # Set the crowd_client.app_token and execute the given block.  After the block
      # executes, cache the new app token if it changed.
      def crowd_client_with_app_token(crowd_client=self.crowd_client, crowd_app_token=nil)
        crowd_app_token = self.crowd_app_token(crowd_client) unless crowd_app_token
        crowd_client.app_token = crowd_app_token
        res = yield(crowd_client) if block_given?
        if (new_app_token = crowd_client.app_token) != crowd_app_token
          Rails.cache.write('crowd_app_token', new_app_token.dup)
        end
        res
      end

      def crowd_enabled?
        !!self.crowd_enabled
      end

      def using_crowd?
        self.crowd_enabled? && !(self.crowd_app_name.nil? || self.crowd_app_password.nil? || self.crowd_service_url.nil?)
      end
    end

    module Methods
      def self.included(klass)
        klass.class_eval do
          #validate_on_create :must_have_unique_crowd_login, :if => :using_crowd?, :unless => :crowd_record

          # TODO: Cleanup and refactor into callbacks
          #def create
          #  if using_crowd? && !crowd_record
          #    crowd_user = self.create_crowd_user
          #    if crowd_user
          #      # Crowd is going to store password so clear them from local object
          #      self.clear_passwords
          #      result = super
          #      # Delete crowd user if local creation failed
          #      crowd_client.delete_user crowd_user.user unless result
          #      if result
          #        user_token = crowd_client.create_user_token crowd_user.username
          #        session_class.crowd_user_token = user_token unless
          #            session_class.controller && session_class.controller.session[:"crowd.token_key"]
          #      end
          #      return result
          #    end
          #  end
          #  super
          #end
          validates_length_of_password_field_options validates_length_of_password_field_options.merge(:on => :create)
          validates_confirmation_of_password_field_options validates_confirmation_of_password_field_options.merge(:on => :create)
          validates_length_of_password_confirmation_field_options validates_length_of_password_confirmation_field_options.merge(:on => :create)
        end
      end

      #attr_accessor :crowd_record

      def crowd_client
        @crowd_client ||= self.class.crowd_client
      end

      protected

      #def create_crowd_user
      #  return unless self.login && @password
      #  self.crowd_record = SimpleCrowd::User.new({:username => self.login})
      #  sync_on_create
      #  crowd_client.add_user self.crowd_record, @password
      #end

      #def clear_passwords
      #  @password = nil
      #  @password_changed = false
      #  send("#{self.class.crypted_password_field}=", nil) if self.class.crypted_password_field
      #  send("#{self.class.password_salt_field}=", nil) if self.class.password_salt_field
      #end

      private

      #def must_have_unique_crowd_login
      #  login = send(self.class.login_field)
      #  crowd_user = crowd_client.find_user_by_name(login)
      #  errors.add(self.class.login_field, "is already taken") unless crowd_user.nil? || !errors.on(self.class.login_field).nil?
      #end


      #def load_crowd_app_token
      #  cached_token = Rails.cache.read('crowd_app_token')
      #  crowd_client.app_token = cached_token unless cached_token.nil?
      #  Rails.cache.write('crowd_app_token', crowd_client.app_token) unless cached_token == crowd_client.app_token
      #end
      #def crowd_cookie_info
      #  unless @crowd_cookie_info
      #    cached_info = Rails.cache.read('crowd_cookie_info')
      #    @crowd_cookie_info ||= cached_info || crowd_client.get_cookie_info
      #    Rails.cache.write('crowd_cookie_info', @crowd_cookie_info) unless cached_info == @crowd_cookie_info
      #  end
      #  @crowd_cookie_info
      #end

      def using_crowd?
        self.class.using_crowd?
      end

      #def validate_password_with_crowd?
      #  #!using_crowd? && require_password?
      #end
    end
  end
end
