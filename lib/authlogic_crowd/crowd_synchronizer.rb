module AuthlogicCrowd
  class CrowdSynchronizer

    attr_accessor :klass, :crowd_client

    def initialize(klass, crowd_client)
      self.klass = klass
      self.crowd_client = crowd_client
    end

    def create_crowd_record(local_record)
      local_record.crowd_synchronizer = self
      if local_record.before_create_crowd_record
        crowd_record = SimpleCrowd::User.new({:username => send(local_record.send(klass.login_field))})
        if sync_to_crowd(local_record, crowd_record, true)
          after_create_crowd_record
          return crowd_record
        end
      end
      nil
    end

    def sync_to_crowd(local_record, crowd_record, new_record=false)
      return unless local_record && crowd_record

      local_record.crowd_record = crowd_record
      local_record.crowd_synchronizer = self
      if local_record.before_sync_to_crowd
        local_record.sync_to_crowd
        # TODO: Sync to crowd
        crowd_client_with_app_token do |crowd_client|
          if new_record
            crowd_client.add_user crowd_record, local_record.crowd_password
          else
            crowd_client.update_user crowd_record
          end
        end
        local_record.after_sync_to_crowd
        return true
      end
      false
    end

    def create_record_from_crowd(crowd_record)
      local_record = klass.new
      local_record.crowd_record = crowd_record
      local_record.crowd_synchronizer = self
      if local_record.before_create_from_crowd
        local_record.send(:"#{klass.login_field}=", crowd_record.username) if local_record.respond_to?(:"#{klass.login_field}=")
        sync_from_crowd(crowd_record, local_record)
        if local_record.save_without_session_maintenance
          local_record.after_create_from_crowd
          return local_record
        end
      end
      nil
    end

    def sync_from_crowd(crowd_record, local_record)
      return unless local_record && crowd_record

      local_record.crowd_record = crowd_record
      local_record.crowd_synchronizer = self
      if local_record.before_sync_from_crowd
        local_record.sync_from_crowd
        local_record.after_sync_from_crowd
      end
    end

    def crowd_client_with_app_token(&block)
      klass.crowd_client_with_app_token(crowd_client, &block)
    end
  end
end
