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

      # Should changes to local records be synced to crowd?
      # Default is true
      def update_crowd_records(value=nil)
        rw_config(:update_crowd_records, value, true)
      end
      alias_method :update_crowd_records=, :update_crowd_records

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
          :cache_store => Rails.cache,
        }
      end

      def crowd_client
        SimpleCrowd::Client.new(crowd_config)
      end

      def crowd_synchronizer(crowd_client=self.crowd_client, local_record=nil)
        CrowdSynchronizer.new(self, crowd_client, local_record)
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

          after_create(:if => [:using_crowd?, :adding_crowd_records?], :unless => :has_crowd_record?) do |r|
            r.crowd_synchronizer.create_crowd_record
          end

          before_update :crowd_before_update_reset_password, :if => [:using_crowd?, :updating_crowd_records?, :has_crowd_record?]

          after_update(:if => [:using_crowd?, :updating_crowd_records?, :has_crowd_record?]) do |r|
            r.crowd_synchronizer.sync_to_crowd
          end

          validate_on_create :must_have_unique_crowd_login, :if => [:using_crowd?, :adding_crowd_records?], :unless => :has_crowd_record?
        end
      end

      attr_accessor :crowd_record, :crowd_synchronizer

      def crowd_client
        @crowd_client ||= self.class.crowd_client
      end

      def crowd_synchronizer
        @crowd_synchronizer ||= self.class.crowd_synchronizer(crowd_client, self)
      end

      def crowd_record
        return nil unless using_crowd?
        if @crowd_record.nil?
          @crowd_record = false
          begin
            login = self.send(self.class.login_field)
            record = crowd_client.find_user_by_name(login)
            @crowd_record = record if record
          rescue SimpleCrowd::CrowdError => e
            Rails.logger.warn "CROWD[#{__method__}]: Unexpected error.  #{e}"
          end
        end
        @crowd_record == false ? nil : @crowd_record
      end

      def using_crowd?
        self.class.using_crowd?
      end

      def adding_crowd_records?
        self.class.add_crowd_records
      end

      def updating_crowd_records?
        self.class.update_crowd_records
      end

      def has_crowd_record?
        !!self.crowd_record
      end

      def crowd_password
        password
      end

      def crowd_password_changed?
        password_changed?
      end

      def valid_crowd_password?(plaintext_password)
        if using_crowd?
          begin
            token = crowd_client.authenticate_user(self.unique_id, plaintext_password)
            return true if token
          rescue SimpleCrowd::CrowdError => e
            Rails.logger.warn "CROWD[#{__method__}]: Unexpected error.  #{e}"
          end
        end
        false
      end


      private

      def must_have_unique_crowd_login
        login = send(self.class.login_field)
        crowd_user = crowd_client.find_user_by_name(login)
        errors.add(self.class.login_field, "is already taken") unless crowd_user.nil? || !errors.on(self.class.login_field).nil?
      end

      def crowd_before_update_reset_password
        if crowd_password_changed?
          send("#{password_salt_field}=", nil) if password_salt_field
          send("#{crypted_password_field}=", nil)
        end
      end
    end
  end
end
