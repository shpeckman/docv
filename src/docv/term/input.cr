# src/docv/term/input.cr

module Docv::Term
  # :nodoc:
  # A key that produced text with no command modifier.
  record TextInput, text : String, key : KeyEvent

  # :nodoc:
  # Any other key press or repeat.
  record KeyCommand, key : KeyEvent

  # :nodoc:
  record MousePress, button : MouseButton, col : Int32, row : Int32, mods : Mods

  # :nodoc:
  # `count` is 1 to 3 for single to triple clicks.
  record Click, button : MouseButton, count : Int32, col : Int32, row : Int32, mods : Mods

  # :nodoc:
  enum DragPhase : UInt8
    Start
    Move
    End
  end

  # :nodoc:
  record Drag, phase : DragPhase, button : MouseButton, col : Int32, row : Int32,
    start_col : Int32, start_row : Int32, mods : Mods

  # :nodoc:
  # Coalesced wheel steps: positive `dy` scrolls down, positive `dx` right.
  record Scroll, dx : Int32, dy : Int32, col : Int32, row : Int32, mods : Mods

  # :nodoc:
  record PointerEnter, col : Int32, row : Int32
  # :nodoc:
  record PointerLeave, col : Int32, row : Int32

  # :nodoc:
  # The pointer moved with no button held.
  record PointerMove, col : Int32, row : Int32, mods : Mods

  # :nodoc:
  alias Derived = TextInput | KeyCommand | MousePress | Click | Drag | Scroll | PointerEnter | PointerLeave | PointerMove |
                  ResizeEvent | FocusEvent | VisibilityEvent | ColorSchemeEvent | ModeReport | CellSizeReport |
                  KeyboardFlagsReport | ColorsReport

  # :nodoc:
  # Derives text, commands, clicks, drags and scrolls from raw events, in cells.
  class Input
    # Longest press that still counts as a click.
    CLICK_TIME = 500.milliseconds
    # Longest gap between clicks of a multi-click.
    MULTI_CLICK_TIME = 400.milliseconds

    # A key in the pressed-set.
    record Held, pressed_at : Time::Instant, last_repeat_at : Time::Instant, repeat_count : Int32, mods : Mods

    # Cell size in pixels, from the window size or a report.
    property cell_width : Int32 = 0
    property cell_height : Int32 = 0
    # Mouse reports carry pixels (mode 1016).
    property? pixels : Bool = false

    getter held = Hash(Int32, Held).new

    @decoder = Decoder.new
    @inside = false
    @last_x = 0
    @last_y = 0
    @press : {MouseButton, Int32, Int32, Time::Instant}? = nil
    @dragging = false
    @drag_start = {0, 0}
    @last_click : {MouseButton, Int32, Int32, Time::Instant, Int32}? = nil
    @scroll_dx = 0
    @scroll_dy = 0
    @scroll_mods = Mods::None

    def pending? : Bool
      @decoder.pending?
    end

    def feed(bytes : Bytes, & : Derived ->) : Nil
      @decoder.feed(bytes) { |event| handle(event) { |derived| yield derived } }
      flush_scroll { |derived| yield derived }
    end

    # Resolves buffered input after a timeout (a lone ESC).
    def flush(& : Derived ->) : Nil
      @decoder.flush { |event| handle(event) { |derived| yield derived } }
      flush_scroll { |derived| yield derived }
    end

    # Sets the cell size from the window's cell and pixel extents.
    def window(rows : Int32, cols : Int32, width : Int32, height : Int32) : Nil
      return if rows <= 0 || cols <= 0 || width <= 0 || height <= 0
      @cell_width = width // cols
      @cell_height = height // rows
    end

    private def handle(event : Event, & : Derived ->) : Nil
      flush_scroll { |derived| yield derived } unless event.is_a?(MouseEvent) && event.action.scroll?
      case event
      when KeyEvent
        key(event) { |derived| yield derived }
      when MouseEvent
        mouse(event) { |derived| yield derived }
      when ModeReport
        @pixels = event.value == 1 || event.value == 3 if event.mode == 1016
        yield event
      when CellSizeReport
        @cell_width, @cell_height = event.width, event.height if event.width > 0 && event.height > 0
        yield event
      when ResizeEvent
        window(event.rows, event.cols, event.width, event.height)
        yield event
      else
        yield event
      end
    end

    private def key(event : KeyEvent, & : Derived ->) : Nil
      now = Time.instant
      case event.action
      in .press?
        @held[event.key] = Held.new(now, now, 0, event.mods)
      in .repeat?
        if held = @held[event.key]?
          @held[event.key] = Held.new(held.pressed_at, now, held.repeat_count + 1, held.mods)
        else
          @held[event.key] = Held.new(now, now, 1, event.mods)
        end
      in .release?
        @held.delete(event.key)
        return
      end
      return if Key.modifier?(event.key)
      text = event.text
      if text && (event.mods & Mods::COMMAND).none?
        yield TextInput.new(text, event)
      else
        yield KeyCommand.new(event)
      end
    end

    private def cell(x : Int32, y : Int32) : {Int32, Int32}
      if @pixels
        width = @cell_width > 0 ? @cell_width : 1
        height = @cell_height > 0 ? @cell_height : 1
        {x // width, y // height}
      else
        {Math.max(x - 1, 0), Math.max(y - 1, 0)}
      end
    end

    private def radius : Int32
      @pixels ? Math.max(@cell_width // 2, 3) : 0
    end

    private def near?(x1 : Int32, y1 : Int32, x2 : Int32, y2 : Int32) : Bool
      (x1 - x2).abs <= radius && (y1 - y2).abs <= radius
    end

    private def mouse(event : MouseEvent, & : Derived ->) : Nil
      if event.action.leave?
        col, row = cell(@last_x, @last_y)
        if @dragging && (press = @press)
          yield Drag.new(DragPhase::End, press[0], col, row, @drag_start[0], @drag_start[1], event.mods)
        end
        @press = nil
        @dragging = false
        @inside = false
        yield PointerLeave.new(col, row)
        return
      end
      unless @inside
        @inside = true
        enter_col, enter_row = cell(event.x, event.y)
        yield PointerEnter.new(enter_col, enter_row)
      end
      @last_x, @last_y = event.x, event.y
      col, row = cell(event.x, event.y)
      now = Time.instant
      case event.action
      when .scroll?
        case event.button
        when .wheel_up?    then @scroll_dy -= 1
        when .wheel_down?  then @scroll_dy += 1
        when .wheel_left?  then @scroll_dx -= 1
        when .wheel_right? then @scroll_dx += 1
        end
        @scroll_mods = event.mods
      when .hover?
        yield PointerMove.new(col, row, event.mods)
      when .press?
        @press = {event.button, event.x, event.y, now}
        @dragging = false
        yield MousePress.new(event.button, col, row, event.mods)
      when .drag?
        press = @press || return
        if @dragging
          yield Drag.new(DragPhase::Move, press[0], col, row, @drag_start[0], @drag_start[1], event.mods)
        elsif !near?(press[1], press[2], event.x, event.y)
          @dragging = true
          @drag_start = cell(press[1], press[2])
          yield Drag.new(DragPhase::Start, press[0], col, row, @drag_start[0], @drag_start[1], event.mods)
        end
      when .release?
        press = @press
        @press = nil
        if @dragging && press
          @dragging = false
          yield Drag.new(DragPhase::End, press[0], col, row, @drag_start[0], @drag_start[1], event.mods)
          return
        end
        return unless press
        button = press[0]
        return unless near?(press[1], press[2], event.x, event.y) && now - press[3] <= CLICK_TIME
        count = 1
        if (last = @last_click) && last[0] == button && now - last[3] <= MULTI_CLICK_TIME && near?(last[1], last[2], event.x, event.y)
          count = last[4] >= 3 ? 1 : last[4] + 1
        end
        @last_click = {button, event.x, event.y, now, count}
        yield Click.new(button, count, col, row, event.mods)
      end
    end

    private def flush_scroll(& : Derived ->) : Nil
      return if @scroll_dx == 0 && @scroll_dy == 0
      col, row = cell(@last_x, @last_y)
      yield Scroll.new(@scroll_dx, @scroll_dy, col, row, @scroll_mods)
      @scroll_dx = 0
      @scroll_dy = 0
    end
  end
end
