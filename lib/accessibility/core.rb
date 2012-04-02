# -*- coding: utf-8 -*-

framework 'Cocoa'

# check that the Accessibility APIs are enabled and are available to MacRuby
begin
  unless AXAPIEnabled()
    raise RuntimeError, <<-EOS
------------------------------------------------------------------------
Universal Access is disabled on this machine.

Please enable it in the System Preferences.
------------------------------------------------------------------------
    EOS
  end
rescue NoMethodError
  raise NotImplementedError, <<-EOS
------------------------------------------------------------------------
You need to install the latest BridgeSupport preview so that AXElements
has access to CoreFoundation.
------------------------------------------------------------------------
  EOS
end


require 'accessibility/version'

##
# @todo I feel a bit weird having to instantiate a new pointer every
#       time I want to fetch an attribute. Since allocations are costly,
#       it hurts performance a lot when it comes to searches. I wonder if
#       it would pay off to have a pool of pointers...
#
# Core abstraction layer that that interacts with OS X Accessibility
# APIs (AXAPI). You can just mix this module in wherever you want to add
# some accessibility calls. The class that this is mixed into needs to
# have an attribute named `@ref` which is an `AXUIElementRef` object.
#
# This module is responsible for handling pointers and dealing with error
# codes for functions that make use of them. The methods in this module
# provide a clean Ruby-ish interface to the low level CoreFoundation
# functions that compose AXAPI. In doing this, we can hide away the need
# to work with pointers and centralize how AXAPI related errors are handled
# (since CoreFoundation uses a different pattern for that sort of thing).
#
# @example
#
#   class Element
#     include Accessibility::Core
#
#     def initialize ref
#       @ref = ref
#     end
#   end
#
#   Element.new AXUIElementCreateSystemWide()
#   Element.attributes           # => ["AXRole", "AXChildren", ...]
#   Element.size_of "AXChildren" # => 12
#
module Accessibility::Core


  # @group Attributes

  ##
  # @todo Invalid elements do not always raise an error.
  #       This is a bug that should be logged with Apple.
  #
  # Get the list of attributes for the element. As a convention, this
  # method will return an empty array if the backing element is no longer
  # alive.
  #
  # @example
  #
  #   attributes # => ["AXRole", "AXRoleDescription", ...]
  #
  # @return [Array<String>]
  def attributes
    ptr = Pointer.new ARRAY
    case code = AXUIElementCopyAttributeNames(@ref, ptr)
    when 0                        then ptr.value
    when KAXErrorInvalidUIElement then []
    else handle_error code
    end
  end

  ##
  # Fetch the value for an attribute. CoreFoundation wrapped objects
  # will be unwrapped for you, if you expect to get a {CFRange} you
  # will be given a {Range} instead.
  #
  # As a convention, if the backing element is no longer alive then
  # you will receive `nil` for any attribute.
  #
  # @example
  #   attribute KAXTitleAttribute   # => "HotCocoa Demo"
  #   attribute KAXSizeAttribute    # => #<CGSize width=10.0 height=88>
  #   attribute KAXParentAttribute  # => #<AXUIElementRef>
  #   attribute KAXNoValueAttribute # => nil
  #
  # @param [String] name an attribute constant
  def attribute name
    ptr = Pointer.new :id
    case code = AXUIElementCopyAttributeValue(@ref, name, ptr)
    when 0                                         then ptr.value.to_ruby
    when KAXErrorNoValue, KAXErrorInvalidUIElement then nil
    when KAXErrorFailure
      name == KAXChildrenAttribute ? [] : handle_error(code, name)
    else handle_error code, name
    end
  end

  ##
  # Shortcut for getting the `KAXRoleAttribute`.
  #
  # @example
  #
  #   role  # => KAXWindowRole
  #
  # @return [String]
  def role
    attribute KAXRoleAttribute
  end

  ##
  # @note You might get `nil` back as the subrole as AXWebArea
  #       objects are known to do this. You need to check. :(
  #
  # Shortcut for getting the `KAXSubroleAttribute`.
  #
  # @example
  #   subrole  # => "AXDialog"
  #   subrole  # => nil
  #
  # @return [String,nil]
  def subrole
    attribute KAXSubroleAttribute
  end

  ##
  # Shortcut for getting the `KAXChildrenAttribute`.
  #
  # @example
  #
  #   children # => [MenuBar, Window, ...]
  #
  # @return [Array<AX::Element>]
  def children
    attribute KAXChildrenAttribute
  end

  ##
  # Shortcut for getting the `KAXValueAttribute`.
  #
  # @example
  #
  #   value  # => "Mark Rada"
  #   value  # => 42
  #
  def value
    attribute KAXValueAttribute
  end

  ##
  # Get the size of the array for attributes that would return an array.
  # When performance matters, this is much faster than getting the array
  # and asking for the size.
  #
  # If there is a failure or the backing element is no longer alive, this
  # method will return `0`.
  #
  # @example
  #
  #   size_of KAXChildrenAttribute  # => 19
  #   size_of KAXRowsAttribute      # => 100
  #
  # @param [String] name an attribute constant
  # @return [Number]
  def size_of name
    ptr = Pointer.new :long_long
    case code = AXUIElementGetAttributeValueCount(@ref, name, ptr)
    when 0                                                  then ptr.value
    when KAXErrorFailure, KAXErrorAttributeUnsupported,
      KAXErrorInvalidUIElement                              then 0
    else handle_error code, name
    end
  end

  ##
  # Returns whether or not an attribute is writable.
  #
  # @example
  #
  #   writable? KAXSizeAttribute  # => true
  #   writable? KAXTitleAttribute # => false
  #
  # @param [String] name an attribute constant
  def writable? name
    ptr = Pointer.new :bool
    case code = AXUIElementIsAttributeSettable(@ref, name, ptr)
    when 0                        then ptr.value
    when KAXErrorInvalidUIElement then false
    else handle_error code, name
    end
  end

  ##
  # @note This method does not check writability of the attribute
  #       you are setting. If you need to check, use {#writable?}
  #       first.
  #
  # Set the given value to the given attribute. You do not need to
  # worry about wrapping objects first, `Range` objects will also
  # be automatically converted into `CFRange` objects and then
  # wrapped.
  #
  # Unlike when reading attributes, writing to a dead element will
  # raise an exception.
  #
  # @example
  #   set KAXValueAttribute,        "hi"       # => "hi"
  #   set KAXSizeAttribute,         [250,250]  # => [250,250]
  #   set KAXVisibleRangeAttribute, 0..-3      # => 0..-3
  #
  # @param [String] name an attribute constant
  def set name, value
    code = AXUIElementSetAttributeValue(@ref, name, value.to_ax)
    return value if code.zero?
    handle_error code, name, value
  end


  # @group Actions

  ##
  # Get the list of actions that the element can perform. If an element
  # does not have actions, then an empty list will be returned.
  # Dead elements will also return an empty array.
  #
  # @example
  #
  #   action_names  # => ["AXPress"]
  #
  # @return [Array<String>]
  def actions
    ptr = Pointer.new ARRAY
    case code = AXUIElementCopyActionNames(@ref, ptr)
    when 0                        then ptr.value
    when KAXErrorInvalidUIElement then []
    else handle_error code
    end
  end

  ##
  # Ask an element to perform the given action. This method will always
  # return true or raise an exception. Actions should never fail.
  #
  # Unlike when reading attributes, performing an action on a dead element
  # will raise an exception.
  #
  # @example
  #
  #   perform KAXPressAction  # => true
  #
  # @param [String] action an action constant
  # @return [Boolean]
  def perform action
    code = AXUIElementPerformAction(@ref, action)
    return true if code.zero?
    handle_error code, action
  end

  ##
  # Post the list of given keyboard events to the element. This only
  # applies if the given element is an application object or the
  # system wide object.
  #
  # Events could be generated from a string using output from
  # {Accessibility::String#keyboard_events_for}.
  #
  # Events are number/boolean tuples, where the number is a keycode
  # and the boolean is the keypress state (true is keydown, false is
  # keyup).
  #
  # You can learn more about keyboard events from the
  # {file:docs/KeyboardEvents.markdown Keyboard Events} documentation.
  #
  # @example
  #
  #   include Accessibility::String
  #   events = keyboard_events_for "Hello, world!\n"
  #   post events, safari_ref
  #
  # @param [Array<Array(Number,Boolean)>]
  # @param [AXUIElementRef]
  def post events
    events.each do |event|
      code = AXUIElementPostKeyboardEvent(@ref, 0, *event)
      handle_error code, @ref unless code.zero?
      sleep KEY_RATE
    end
    sleep 0.1 # in many cases, UI is not done updating right away
  end

  ##
  # @todo Make this runtime configurable.
  #
  # The delay between key presses. The default value is `0.01`, which
  # should be about 50 characters per second (down and up are separate
  # events).
  #
  # This is just a magic number from trial and error. Both the repeat
  # interval (NXKeyRepeatInterval) and threshold (NXKeyRepeatThreshold),
  # but both were way too big.
  #
  # @return [Number]
  KEY_RATE = case ENV['KEY_RATE']
             when 'VERY_SLOW' then 0.9
             when 'SLOW'      then 0.09
             when nil         then 0.009
             else                  ENV['KEY_RATE'].to_f
             end


  # @group Parameterized Attributes

  ##
  # Get the list of parameterized attributes for the given element. If an
  # element does not have parameterized attributes, then an empty
  # list will be returned.
  #
  # Most elements do not have parameterized attributes, but the ones
  # that do, have many.
  #
  # @example
  #
  #   param_attrs_for text_field_ref  # => ["AXStringForRange", ...]
  #   param_attrs_for window_ref      # => []
  #
  # @param [AXUIElementRef]
  # @return [Array<String>]
  def param_attrs_for element
    ptr  = Pointer.new ARRAY
    code = AXUIElementCopyParameterizedAttributeNames(element, ptr)
    return ptr[0] if code.zero?
    handle_error code, element
  end

  ##
  # Fetch the given pramaeterized attribute value of a given a given element
  # using the given parameter. You will be given raw data from this method;
  # that is, `Boxed` objects will still be wrapped in a `AXValueRef`, and
  # elements will be `AXUIElementRef` objects instead of wrapped
  # {AX::Element} objects.
  #
  # If the parameter needs to be a range or some other C struct, then you
  # will need to wrap it in an `AXValueRef` before passing it to this
  # method.
  #
  # @example
  #
  #   r = CFRange.new(1, 10)
  #   value_of KAXStringForRangeParameterizedAttribute, for_param: r, for: tf
  #     # => "ello, worl"
  #
  # @param [String] attr an attribute constant
  # @param [Object] param
  # @param [AXUIElementRef]
  def value_of attr, for_param: param, for: element
    ptr   = Pointer.new :id
    param = param.to_axvalue
    code  = AXUIElementCopyParameterizedAttributeValue(element,attr,param,ptr)
    return ptr[0].to_value if code.zero?
    return nil             if code == KAXErrorNoValue
    handle_error code, element, attr, param
  end


  # @group Element Hierarchy Entry Points

  ##
  # Find the top most element at a point on the screen that belongs to
  # a given application.
  #
  # The coordinates should be specified using the flipped coordinate
  # system (origin is in the top-left, increasing downward and to the right
  # as if reading a book in English).
  #
  # If more than one element is at the position then the
  # z-order of the elements will be used to determine which is
  # "on top". To get the absolute top element, regardless of application,
  # then pass system-wide element for the `app`.
  #
  # @example
  #
  #   element_at [453, 200], for: safari_ref       # web area
  #   element_at [453, 200], for: system_wide_ref  # table
  #
  # @param [#to_point]
  # @param [AXUIElementRef]
  # @return [AXUIElementRef]
  def element_at point, for: app
    ptr   = Pointer.new ELEMENT
    code  = AXUIElementCopyElementAtPosition(app, *point.to_point, ptr)
    return ptr[0] if code.zero?
    return nil    if code == KAXErrorNoValue
    handle_error code, app, point, nil, nil
  end

  ##
  # Find the top most element at a point on the screen. This is
  # equivalent to calling {element_at:for:} and passing {system_wide} as
  # the application.
  #
  # @param [#to_point]
  def element_at point
    element_at point, for: system_wide
  end

  ##
  # Get the application accessibility object/token for an application
  # given the process identifier (PID) for that application.
  #
  # @example
  #
  #   app = application_for 54743  # => #<AXUIElementRefx00000000>
  #   CFShow(app)
  #
  # @param [Fixnum]
  # @return [AXUIElementRef]
  def application_for pid
    spin_run_loop
    if NSRunningApplication.runningApplicationWithProcessIdentifier pid
      AXUIElementCreateApplication(pid)
    else
      raise ArgumentError, 'pid must belong to a running application'
    end
  end


  # @group Notifications

  ##
  # @todo Allow a `Method` object to be passed once MacRuby ticket #1463
  #       is fixed.
  #
  # Create and return a notification observer for the given object's
  # application. You can either pass a method reference, proc, or just
  # attach a regular block to this method, but you must choose one.
  #
  # Observer's belong to an application, so you can cache a particular
  # observer and use it for many different notification registrations.
  #
  # @example
  #
  #   observer_for pid_for(window_ref) do |observer, element, notif, context|
  #     # do stuff...
  #   end
  #
  # @param [Number]
  # @yieldparam [AXObserverRef]
  # @yieldparam [AXUIElementRef]
  # @yieldparam [String]
  # @yieldparam [Object]
  # @return [AXObserverRef]
  def observer_for pid, &block
    raise ArgumentError, 'A callback is required' unless block
    ptr  = Pointer.new OBSERVER
    # @todo Create a proc here and wrap the given callback
    code = AXObserverCreate(pid, block, ptr)
    return ptr[0] if code.zero?
    handle_error code, element, callback
  end

  ##
  # Get the run loop source for the given observer. You will need to
  # get the source for an observer added the a run loop source in
  # your script in order to begin receiving notifications.
  #
  # @example
  #
  #   # get the source
  #   source = run_loop_source_for observer
  #
  #   # add the source to the current run loop
  #   CFRunLoopAddSource(CFRunLoopGetCurrent(), source, KCFRunLoopDefaultMode)
  #
  #   # don't forget to remove the source when you are done!
  #
  # @param [AXObserverRef]
  # @return [CFRunLoopSourceRef]
  def run_loop_source_for observer
    AXObserverGetRunLoopSource(observer)
  end

  ##
  # @todo Should passing around a context be supported?
  #
  # Register a notification observer for a specific event.
  #
  # @example
  #
  #   register observer, to_receive: KAXWindowCreatedNotification, from: window
  #
  # @param [AXObserverRef]
  # @param [String]
  # @param [AX::Element]
  # @return [Boolean]
  def register observer, to_receive: notif, from: element
    code = AXObserverAddNotification(observer, element, notif, nil)
    return true if code.zero?
    handle_error code, element, notif, observer, nil, nil
  end

  ##
  # Unregister a notification that has been previously setup.
  #
  # @param [AXObserverRef]
  # @param [String]
  # @param [AX::Element]
  # @return [Boolean]
  def unregister observer, from_receiving: notif, from: element
    code = AXObserverRemoveNotification(observer, element, notif)
    return true if code.zero?
    handle_error code, element, notif, observer, nil, nil
  end


  # @group Misc.

  ##
  # Ask whether or not AXAPI is enabled.
  #
  # @example
  #
  #   enabled?  # => true
  #
  #   # After unchecking "Enable access for assistive devices" in System Prefs
  #   enabled?  # => false
  #
  def enabled?
    AXAPIEnabled()
  end

  ##
  # Get the process identifier (PID) of the application that the given
  # element belongs to.
  #
  # @example
  #
  #   pid_for safari_ref      # => 12345
  #   pid_for text_field_ref  # => 12345
  #
  # @param [AXUIElementRef]
  # @return [Fixnum]
  def pid_for element
    ptr  = Pointer.new :int
    code = AXUIElementGetPid(element, ptr)
    return ptr[0] if code.zero?
    handle_error code, element
  end

  ##
  # Create a new reference to the system wide object. This is very useful when
  # working with the system wide object as you cannot cache the system wide
  # reference and need to keep creating new instances all the time.
  #
  # @example
  #
  #   system_wide  # => #<AXUIElementRefx00000000>
  #
  # @return [AXUIElementRef]
  def system_wide
    AXUIElementCreateSystemWide()
  end

  ##
  # Spin the run loop once. For the purpose of receiving notification
  # callbacks.
  #
  # @example
  #
  #   spin_run_loop # not much to it
  #
  # @return [self] returns the receiver
  def spin_run_loop
    NSRunLoop.currentRunLoop.runUntilDate Time.now
  end


  # @group Debug

  ##
  # Change the timeout value for an element or globally. In cases where
  # you think an element may be slow to respond this can be helpful.
  #
  # To change the global value, pass the system wide object for
  # the `element` argument.
  #
  # @param [Number]
  # @param [AXUIElementRef]
  # @return [Number]
  def set_timeout_to seconds, for: element
    code = AXUIElementSetMessagingTimeout(element, seconds)
    return seconds if code.zero?
    handle_error code, element, seconds
  end

  ##
  # Globally change the timeout value for AXAPI. This is equivalent to
  # calling {set_timeout_to:for:} and passing {system_wide} as the element.
  #
  # Setting the global timeout to `0` seconds will reset the timeout value
  # to the system default. Apple does not appear to have publicly documented
  # what the system default is though, so I can't tell you what that value
  # is.
  #
  # @param [Number]
  # @return [Number]
  def set_timeout_to seconds
    set_timeout_to seconds, for: system_wide
  end


  private

  # @group Error Handling

  # @param [Number]
  def handle_error code, *args
    args[0]              = args[0].inspect if args[0]
    klass, handler, argc = AXERROR[code] || [RuntimeError]
    msg                  = if handler
                             self.send handler, *args[argc]
                           else
                             "You should never reach this line [#{code}]"
                           end
    raise klass, msg, caller(1)
  end

  # @private
  def handle_failure ref
    "A system failure occurred with #{ref}, stopping to be safe"
  end

  # @private
  def handle_illegal_argument *args
    case args.size
    when 1
      "#{args.first} is not an AXUIElementRef"
    when 2
      "Either the element #{args.first} " +
        "or the attr/action/callback #{args[1].inspect} " +
        'is not a legal argument'
    when 3
      "You can't set #{args[1].inspect} to " +
        "#{args[2].inspect} for #{args.first}"
    when 4
      "The point #{args[1].to_point.inspect} is not a valid point, " +
        "or #{args.first} is not an AXUIElementRef"
    when 5
      "Either the observer #{args[2].inspect}, " +
        "the element #{args.first}, or " +
        "the notification #{args[1].inspect} " +
        "is not a legitimate argument"
    end
  end

  # @private
  def handle_invalid_element ref
    "#{ref} is no longer a valid reference"
  end

  # @private
  def handle_invalid_observer ref, lol, obsrvr
    "#{obsrvr.inspect} is no longer a valid observer for #{ref}" +
      'or was never valid'
  end

  # @private
  # @param [AXUIElementRef]
  def handle_cannot_complete ref
    spin_run_loop
    pid = pid_for ref
    app = NSRunningApplication.runningApplicationWithProcessIdentifier pid
    if app
      "An unspecified error occurred using #{ref} with AXAPI" +
        ', maybe a timeout :('
    else
      "Application for pid=#{pid} is no longer running. Maybe it crashed?"
    end
  end

  # @private
  def handle_attr_unsupported ref, attr
    "#{ref} does not have a #{attr.inspect} attribute"
  end

  # @private
  def handle_action_unsupported ref, action
    "#{ref} does not have a #{action.inspect} action"
  end

  # @private
  def handle_notif_unsupported ref, notif
    "#{ref} does not support the #{notif.inspect} notification"
  end

  # @private
  def handle_not_implemented ref
    "The program that owns #{ref} does not work with AXAPI properly"
  end

  ##
  # @private
  # @todo Does this really neeed to raise an exception? Seems
  #       like a warning would be sufficient.
  def handle_notif_registered ref, notif
    "You have already registered to hear about #{notif.inspect} from #{ref}"
  end

  # @private
  def handle_notif_not_registered ref, notif
    "You have not registered to hear about #{notif.inspect} from #{ref}"
  end

  # @private
  def handle_api_disabled
    'AXAPI has been disabled'
  end

  # @private
  def handle_param_attr_unsupported ref, attr
    "#{ref} does not have a #{attr.inspect} parameterized attribute"
  end

  # @private
  def handle_not_enough_precision
    'AXAPI said there was not enough precision ¯\(°_o)/¯'
  end

  # @endgroup


  ##
  # @private
  #
  # `Pointer` type encoding for `CFArrayRef` objects.
  #
  # @return [String]
  ARRAY    = '^{__CFArray}'.freeze

  ##
  # @private
  #
  # `Pointer` type encoding for `AXUIElementRef` objects.
  #
  # @return [String]
  ELEMENT  = '^{__AXUIElement}'.freeze

  ##
  # @private
  #
  # `Pointer` type encoding for `AXObserverRef` objects.
  #
  # @return [String]
  OBSERVER = '^{__AXObserver}'.freeze

  ##
  # @private
  #
  # Mapping of `AXError` values to static information on how to handle
  # the error. Used by {handle_error}.
  #
  # @return [Hash{Number=>Array(Symbol,Range)}]
  AXERROR = {
    KAXErrorFailure                           =>
      [RuntimeError,        :handle_failure,                0...1],
    KAXErrorIllegalArgument                   =>
      [ArgumentError,       :handle_illegal_argument,       0..-1],
    KAXErrorInvalidUIElement                  =>
      [ArgumentError,       :handle_invalid_element,        0...1],
    KAXErrorInvalidUIElementObserver          =>
      [ArgumentError,       :handle_invalid_observer,       0...3],
    KAXErrorCannotComplete                    =>
      [RuntimeError,        :handle_cannot_complete,        0...1],
    KAXErrorAttributeUnsupported              =>
      [ArgumentError,       :handle_attr_unsupported,       0...2],
    KAXErrorActionUnsupported                 =>
      [ArgumentError,       :handle_action_unsupported,     0...2],
    KAXErrorNotificationUnsupported           =>
      [ArgumentError,       :handle_notif_unsupported,      0...2],
    KAXErrorNotImplemented                    =>
      [NotImplementedError, :handle_not_implemented,        0...1],
    KAXErrorNotificationAlreadyRegistered     =>
      [ArgumentError,       :handle_notif_registered,       0...2],
    KAXErrorNotificationNotRegistered         =>
      [RuntimeError,        :handle_notif_not_registered,   0...2],
    KAXErrorAPIDisabled                       =>
      [RuntimeError,        :handle_api_disabled,           0...0],
    KAXErrorParameterizedAttributeUnsupported =>
      [ArgumentError,       :handle_param_attr_unsupported, 0...2],
    KAXErrorNotEnoughPrecision                =>
      [RuntimeError,        :handle_not_enough_precision,   0...0]
  }

end


##
# AXElements extensions to the `Boxed` class. The `Boxed` class is
# simply an abstract base class for structs that MacRuby can use
# via bridge support.
class Boxed
  ##
  # Returns the number that AXAPI uses in order to know how to wrap
  # a struct.
  #
  # @return [Number]
  def self.ax_value
    raise NotImplementedError, "#{self.class} cannot be wraped"
  end

  ##
  # Create an `AXValue` from the `Boxed` instance. This will only
  # work if for a few boxed types, you will need to check the AXAPI
  # documentation for an up to date list.
  #
  # @example
  #
  #   CGPointMake(12, 34).to_axvalue # => #<AXValueRef:0x455678e2>
  #   CGSizeMake(56, 78).to_axvalue  # => #<AXValueRef:0x555678e2>
  #
  # @return [AXValueRef]
  def to_axvalue
    klass = self.class
    ptr   = Pointer.new klass.type
    ptr.assign self
    AXValueCreate(klass.ax_value, ptr)
  end
end

# AXElements extensions for `CFRange`.
class CFRange
  def self.ax_value
    KAXValueCFRangeType
  end

  # @return [Range]
  def to_value
    Range.new location, (location + length - 1)
  end
end

# AXElements extensions for `CGSize`.
class << CGSize;  def ax_value; KAXValueCGSizeType;  end end
# AXElements extensions for `CGRect`.
class << CGRect;  def ax_value; KAXValueCGRectType;  end end
# AXElements extensions for `CGPoint`.
class << CGPoint; def ax_value; KAXValueCGPointType; end end

##
# Mixin for the special `__NSCFType` class so that `#to_value` works properly.
module Accessibility::AXValueUnwrapper
  ##
  # Map of type encodings used for wrapping structs when coming from
  # an `AXValueRef`.
  #
  # The list is order sensitive, which is why we unshift nil, but
  # should probably be more rigorously defined at runtime.
  #
  # @return [String,nil]
  BOX_TYPES = [CGPoint, CGSize, CGRect, CFRange].map!(&:type).unshift(nil)

  ##
  # Unwrap an `AXValue` into the `Boxed` instance that it is supposed
  # to be. This will only work for a few boxed types, you will need to
  # check the AXAPI documentation for an up to date list.
  #
  # @example
  #
  #   wrapped_point.to_value # => #<CGPoint x=44.3 y=99.0>
  #   wrapped_range.to_value # => #<CFRange begin=7 length=100>
  #
  # @return [Boxed]
  def to_value
    box_type = AXValueGetType(self)
    return self if box_type.zero?
    ptr      = Pointer.new BOX_TYPES[box_type]
    AXValueGetValue(self, box_type, ptr)
    ptr[0].to_value
  end
end
AXUIElementCreateSystemWide().class.send(:include, Accessibility::AXValueUnwrapper)

# AXElements extensions for `NSObject`.
class NSObject
  # @return [Object]
  def to_axvalue
    self
  end

  # @return [Object]
  def to_value
    self
  end
end


unless Object.const_defined? :KAXIdentifierAttribute
  ##
  # Added for backwards compatability with Snow Leopard.
  # This attribute is standard with Lion and newer. AXElements depends
  # on it being defined.
  #
  # @return [String]
  KAXIdentifierAttribute = 'AXIdentifier'
end


# AXElements extensions to `NSArray`.
class NSArray
  # @return [CFRange]
  def to_range; CFRange.new(first, at(1)) end
  # @return [CGPoint]
  def to_point; CGPoint.new(first, at(1)) end
  # @return [CGSize]
  def to_size;  CGSize.new(first, at(1))  end
  # @return [CGRect]
  def to_rect;  CGRectMake(*self[0..3])   end
end

# AXElements extensions for `CGPoint`.
class CGPoint
  # @return [CGPoint]
  def to_point
    self
  end
end

# AXElements extensions for `Range`.
class Range
  # @return [AXValueRef]
  def to_axvalue
    raise ArgumentError if last < 0 || first < 0
    length = if exclude_end?
               last - first
             else
               last - first + 1
             end
    CFRange.new(first, length).to_axvalue
  end
end
