module AuthlogicCrowd
  module ActsAsAuthentic
    # Adds in the neccesary modules for acts_as_authentic to include and also disabled password validation if
    # Yolk is being used.
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
      # Specify your yolk endpoint.
      # @param [String] endpoint to use when calling Yolk
      def yolk_endpoint(url=nil)
        rw_config(:yolk_endpoint, url, "http://yolk.local.thinkwell.com")
      end
      alias_method :yolk_endpoint=, :yolk_endpoint

      # **REQUIRED**
      #
      # Specify your yolk key.
      # @param [String] key to use when calling Yolk
      def yolk_key(name=nil)
        rw_config(:yolk_key, name, nil)
      end
      alias_method :yolk_key=, :yolk_key

      # **REQUIRED**
      #
      # Specify your yolk secret.
      # @param [String] Plain-text key for yolk validation
      def yolk_secret(secret=nil)
        rw_config(:yolk_secret, secret, nil)
      end
      alias_method :yolk_secret=, :yolk_secret

      def yolk_cookie_domain(domain=nil)
        rw_config(:yolk_cookie_domain, domain, ".thinkwell.com")
      end
      alias_method :yolk_cookie_domain=, :yolk_cookie_domain

      def yolk_cookie_secure(secure=nil)
        rw_config(:yolk_cookie_secure, secure, true)
      end
      alias_method :yolk_cookie_secure=, :yolk_cookie_secure

      # Should new local records be added to yolk?
      # Default is false.
      def add_yolk_records(value=nil)
        rw_config(:add_yolk_records, value, false)
      end
      alias_method :add_yolk_records=, :add_yolk_records

      # Should changes to local records be synced to yolk?
      # Default is true
      def update_yolk_records(value=nil)
        rw_config(:update_yolk_records, value, true)
      end
      alias_method :update_yolk_records=, :update_yolk_records

      def yolk_enabled(value=nil)
        rw_config(:yolk_enabled, value, true)
      end
      alias_method :yolk_enabled=, :yolk_enabled
    end

    module ClassMethods
      def yolk_config
        {
          :endpoint => yolk_endpoint,
          :key => yolk_key,
          :secret => yolk_secret,
          :cache_store => Rails.cache,
        }
      end

      def yolk_cookie_info
        {:domain => yolk_cookie_domain, :secure => yolk_cookie_secure}
      end

      def yolk_client
        Yolk::Client.new(yolk_config)
      end

      def yolk_synchronizer(yolk_client=self.yolk_client, local_record=nil)
        YolkSynchronizer.new(self, yolk_client, local_record)
      end

      def yolk_enabled?
        !!self.yolk_enabled
      end

      def using_yolk?
        self.yolk_enabled? && !(self.yolk_endpoint.nil? || self.yolk_key.nil? || self.yolk_secret.nil?)
      end
    end

    module Methods
      def self.included(klass)
        klass.class_eval do
          extend ClassMethods

          after_create(:if => [:using_yolk?, :adding_yolk_records?], :unless => :has_yolk_record?) do |r|
            r.yolk_synchronizer.create_yolk_record
          end

          before_update :yolk_before_update_reset_password, :if => [:using_yolk?, :updating_yolk_records?, :has_yolk_record?]

          after_update(:if => [:using_yolk?, :updating_yolk_records?, :has_yolk_record?]) do |r|
            r.yolk_synchronizer.sync_to_yolk
          end

          validate :must_have_unique_login, :on => :create, :if => [:using_yolk?, :adding_yolk_records?], :unless => :has_yolk_record?
        end
      end

      attr_accessor :yolk_record, :yolk_synchronizer

      def yolk_client
        @yolk_client ||= self.class.yolk_client
      end

      def yolk_synchronizer
        @yolk_synchronizer ||= self.class.yolk_synchronizer(yolk_client, self)
      end

      def yolk_record
        return nil unless using_yolk?
        if @yolk_record.nil?
          @yolk_record = false
          begin
            login = self.send(self.class.login_field)
            @yolk_record = yolk_client.get_user(login)
            Rails.logger.info "YOLK :: #{login} : got yolk record"
          rescue StandardError => e
            Rails.logger.info "YOLK :: #{login} : NO yolk record : #{e.message}"
          end
        end
        @yolk_record == false ? nil : @yolk_record
      end

      def using_yolk?
        self.class.using_yolk?
      end

      def adding_yolk_records?
        self.class.add_yolk_records
      end

      def updating_yolk_records?
        self.class.update_yolk_records
      end

      def has_yolk_record?
        !!self.yolk_record
      end

      def yolk_password
        password
      end

      def yolk_password_changed?
        password_changed?
      end

      def valid_yolk_password?(plaintext_password)
        if using_yolk?
          begin
            user = yolk_client.authenticate_user(self.unique_id, plaintext_password)
            Rails.logger.info "YOLK :: #{self.unique_id} : authenticated user" if user
            Rails.logger.info "YOLK :: #{self.unique_id} : NOT authenticated user" unless user
            return true if user
          rescue StandardError => e
            Rails.logger.warn "YOLK[#{__method__}]: Unexpected error.  #{e}"
          end
        end
        false
      end


      private

      def must_have_unique_login
        login = send(self.class.login_field)
        begin
          yolk_user = yolk_client.get_user(login)
          Rails.logger.info "YOLK :: #{login} : already exists"
          errors.add(self.class.login_field, "is already taken") unless yolk_user.nil? || !errors.on(self.class.login_field).nil?
        rescue StandardError => error
          Rails.logger.info "YOLK :: #{login} : is unique login"
        end
      end

      def yolk_before_update_reset_password
        if yolk_password_changed?
          send("#{password_salt_field}=", nil) if password_salt_field
          send("#{crypted_password_field}=", nil)
        end
      end
    end
  end
end
