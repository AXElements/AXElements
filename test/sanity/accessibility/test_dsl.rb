require 'test/fixture_app'
require 'test/helper'
require 'accessibility/dsl'

class TestAccessibilityDSL < Minitest::Test

  # LSP FTW
  class DSL
    include Accessibility::DSL
  end

  class LanguageTest < AX::Element
    attr_reader :called_action
    def actions=  value; @actions       = value  end
    def actions;         @actions                end
    def perform  action; @called_action = action end
    def search    *args; @search_args   = args   end
  end

  def dsl
    @dsl ||= DSL.new
  end

  def element
    @element ||= LanguageTest.new REF
  end


  def test_static_actions
    def static_action action
      dsl.send action, element
      assert_equal action, element.called_action
    end

    static_action :press
    static_action :show_menu
    static_action :pick
    static_action :decrement
    static_action :confirm
    static_action :increment
    static_action :delete
    static_action :cancel
    static_action :hide
    static_action :unhide
    static_action :terminate
    static_action :raise
  end

  def test_method_missing_forwards
    element.actions = [:purple_rain]
    dsl.purple_rain element
    assert_equal :purple_rain, element.called_action

    e = assert_raises(ArgumentError) { dsl.hack element }
    assert_match /.hack. is not an action/, e.message

    e = assert_raises(NoMethodError) { dsl.purple_rain 'A string' }
    assert_match /undefined method/, e.message
  end

  def test_raise_can_still_raise_exception
    assert_raises(ArgumentError) { dsl.raise ArgumentError }
    assert_raises(NoMethodError) { dsl.raise NoMethodError }
  end

  def test_wait_for_demands_a_parent_or_ancestor
    assert_raises(ArgumentError) { dsl.wait_for :bacon }
  end

  def test_wait_for_allows_filtering_by_parent
    result = dsl.wait_for(:dude, parent: :hippie, ancestor: element)
    assert_equal [:dude, { parent: :hippie }], result
  end

end
