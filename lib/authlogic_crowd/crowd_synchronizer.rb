module AuthlogicCrowd
  class CrowdSynchronizer

    attr_accessor :klass, :crowd_client, :local_record

    def initialize(klass, crowd_client, local_record=nil, crowd_record=nil)
      self.klass = klass
      self.crowd_client = crowd_client
      self.local_record = local_record if local_record
      self.crowd_record = crowd_record if crowd_record
      @syncing = false
    end

    def local_record=(val)
      @local_record = val
      @local_record.crowd_synchronizer = self if @local_record
      @local_record.crowd_record = @crowd_record if @local_record && @crowd_record
    end

    def crowd_record
      @crowd_record ||= @local_record.crowd_record if @local_record
      @crowd_record
    end

    def crowd_record=(val)
      @crowd_record = val
      @local_record.crowd_record = @crowd_record if @local_record
    end

    def create_crowd_record
      if local_record.before_create_crowd_record
        self.crowd_record = SimpleCrowd::User.new({:username => send(local_record.send(klass.login_field))})
        if sync_to_crowd(true)
          after_create_crowd_record
          return crowd_record
        end
      end
      nil
    end

    def sync_to_crowd(new_record=false)
      return unless local_record && crowd_record
      return if @syncing

      if local_record.before_sync_to_crowd
        @syncing = true
        begin
          local_record.sync_to_crowd
          if crowd_record.dirty?
            crowd_client_with_app_token do |crowd_client|
              if new_record
                crowd_client.add_user crowd_record, local_record.crowd_password
              else
                crowd_client.update_user crowd_record
              end
            end
          end
        ensure
          @syncing = false
        end
        local_record.after_sync_to_crowd
        return true
      end
      false
    end

    def create_record_from_crowd
      self.local_record = klass.new
      if local_record.before_create_from_crowd
        local_record.send(:"#{klass.login_field}=", crowd_record.username) if local_record.respond_to?(:"#{klass.login_field}=")
        sync_from_crowd
        if local_record.save_without_session_maintenance
          local_record.after_create_from_crowd
          return local_record
        end
      end
      nil
    end

    def sync_from_crowd
      return unless local_record && crowd_record
      return if @syncing

      if local_record.before_sync_from_crowd
        @syncing = true
        begin
          local_record.sync_from_crowd
          local_record.save_without_session_maintenance if local_record.changed?
        ensure
          @syncing = false
        end
        local_record.after_sync_from_crowd
      end
    end

    def crowd_client_with_app_token(&block)
      klass.crowd_client_with_app_token(crowd_client, &block)
    end
  end
end
