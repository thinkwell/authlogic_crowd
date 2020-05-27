module AuthlogicCrowd
  module ActsAsAuthenticCallbacks
    METHODS = [
      # Fired when a local record is synced from a crowd record (usually on login)
      "before_sync_from_yolk", "sync_from_yolk", "after_sync_from_yolk",

      # Fired when a new local record is created by crowd (usually because a
      # user logged in using crowd credentials)
      "before_create_from_yolk", "after_create_from_yolk",

      # Fired when a local record is synced to a crowd record (usually when creating a local record)
      "before_sync_to_yolk", "sync_to_yolk", "after_sync_to_yolk",

      # Fired when a creating a new crowd record (usually because a new local
      # record was created)
      "before_create_yolk_record", "after_create_yolk_record",
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
