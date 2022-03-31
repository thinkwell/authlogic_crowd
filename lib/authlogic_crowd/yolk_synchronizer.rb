module AuthlogicCrowd
  class YolkSynchronizer

    attr_accessor :klass, :yolk_client, :local_record

    def initialize(klass, yolk_client, local_record=nil, yolk_record=nil)
      self.klass = klass
      self.yolk_client = yolk_client
      self.local_record = local_record if local_record
      self.yolk_record = yolk_record if yolk_record
      @syncing = false
    end

    def local_record=(val)
      @local_record = val
      @local_record.yolk_synchronizer = self if @local_record
      @local_record.yolk_record = @yolk_record if @local_record && @yolk_record
    end

    def yolk_record
      @yolk_record ||= @local_record.yolk_record if @local_record
      @yolk_record
    end

    def yolk_record=(val)
      @yolk_record = val
      @local_record.yolk_record = @yolk_record if @local_record
    end

    def create_yolk_record
      if local_record.before_create_yolk_record
        self.yolk_record = Yolk::Models::User.new({:username => local_record.send(klass.login_field)})
        if sync_to_yolk(true)
          local_record.after_create_yolk_record
          return yolk_record
        end
      end
      nil
    end

    def sync_to_yolk(new_record=false)
      return unless local_record && yolk_record
      return if @syncing

      if local_record.before_sync_to_yolk
        @syncing = true
        begin
          local_record.sync_to_yolk
          user_attributes = yolk_record.to_h
          user_attributes.merge!({:password => local_record.yolk_password}) if local_record.yolk_password
          if new_record
            begin
              yolk_client.add_user user_attributes
              yolk_record.reset
              Rails.logger.info "YOLK_SYNC :: #{yolk_record.username} : added user : #{user_attributes.except(:password).inspect}"
            rescue StandardError => error
              Rails.logger.error "YOLK_SYNC :: #{yolk_record.username} : could not add user : #{error.message}"
            end
          else
            begin
              Rails.logger.info "YOLK_SYNC :: #{yolk_record.username} : updating user : #{user_attributes.inspect} ..."
              yolk_client.update_user yolk_record.username, user_attributes
              yolk_record.reset
              Rails.logger.info "YOLK_SYNC :: #{yolk_record.username} : updated user"
            rescue StandardError => error
              Rails.logger.error "YOLK_SYNC :: #{yolk_record.username} : could not update user : #{error.message}"
            end
          end
        ensure
          @syncing = false
        end
        local_record.after_sync_to_yolk
        return true
      end
      false
    end

    def create_record_from_yolk
      self.local_record = klass.new
      if local_record.before_create_from_yolk
        local_record.send(:"#{klass.login_field}=", yolk_record.username) if local_record.respond_to?(:"#{klass.login_field}=")
        sync_from_yolk
        if local_record.save_without_session_maintenance
          local_record.after_create_from_yolk
          return local_record
        end
      end
      nil
    end

    def sync_from_yolk
      return unless local_record && yolk_record
      return if @syncing

      if local_record.before_sync_from_yolk
        @syncing = true
        begin
          local_record.sync_from_yolk
          local_record.save_without_session_maintenance if local_record.changed?
        ensure
          @syncing = false
        end
        local_record.after_sync_from_yolk
      end
    end
  end
end
