# src/docv/term/tty.cr

require "base64"

# :nodoc:
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
  # :nodoc:
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
    # OSC 21 query: foreground, background and the 16 ANSI colors.
    COLORS_QUERY = "\e]21;foreground=?;background=?;#{(0..15).join(';') { |index| "#{index}=?" }}\e\\"
    # OSC 52; the invalid `!` payload first clears terminals that append writes (kitty).
    CLIPBOARD_CLEAR = "\e]52;c;!\e\\"
    CLIPBOARD       = "\e]52;c;"
    # OSC 8: `HYPERLINK uri TERMINATOR`; an empty URI ends the link.
    HYPERLINK = "\e]8;;"
    # OSC 22: `POINTER css-cursor-name TERMINATOR`; an empty name resets the shape.
    POINTER    = "\e]22;"
    TERMINATOR = "\e\\"
    SYNC_BEGIN = "\e[?2026h"
    SYNC_END   = "\e[?2026l"
    RESET      = "\e[0m"
  end

  # The terminal a `Viewer` runs on: *input* and *output*, `STDIN` and `STDOUT` by default.
  class Tty
    # :nodoc:
    TIOCGWINSZ = 0x5413_u64

    # The `ColorDepth` the environment announces: `None` for a non-empty *no_color*,
    # `TrueColor` for a *colorterm* of `truecolor`/`24bit` or a `-direct` *term*,
    # `Palette` for a `256color` *term*, `Ansi` otherwise.
    def self.color_depth(no_color : String? = ENV["NO_COLOR"]?, colorterm : String? = ENV["COLORTERM"]?,
                         term : String? = ENV["TERM"]?) : ColorDepth
      return ColorDepth::None if no_color && !no_color.empty?
      return ColorDepth::TrueColor if colorterm.try(&.downcase).in?("truecolor", "24bit")
      return ColorDepth::TrueColor if term.try(&.ends_with?("-direct"))
      return ColorDepth::Palette if term.try(&.includes?("256color"))
      ColorDepth::Ansi
    end

    # :nodoc:
    getter input : IO::FileDescriptor
    # :nodoc:
    getter output : IO::FileDescriptor
    @saved : LibC::Termios? = nil

    def initialize(@input : IO::FileDescriptor = STDIN, @output : IO::FileDescriptor = STDOUT)
    end

    # True when both ends are terminals.
    def tty? : Bool
      @input.tty? && @output.tty?
    end

    # :nodoc:
    def raw : Nil
      attributes = uninitialized LibC::Termios
      return if LibC.tcgetattr(@input.fd, pointerof(attributes)) != 0
      @saved = attributes
      LibC.cfmakeraw(pointerof(attributes))
      LibC.tcsetattr(@input.fd, LibC::TCSANOW, pointerof(attributes))
    end

    # :nodoc:
    def restore : Nil
      if saved = @saved
        attributes = saved
        LibC.tcsetattr(@input.fd, LibC::TCSANOW, pointerof(attributes))
        @saved = nil
      end
    end

    # The window size as rows, columns, pixel width and pixel height; 24x80 when unknown.
    def size : {Int32, Int32, Int32, Int32}
      size = LibDocvTty::Winsize.new
      if LibDocvTty.ioctl(@output.fd, TIOCGWINSZ, pointerof(size)) == 0 && size.ws_col > 0
        {size.ws_row.to_i, size.ws_col.to_i, size.ws_xpixel.to_i, size.ws_ypixel.to_i}
      else
        {24, 80, 0, 0}
      end
    end

    # :nodoc:
    # Raw mode, alternate screen (keyboard mode pushed inside it), mouse and notifications.
    def enter : Nil
      raw
      write(Sequences::ALT_SCREEN_ON + Sequences::KEYBOARD_PUSH + Sequences::CURSOR_HIDE +
            Sequences::MOUSE_ON + Sequences::NOTIFY_ON + Sequences::QUERIES + Sequences::COLORS_QUERY)
    end

    # :nodoc:
    def query_colors : Nil
      write(Sequences::COLORS_QUERY)
    end

    # :nodoc:
    # Puts *text* on the system clipboard (OSC 52).
    def copy(text : String) : Nil
      write("#{Sequences::CLIPBOARD_CLEAR}#{Sequences::CLIPBOARD}#{Base64.strict_encode(text)}\e\\")
    end

    # :nodoc:
    # CSS cursor *shape* (OSC 22); an empty shape resets it.
    def pointer(shape : String) : Nil
      write("#{Sequences::POINTER}#{shape}#{Sequences::TERMINATOR}")
    end

    # :nodoc:
    # Undoes `enter` in reverse order, resetting the pointer shape.
    def leave : Nil
      write(Sequences::POINTER + Sequences::TERMINATOR + Sequences::RESET + Sequences::NOTIFY_OFF + Sequences::MOUSE_OFF + Sequences::KEYBOARD_POP +
            Sequences::CURSOR_SHOW + Sequences::ALT_SCREEN_OFF)
      restore
    end

    # :nodoc:
    def write(data : String | Bytes) : Nil
      @output.write(data.to_slice)
      @output.flush
    end
  end
end
