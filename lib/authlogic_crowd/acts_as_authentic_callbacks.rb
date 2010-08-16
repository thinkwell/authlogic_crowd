module AuthlogicCrowd
  module ActsAsAuthenticCallbacks
    def self.included(klass)
      klass.class_eval do
        add_acts_as_authentic_module(Methods, :prepend)
      end
    end
    module Methods
      METHODS = [
        "sync_on_create"
      ]
      def self.included(base)
        base.send :include, ActiveSupport::Callbacks
        base.define_callbacks *METHODS
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
end