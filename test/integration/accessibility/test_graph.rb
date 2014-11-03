require 'test/integration/helper'
require 'accessibility/graph'

class TestAccessibilityGraph < Minitest::Test

  def test_generate
    skip 'graphs are broken right now'
    p = Accessibility::Graph.new(app.main_window).generate_png!
    assert File.exists? p
    assert_match /^PNG image/, `file --brief #{p}`
  end

end
