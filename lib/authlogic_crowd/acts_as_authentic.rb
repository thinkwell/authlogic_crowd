module AuthlogicCrowd
  module ActsAsAuthentic
    # Adds in the neccesary modules for acts_as_authentic to include and also disabled password validation if
    # Crowd is being used.
    def self.included(klass)
      klass.class_eval do
        extend Config
        add_acts_as_authentic_module(ActsAsAuthenticCallbacks)
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

      # Should new local records be added to crowd?
      # Default is false.
      def add_crowd_records(value=nil)
        rw_config(:add_crowd_records, value, false)
      end
      alias_method :add_crowd_records=, :add_crowd_records

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

      def crowd_synchronizer(crowd_client=self.crowd_client)
        CrowdSynchronizer.new(self, crowd_client)
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
          extend ClassMethods

          after_create(:if => [:using_crowd?, :adding_crowd_records?]) do |r|
            r.crowd_synchronizer.create_crowd_record unless r.crowd_record
          end

          validate_on_create :must_have_unique_crowd_login, :if => [:using_crowd?, :adding_crowd_records?], :unless => :crowd_record
        end
      end

      attr_accessor :crowd_record, :crowd_synchronizer

      def crowd_client
        @crowd_client ||= self.class.crowd_client
      end

      def crowd_client_with_app_token(&block)
        self.class.crowd_client_with_app_token(crowd_client, &block)
      end

      def crowd_synchronizer
        @crowd_synchronizer ||= self.class.crowd_synchronizer(crowd_client)
      end

      def crowd_password
        password
      end

      private

      def must_have_unique_crowd_login
        login = send(self.class.login_field)
        crowd_user = crowd_client_with_app_token do |crowd_client|
          crowd_client.find_user_by_name(login)
        end
        errors.add(self.class.login_field, "is already taken") unless crowd_user.nil? || !errors.on(self.class.login_field).nil?
      end

      def using_crowd?
        self.class.using_crowd?
      end

      def adding_crowd_records?
        self.class.after_create_add_crowd_record
      end
    end
  end
end
