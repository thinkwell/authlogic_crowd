require "authlogic/test_case"
require "test_helper"

module AuthlogicCrowd
  class SessionTest < ActiveSupport::TestCase

    def test_user_credentials
      ben = users(:ben)
      assert_nil controller.session["user_credentials"]
      assert UserSession.create(ben)
      assert_equal controller.session["user_credentials"], ben.persistence_token
    end
  end
end
