module AuthlogicCrowd
  module ActsAsAuthentic
    # Adds in the neccesary modules for acts_as_authentic to include and also disabled password validation if
    # OpenID is being used.
    def self.included(klass)
      klass.class_eval do
        extend Config
        add_acts_as_authentic_module(Methods, :prepend)
      end
    end
    module Config

    end
    module Methods
      def self.included(klass)
        klass.class_eval do
          #validates_length_of_password_field_options validates_length_of_password_field_options.merge(:if => :validate_password_with_crowd?)
          #validates_confirmation_of_password_field_options validates_confirmation_of_password_field_options.merge(:if => :validate_password_with_crowd?)
          #validates_length_of_password_confirmation_field_options validates_length_of_password_confirmation_field_options.merge(:if => :validate_password_with_crowd?)
        end
      end

      private

      def using_crowd?
        #respond_to?(:crowd_token) && !crowd_token.blank?
      end

      def validate_password_with_crowd?
        #!using_crowd? && require_password?
      end
    end
  end
end