# -*- coding: utf-8 -*-
module AX

##
# Some additional constructors and conveniences for Application objects.
class Application < AX::Element

  class << self

    ##
    # @todo Find a way for this method to work without sleeping;
    #       consider looping begin/rescue/end until AX starts up
    # @todo Search NSWorkspace.sharedWorkspace.runningApplications ?
    # @todo add another app launching method using app names
    #
    # This is the standard way of creating an application object. It will
    # launch the app if it is not already running and then create the
    # accessibility object.
    #
    # However, this method is a HUGE hack in cases where the app is not
    # already running; I've tried to register for notifications, launch
    # synchronously, etc., but there is always a problem with accessibility
    # not being ready. Hopefully this problem will go away on Lion...
    #
    # @param [String] bundle
    # @param [Float] timeout how long to wait between polling
    # @return [AX::Application]
    def application_with_bundle_identifier bundle, sleep_time = 2
      AX.application_for_bundle_identifier(bundle, sleep_time)
    end

  end


  ##
  ##
  # @todo return the element for the window?
  #
  # A macro for showing the About window for an app.
  def show_about_window
    self.set_focus
    Kernel.press self.menu_bar_item(title:(self.title))
    Kernel.press self.menu_bar.menu_item(title: "About #{self.title}")
  end

  ##
  # @todo return the element for the window?
  # @todo handle cases where an app has no prefs?
  #
  # A macro for showing the About window for an app.
  def show_preferences_window
    self.set_focus
    Kernel.press self.menu_bar_item(title:(self.title))
    Kernel.press self.menu_bar.menu_item(title:'Preferences…')
  end

  ##
  # Overriden to handle the {#set_focus} case.
  def set_attribute attr, value
    return set_focus if attr == :focused
    return super
  end

  ##
  # Override the base class to make sure the pid is included.
  def inspect
    (super).sub />$/, " @pid=#{self.pid}>"
  end

  def post_kb_string string
    AX.post_kb_string( @ref, string )
  end


  private

  ##
  # @todo This method needs a fall back procedure if the app does not
  #       have a dock icon (i.e. the dock doesn't have a dock icon)
  def set_focus
    AX::DOCK.application_dock_item(title: title).perform_action(:press)
  end

end
end
