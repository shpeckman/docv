# src/docv/style.cr

module Docv
  # Text attributes of a `Style`.
  @[Flags]
  enum Attr : UInt8
    Bold
    Italic
    Underline
    Reverse
    Dim
    Strike
  end

  # What a piece of text is (code, quote bar, syntax class...), set by the
  # parsers; the viewer draws each kind in its own `Theme::Role`.
  enum Markup : UInt8
    None
    # Inline code.
    Code
    # A code block line.
    CodeBlock
    # A block quote bar.
    Quote
    # A horizontal rule.
    Rule
    # The text standing for an image.
    Image
    # Highlighted code, by syntax class (`Syntax::CAPTURES`).
    SyntaxKeyword
    SyntaxString
    SyntaxComment
    SyntaxFunction
    SyntaxType
    SyntaxConstant
    SyntaxOperator
    SyntaxPunctuation
    SyntaxProperty
    SyntaxTag
  end

  # How many colors the terminal shows.
  enum ColorDepth : UInt8
    # No colors (`NO_COLOR`); attributes only.
    None
    # The 16 ANSI colors.
    Ansi
    # The 256-color palette.
    Palette
    # 24-bit RGB.
    TrueColor
  end

  # A terminal color in 32 bits: the default color, an entry of the
  # 256-color palette, or 24-bit RGB.
  struct Color
    # :nodoc:
    RGB_FLAG = 0x0100_0000_u32

    # The terminal's default foreground or background.
    DEFAULT = new(0_u32)

    getter value : UInt32

    def initialize(@value : UInt32)
    end

    # Palette entry *index* (0-255; 0-15 are the ANSI colors).
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

    # Writes `;`-prefixed SGR parameters selecting this color as *foreground*
    # or background; nothing for the default color.
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

  # A text style: attributes, foreground and background colors, and the
  # `Markup` of the text (not written to the terminal).
  record Style, attr : Attr = Attr::None, fg : Color = Color::DEFAULT, bg : Color = Color::DEFAULT,
    markup : Markup = Markup::None do
    # A copy with *extra* attributes added.
    def add(extra : Attr) : Style
      copy_with(attr: attr | extra)
    end

    # A copy with other colors.
    def colors(fg : Color, bg : Color) : Style
      copy_with(fg: fg, bg: bg)
    end

    # This style with *over* on top: attributes combined, colors and markup
    # replaced where *over* sets them.
    def merge(over : Style) : Style
      Style.new(attr | over.attr, over.fg.default? ? fg : over.fg, over.bg.default? ? bg : over.bg,
        over.markup.none? ? markup : over.markup)
    end

    # Writes the SGR sequence selecting this style from a reset state.
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

  # Interns `Style` values as 16-bit ids; id `0` is the default style.
  module Styles
    @@list = [Style.new]
    @@ids = {Style.new => 0_u16}

    # The id of *style*, registered on first use.
    def self.id(style : Style) : UInt16
      @@ids[style] ||= begin
        @@list << style
        (@@list.size - 1).to_u16
      end
    end

    # The style of *id*.
    def self.[](id : UInt16) : Style
      @@list[id]
    end

    # The id of *id*'s style with *extra* attributes added.
    def self.add(id : UInt16, extra : Attr) : UInt16
      id(self[id].add(extra))
    end

    # The id of *id*'s style with *over*'s on top (`Style#merge`).
    def self.merge(id : UInt16, over : UInt16) : UInt16
      return id if over == 0
      id(self[id].merge(self[over]))
    end
  end

  # :nodoc:
  # Named roff colors, including those a page defines with `.defcolor`.
  module Colors
    NAMES = {
      "default" => Color::DEFAULT, "black" => Color.palette(0), "red" => Color.palette(1),
      "green" => Color.palette(2), "yellow" => Color.palette(3), "blue" => Color.palette(4),
      "magenta" => Color.palette(5), "cyan" => Color.palette(6), "white" => Color.palette(7),
    }

    @@defined = Hash(String, Color).new

    def self.[]?(name : String) : Color?
      @@defined[name]? || NAMES[name]?
    end

    # *scheme* is `rgb`, `gray`/`grey` or `cmy`/`cmyk`, as in `.defcolor`.
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
