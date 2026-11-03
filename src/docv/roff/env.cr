# src/docv/roff/env.cr

# :nodoc:
module Docv::Roff
  # The four terminal fonts; other font names map onto these.
  enum Font : UInt8
    Regular
    Bold
    Italic
    BoldItalic

    # Maps any font name (`CW`, `CB`, `TBI`, ...) by its suffix.
    def self.from_name(name : String) : Font
      case
      when name.ends_with?("BI") || name.ends_with?("IB") then BoldItalic
      when name.ends_with?('B')                           then Bold
      when name.ends_with?('I')                           then Italic
      else                                                     Regular
      end
    end

    def attr : Attr
      case self
      in .regular?     then Attr::None
      in .bold?        then Attr::Bold
      in .italic?      then Attr::Italic
      in .bold_italic? then Attr::Bold | Attr::Italic
      end
    end
  end

  # A formatting environment (`.ev`); indents and lengths are in columns.
  class Env
    property font : Font = Font::Regular
    property prev_font : Font = Font::Regular
    property fg : Color = Color::DEFAULT
    property bg : Color = Color::DEFAULT
    property prev_fg : Color = Color::DEFAULT
    property prev_bg : Color = Color::DEFAULT
    property? fill : Bool = true
    property adjust : Align = Align::Both
    property indent : Int32 = 0
    property prev_indent : Int32 = 0
    # `.ti`: indent of the next output line only.
    property temp_indent : Int32? = nil
    # Input lines left for `.ce` and `.rj`.
    property center : Int32 = 0
    property rjust : Int32 = 0
    # Input lines left for `.ul`/`.cu`.
    property underline : Int32 = 0
    property tabs : Tabs = Tabs::DEFAULT
    property line_length : Int32 = 78
    property prev_line_length : Int32 = 78
    property title_length : Int32 = 78

    # Remembers the previous font for `\fP`.
    def font=(font : Font) : Font
      @prev_font = @font
      @font = font
    end

    # `\fP`: swaps back to the previous font.
    def previous_font : Nil
      @font, @prev_font = @prev_font, @font
    end

    # Style id for text in the current state.
    def style : UInt16
      attr = @font.attr
      attr |= Attr::Underline if @underline > 0
      Styles.id(Style.new(attr, @fg, @bg))
    end

    # A copy for `.evc` and new environments.
    def copy : Env
      env = Env.new
      env.font = @font
      env.prev_font = @prev_font
      env.fg, env.bg, env.prev_fg, env.prev_bg = @fg, @bg, @prev_fg, @prev_bg
      env.fill = @fill
      env.adjust = @adjust
      env.indent, env.prev_indent = @indent, @prev_indent
      env.tabs = @tabs
      env.line_length, env.prev_line_length, env.title_length = @line_length, @prev_line_length, @title_length
      env
    end
  end
end
