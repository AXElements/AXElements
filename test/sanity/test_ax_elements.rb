require 'test/helper'
require 'ax_elements'

class TestDefaults < Minitest::Test

  def test_dock_constant_is_set
    assert_instance_of AX::Application, AX::DOCK
    assert_equal 'Dock', AX::DOCK.title
  end

end
