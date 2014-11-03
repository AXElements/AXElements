require 'active_support/core_ext'
require 'accessibility/bridge'
require 'ax_elements/mri'

# Mix the language methods into the TopLevel
require 'accessibility/dsl'
include Accessibility::DSL

require 'accessibility/system_info'

##
# @deprecated Please use {AX::Application.dock} instead
#
# The Mac OS X dock application.
#
# @return [AX::Application]
AX::DOCK = AX::Application.dock

# Load explicitly defined elements that are optional
require 'ax/button'
require 'ax/radio_button'
require 'ax/row'
require 'ax/static_text'
require 'ax/pop_up_button'

# Misc things that we need to load
require 'ax_elements/nsarray_compat'
