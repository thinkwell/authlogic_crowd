module AuthlogicCrowd
  module ActsAsAuthenticCallbacks
    METHODS = [
      # Fired when a local record is synced from a crowd record (usually on login)
      "before_sync_from_crowd", "sync_from_crowd", "after_sync_from_crowd",

      # Fired when a new local record is created by crowd (usually because a
      # user logged in using crowd credentials)
      "before_create_from_crowd", "after_create_from_crowd",

      # Fired when a local record is synced to a crowd record (usually when creating a local record)
      "before_sync_to_crowd", "sync_to_crowd", "after_sync_to_crowd",

      # Fired when a creating a new crowd record (usually because a new local
      # record was created)
      "before_create_crowd_record", "after_create_crowd_record",
    ]

    def self.included(klass)
      klass.define_callbacks *METHODS
    end

    private
    METHODS.each do |method|
      class_eval <<-"end_eval", __FILE__, __LINE__
        def #{method}
          run_callbacks(:#{method}) { |result, object| result == false }
        end
      end_eval
    end
  end
end
