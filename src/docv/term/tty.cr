# src/docv/term/tty.cr
require "base64"

lib LibDocvTty
  struct Winsize
    ws_row : UInt16
    ws_col : UInt16
    ws_xpixel : UInt16
    ws_ypixel : UInt16
  end

  fun ioctl(fd : LibC::Int, request : LibC::ULong, ...) : LibC::Int
end

module Docv::Term
  # Escape sequences the viewer writes.
  module Sequences
    ALT_SCREEN_ON  = "\e[?1049h"
    ALT_SCREEN_OFF = "\e[?1049l"
    CURSOR_HIDE    = "\e[?25l"
    CURSOR_SHOW    = "\e[?25h"
    # Kitty keyboard: push all five enhancements, pop on exit.
    KEYBOARD_PUSH = "\e[>31u"
    KEYBOARD_POP  = "\e[<u"
    # Any-event tracking with SGR-pixel coordinates (SGR cells as fallback).
    MOUSE_ON  = "\e[?1003;1006;1016h"
    MOUSE_OFF = "\e[?1003;1006;1016l"
    # In-band resize, focus, visibility and color scheme notifications.
    NOTIFY_ON  = "\e[?2048h\e[?1004h\e[?2033h\e[?2031h"
    NOTIFY_OFF = "\e[?2048l\e[?1004l\e[?2033l\e[?2031l"
    # Queries: pixel mouse mode, cell size, keyboard flags, visibility, scheme.
    QUERIES = "\e[?1016$p\e[16t\e[?u\e[?998n\e[?996n"
    # OSC 21 query of the terminal theme: foreground, background and the 16
    # ANSI colors.
    COLORS_QUERY = "\e]21;foreground=?;background=?;#{(0..15).join(';') { |index| "#{index}=?" }}\e\\"
    # OSC 52 clipboard write: the start before the base64 text. An invalid
    # payload first clears the clipboard in terminals that append writes
    # (kitty).
    CLIPBOARD_CLEAR = "\e]52;c;!\e\\"
    CLIPBOARD       = "\e]52;c;"
    # OSC 8 hyperlink: the start before the URI and the string terminator
    # after it; an empty URI ends the link.
    HYPERLINK = "\e]8;;"
    # OSC 22 pointer shape: the start before a CSS cursor name and the
    # string terminator after it; an empty name resets the shape.
    POINTER    = "\e]22;"
    TERMINATOR = "\e\\"
    SYNC_BEGIN = "\e[?2026h"
    SYNC_END   = "\e[?2026l"
    RESET      = "\e[0m"
  end

  # The controlling terminal: raw mode, size, and entering/leaving the
  # full-screen state with all input reporting.
  class Tty
    TIOCGWINSZ = 0x5413_u64

    # The color depth the environment announces: none when *no_color*
    # (`NO_COLOR`) is set and not empty, 24-bit when *colorterm* is
    # `truecolor` or `24bit`, 256 colors when *term* names a `256color` or
    # `direct` terminal, the 16 ANSI colors otherwise. A terminal that
    # answers the OSC 21 query (`Sequences::COLORS_QUERY`) shows 24-bit color
    # whatever this says.
    def self.color_depth(no_color : String? = ENV["NO_COLOR"]?, colorterm : String? = ENV["COLORTERM"]?,
                         term : String? = ENV["TERM"]?) : ColorDepth
      return ColorDepth::None if no_color && !no_color.empty?
      return ColorDepth::TrueColor if colorterm.try(&.downcase).in?("truecolor", "24bit")
      return ColorDepth::TrueColor if term.try(&.ends_with?("-direct"))
      return ColorDepth::Palette if term.try(&.includes?("256color"))
      ColorDepth::Ansi
    end

    getter input : IO::FileDescriptor
    getter output : IO::FileDescriptor
    @saved : LibC::Termios? = nil

    def initialize(@input : IO::FileDescriptor = STDIN, @output : IO::FileDescriptor = STDOUT)
    end

    # True when both ends are terminals.
    def tty? : Bool
      @input.tty? && @output.tty?
    end

    # Switches the input to raw mode, remembering the previous settings.
    def raw : Nil
      attributes = uninitialized LibC::Termios
      return if LibC.tcgetattr(@input.fd, pointerof(attributes)) != 0
      @saved = attributes
      LibC.cfmakeraw(pointerof(attributes))
      LibC.tcsetattr(@input.fd, LibC::TCSANOW, pointerof(attributes))
    end

    # Restores the settings saved by `raw`.
    def restore : Nil
      if saved = @saved
        attributes = saved
        LibC.tcsetattr(@input.fd, LibC::TCSANOW, pointerof(attributes))
        @saved = nil
      end
    end

    # The window size: rows, columns, pixel width, pixel height.
    def size : {Int32, Int32, Int32, Int32}
      size = LibDocvTty::Winsize.new
      if LibDocvTty.ioctl(@output.fd, TIOCGWINSZ, pointerof(size)) == 0 && size.ws_col > 0
        {size.ws_row.to_i, size.ws_col.to_i, size.ws_xpixel.to_i, size.ws_ypixel.to_i}
      else
        {24, 80, 0, 0}
      end
    end

    # Enters the alternate screen, pushes the keyboard mode inside it, and
    # enables mouse and notification reporting.
    def enter : Nil
      raw
      write(Sequences::ALT_SCREEN_ON + Sequences::KEYBOARD_PUSH + Sequences::CURSOR_HIDE +
            Sequences::MOUSE_ON + Sequences::NOTIFY_ON + Sequences::QUERIES + Sequences::COLORS_QUERY)
    end

    # Asks the terminal for its theme colors again (after a color scheme
    # change).
    def query_colors : Nil
      write(Sequences::COLORS_QUERY)
    end

    # Puts *text* on the system clipboard (OSC 52).
    def copy(text : String) : Nil
      write("#{Sequences::CLIPBOARD_CLEAR}#{Sequences::CLIPBOARD}#{Base64.strict_encode(text)}\e\\")
    end

    # Sets the mouse pointer to the CSS cursor *shape* (`pointer`, `text`,
    # `ew-resize` ...; OSC 22); an empty shape resets it.
    def pointer(shape : String) : Nil
      write("#{Sequences::POINTER}#{shape}#{Sequences::TERMINATOR}")
    end

    # Undoes `enter` in reverse order, resetting the pointer shape.
    def leave : Nil
      write(Sequences::POINTER + Sequences::TERMINATOR + Sequences::RESET + Sequences::NOTIFY_OFF + Sequences::MOUSE_OFF + Sequences::KEYBOARD_POP +
            Sequences::CURSOR_SHOW + Sequences::ALT_SCREEN_OFF)
      restore
    end

    # Writes *data* and flushes.
    def write(data : String | Bytes) : Nil
      @output.write(data.to_slice)
      @output.flush
    end
  end
end
