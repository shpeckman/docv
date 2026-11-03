# src/docv/style.cr
module Docv
  # Text attributes of a rendition.
  @[Flags]
  enum Attr : UInt8
    Bold
    Italic
    Underline
    Reverse
    Dim
    Strike
  end

  # What page text is beyond its rendition. A parser sets it; the viewer
  # draws marked text in a role (`Viewer::MARKUP_ROLES`).
  enum Markup : UInt8
    None
    # Inline code.
    Code
    # A line of a code block.
    CodeBlock
    # The bar of a block quote.
    Quote
    # A horizontal rule.
    Rule
    # The text standing for an image.
    Image
  end

  # How many colors the terminal shows.
  enum ColorDepth : UInt8
    # No colors at all (`NO_COLOR`); attributes only.
    None
    # The 16 ANSI colors.
    Ansi
    # The 256-color palette.
    Palette
    # 24-bit RGB.
    TrueColor
  end

  # A terminal color: the default color, an entry of the terminal's 256-color
  # palette (0-15 are the ANSI colors of the terminal theme) or a 24-bit RGB
  # value, packed into 32 bits.
  struct Color
    RGB_FLAG = 0x0100_0000_u32

    # The terminal's default foreground or background.
    DEFAULT = new(0_u32)

    getter value : UInt32

    def initialize(@value : UInt32)
    end

    # Palette entry *index* (0-255; 0-7 are the ANSI colors, 8-15 their
    # bright variants).
    def self.palette(index : Int) : Color
      new(index.clamp(0, 255).to_u32 + 1)
    end

    # A 24-bit color.
    def self.rgb(red : Int, green : Int, blue : Int) : Color
      new(RGB_FLAG | (red.clamp(0, 255).to_u32 << 16) | (green.clamp(0, 255).to_u32 << 8) | blue.clamp(0, 255).to_u32)
    end

    def default? : Bool
      @value == 0
    end

    def rgb? : Bool
      @value & RGB_FLAG != 0
    end

    def palette? : Bool
      !default? && !rgb?
    end

    # The palette index of a palette color.
    def index : Int32
      @value.to_i - 1
    end

    def red : UInt8
      ((@value >> 16) & 0xff).to_u8
    end

    def green : UInt8
      ((@value >> 8) & 0xff).to_u8
    end

    def blue : UInt8
      (@value & 0xff).to_u8
    end

    # Writes the SGR parameters selecting this color as the *foreground* or
    # background, each after a `;`; nothing for the default color.
    def to_sgr(io : IO, foreground : Bool) : Nil
      return if default?
      if rgb?
        io << (foreground ? ";38;2;" : ";48;2;") << red << ';' << green << ';' << blue
      elsif index < 8
        io << ';' << (foreground ? 30 : 40) + index
      elsif index < 16
        io << ';' << (foreground ? 90 : 100) + index - 8
      else
        io << (foreground ? ";38;5;" : ";48;5;") << index
      end
    end
  end

  # A text rendition: attributes plus foreground and background color, and
  # the markup of the text (not written to the terminal).
  record Style, attr : Attr = Attr::None, fg : Color = Color::DEFAULT, bg : Color = Color::DEFAULT,
    markup : Markup = Markup::None do
    # Returns a copy with *extra* attributes added.
    def add(extra : Attr) : Style
      copy_with(attr: attr | extra)
    end

    # Returns a copy with different colors.
    def colors(fg : Color, bg : Color) : Style
      copy_with(fg: fg, bg: bg)
    end

    # Returns this style with *over* on top: attributes combined, each color
    # and the markup replaced where *over* has one.
    def merge(over : Style) : Style
      Style.new(attr | over.attr, over.fg.default? ? fg : over.fg, over.bg.default? ? bg : over.bg,
        over.markup.none? ? markup : over.markup)
    end

    # Writes the SGR sequence selecting this rendition from a reset state.
    def to_sgr(io : IO) : Nil
      io << "\e[0"
      io << ";1" if attr.bold?
      io << ";2" if attr.dim?
      io << ";3" if attr.italic?
      io << ";4" if attr.underline?
      io << ";7" if attr.reverse?
      io << ";9" if attr.strike?
      fg.to_sgr(io, true)
      bg.to_sgr(io, false)
      io << 'm'
    end
  end

  # Interns `Style` values into 16-bit ids so cells stay small. Id `0` is the
  # default rendition.
  module Styles
    @@list = [Style.new]
    @@ids = {Style.new => 0_u16}

    # Returns the id of *style*, registering it on first use.
    def self.id(style : Style) : UInt16
      @@ids[style] ||= begin
        @@list << style
        (@@list.size - 1).to_u16
      end
    end

    # Returns the style registered under *id*.
    def self.[](id : UInt16) : Style
      @@list[id]
    end

    # Returns the id of the style of *id* with *extra* attributes added.
    def self.add(id : UInt16, extra : Attr) : UInt16
      id(self[id].add(extra))
    end

    # Returns the id of the style of *id* with the style of *over* on top
    # (`Style#merge`).
    def self.merge(id : UInt16, over : UInt16) : UInt16
      return id if over == 0
      id(self[id].merge(self[over]))
    end
  end

  # Named roff colors: the eight ANSI colors and `default`, plus the colors
  # a page defines with `.defcolor` as 24-bit values (the screen maps them to
  # fewer colors when the terminal shows fewer).
  module Colors
    NAMES = {
      "default" => Color::DEFAULT, "black" => Color.palette(0), "red" => Color.palette(1),
      "green" => Color.palette(2), "yellow" => Color.palette(3), "blue" => Color.palette(4),
      "magenta" => Color.palette(5), "cyan" => Color.palette(6), "white" => Color.palette(7),
    }

    @@defined = Hash(String, Color).new

    # Looks up a color by roff name; unknown names yield `nil`.
    def self.[]?(name : String) : Color?
      @@defined[name]? || NAMES[name]?
    end

    # Defines *name* from a roff color specification (`rgb #rrggbb`,
    # `gray`/`grey` and `cmyk` schemes).
    def self.define(name : String, scheme : String, value : String) : Nil
      rgb = parse(scheme, value)
      @@defined[name] = rgb ? Color.rgb(*rgb) : Color::DEFAULT
    end

    private def self.parse(scheme : String, value : String) : {Int32, Int32, Int32}?
      case scheme
      when "rgb"
        if value.starts_with?("##") && value.size >= 14
          {value[2, 4].to_i(16) >> 8, value[6, 4].to_i(16) >> 8, value[10, 4].to_i(16) >> 8}
        elsif value.starts_with?('#') && value.size >= 7
          {value[1, 2].to_i(16), value[3, 2].to_i(16), value[5, 2].to_i(16)}
        else
          parts = value.split.map { |part| (part.to_f? || 0.0).clamp(0.0, 1.0) }
          parts.size == 3 ? {(parts[0] * 255).to_i, (parts[1] * 255).to_i, (parts[2] * 255).to_i} : nil
        end
      when "gray", "grey"
        level = value.starts_with?('#') ? value[1, 2].to_i(16) : ((value.to_f? || 0.0).clamp(0.0, 1.0) * 255).to_i
        {level, level, level}
      when "cmyk", "cmy"
        parts = value.split.map { |part| (part.to_f? || 0.0).clamp(0.0, 1.0) }
        k = parts[3]? || 0.0
        return nil if parts.size < 3
        {((1 - parts[0]) * (1 - k) * 255).to_i, ((1 - parts[1]) * (1 - k) * 255).to_i, ((1 - parts[2]) * (1 - k) * 255).to_i}
      end
    rescue ArgumentError
      nil
    end
  end
end
