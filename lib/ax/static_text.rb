require 'ax/element'

##
# Represents text on the screen that cannot directly be changed by
# a user, usually a label or an instructional text block.
class AX::StaticText < AX::Element

  ##
  # Test equality with another object. Equality can be with another
  # {AX::Element} or it can be with a string that matches the value
  # of the static text.
  #
  # @return [Boolean]
  def == other
    if other.kind_of? String
      attribute(:value) == other
    else
      super
    end
  end

end
