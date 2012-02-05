# Functional and system tests for AXElements

class TestAccessibilityDSL < MiniTest::Unit::TestCase
  include Accessibility::Core

  # LSP FTW
  class DSL
    include Accessibility::DSL
  end

  class LanguageTest < AX::Element
    attr_reader :called_action
    def actions=  value; @actions       = value;  end
    def perform  action; @called_action = action; end
  end

  def dsl
    @dsl ||= DSL.new
  end

  def element
    @element ||= LanguageTest.new REF, attrs_for(REF)
  end

  def app
    @@app ||= AX::Application.new REF, attrs_for(REF)
  end

  def text_area
    @@text_area ||= app.main_window.text_area
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
    element.actions = ['AXPurpleRain']
    dsl.purple_rain element
    assert_equal :purple_rain, element.called_action

    assert_raises NoMethodError do
      dsl.hack element
    end
    assert_raises NoMethodError do
      dsl.purple_rain 'A string'
    end
  end

  def test_raise_can_still_raise_exception
    assert_raises ArgumentError do
      dsl.raise ArgumentError
    end
    assert_raises NoMethodError do
      dsl.raise NoMethodError
    end
  end

  def test_type
    def try string, expected = nil
      expected = string unless expected
      text_area.set :focused, to: true
      dsl.type string
      assert_equal expected, text_area.value
    ensure # reset for next test
      dsl.type "\\COMMAND+a \b"
    end

    try "A proper sentence, with punctuation and the number 9. LOL!\tA 'quoted' string--then some @#*$ cursing."
    try "The cake is a lie!\b\b\b\bgift!", 'The cake is a gift!'
    try ", world!\\CONTROL+a Hello", 'Hello, world!'
    try "Hai.\\<- \\<- \b", "Hi."
    try "First line.\nSecond line."
  end

  def test_dsl_is_mixed_into_toplevel
    assert_includes Object.new.class.ancestors, Accessibility::DSL
  end

end
