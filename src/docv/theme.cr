# src/docv/theme.cr
module Docv
  # The viewer's styles by role. A role's spec is a list of words:
  # attributes (`bold`, `italic`, `underline`, `reverse`, `dim`), a
  # foreground color, and `on` followed by a background color, e.g.
  # `bold cyan`, `black on yellow`, `on background+12`.
  #
  # A color is `default`, `foreground`, `background`, an ANSI name (`black`,
  # `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, and
  # `bright-` before any of them), a palette number `0`-`255` or `#rrggbb`.
  # ANSI names and numbers are the terminal theme's own colors. A `+N` or
  # `-N` suffix ramps a color N percent toward the theme's foreground or
  # background, so `background+12` is a shade off the background in a dark
  # and a light theme alike.
  #
  # ```
  # theme = Docv::Theme.new({Docv::Theme::Role::Heading1 => Docv::Theme.parse("bold #ff8800")})
  # ids = theme.styles(Docv::Palette.new, Docv::ColorDepth::TrueColor)
  # Docv::Styles[ids[Docv::Theme::Role::Heading1.value]] # => bold, fg #ff8800
  # ```
  class Theme
    # A spec that cannot be parsed.
    class Error < Exception
    end

    # What a style is for. Page roles restyle the page text; `Text` is plain.
    enum Role
      Text
      Heading1
      Heading2
      Heading3
      Heading4
      Heading5
      Heading6
      Bold
      Italic
      BoldItalic
      Underline
      Code
      CodeBlock
      Quote
      Image
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
      Link
      LinkFocus
      TextSelection
      PageHeader
      Title
      Version
      Close
      Border
      Thumb
      Rule
      Field
      Prompt
      Placeholder
      Cursor
      Message
      Status
      StatusSeparator
      Name
      Detail
      Selection
      Hover
      Mark
      Hit
      Popup
    end

    # What a color refers to.
    enum Base
      Default
      Foreground
      Background
      Fixed
    end

    # A color of a spec: its base, the fixed color, and a ramp in percent
    # (toward the foreground when positive, the background when negative).
    record Paint, base : Base = Base::Default, color : Color = Color::DEFAULT, ramp : Int32 = 0 do
      # The color for *palette*, as a foreground or background. Ramped
      # colors are RGB; others stay palette colors of the terminal theme.
      def resolve(palette : Palette, foreground : Bool) : Color
        if ramp == 0
          return color if base.fixed?
          return Color::DEFAULT if base.default? || (base.foreground? && foreground) || (base.background? && !foreground)
        end
        start = case base
                in .default?    then foreground ? palette.foreground : palette.background
                in .foreground? then palette.foreground
                in .background? then palette.background
                in .fixed?      then palette.rgb(color, foreground)
                end
        rgb = palette.ramp(start, ramp)
        Color.rgb(rgb.red, rgb.green, rgb.blue)
      end
    end

    # A parsed spec.
    record Spec, attr : Attr = Attr::None, fg : Paint = Paint.new, bg : Paint = Paint.new do
      def style(palette : Palette) : Style
        Style.new(attr, fg.resolve(palette, true), bg.resolve(palette, false))
      end
    end

    ATTRIBUTES = {
      "bold" => Attr::Bold, "italic" => Attr::Italic, "underline" => Attr::Underline,
      "reverse" => Attr::Reverse, "dim" => Attr::Dim,
    }

    # Color names: the bases, then the ANSI colors and their bright variants.
    COLORS = begin
      names = {"default" => Paint.new, "foreground" => Paint.new(Base::Foreground), "background" => Paint.new(Base::Background)}
      %w(black red green yellow blue magenta cyan white).each_with_index do |name, index|
        names[name] = Paint.new(Base::Fixed, Color.palette(index))
        names["bright-#{name}"] = Paint.new(Base::Fixed, Color.palette(index + 8))
      end
      names
    end

    # A color word with an optional ramp.
    PAINT = /\A([a-z0-9#]+(?:-[a-z]+)?)(?:([+-])(\d{1,3}))?\z/

    # The colored theme.
    DEFAULT = {
      Role::Text              => "",
      Role::Heading1          => "bold bright-blue",
      Role::Heading2          => "bold blue",
      Role::Heading3          => "bold bright-magenta",
      Role::Heading4          => "bold magenta",
      Role::Heading5          => "bold",
      Role::Heading6          => "bold foreground-40",
      Role::Bold              => "bold cyan",
      Role::Italic            => "underline green",
      Role::BoldItalic        => "bold underline green",
      Role::Underline         => "underline",
      Role::Code              => "yellow on background+8",
      Role::CodeBlock         => "yellow",
      Role::Quote             => "foreground-60",
      Role::Image             => "italic foreground-40",
      Role::SyntaxKeyword     => "bold magenta",
      Role::SyntaxString      => "green",
      Role::SyntaxComment     => "italic foreground-45",
      Role::SyntaxFunction    => "blue",
      Role::SyntaxType        => "cyan",
      Role::SyntaxConstant    => "red",
      Role::SyntaxOperator    => "foreground-15",
      Role::SyntaxPunctuation => "foreground-35",
      Role::SyntaxProperty    => "bright-cyan",
      Role::SyntaxTag         => "bright-blue",
      Role::Link              => "underline magenta",
      Role::LinkFocus         => "reverse magenta",
      Role::TextSelection     => "on blue-50",
      Role::PageHeader        => "bold",
      Role::Title             => "bold",
      Role::Version           => "foreground-50",
      Role::Close             => "red",
      Role::Border            => "foreground-60",
      Role::Thumb             => "bold blue",
      Role::Rule              => "foreground-70",
      Role::Field             => "on background+12",
      Role::Prompt            => "bold blue",
      Role::Placeholder       => "foreground-50",
      Role::Cursor            => "reverse",
      Role::Message           => "yellow",
      Role::Status            => "foreground-30",
      Role::StatusSeparator   => "foreground-60",
      Role::Name              => "bold cyan",
      Role::Detail            => "foreground-35",
      Role::Selection         => "on background+22",
      Role::Hover             => "on background+10",
      Role::Mark              => "bold underline yellow",
      Role::Hit               => "bold green",
      Role::Popup             => "on background+6",
    }

    # The theme without colors (`NO_COLOR`): attributes only.
    MONOCHROME = {
      Role::Text              => "",
      Role::Heading1          => "bold",
      Role::Heading2          => "bold",
      Role::Heading3          => "bold",
      Role::Heading4          => "bold",
      Role::Heading5          => "bold",
      Role::Heading6          => "bold dim",
      Role::Bold              => "bold",
      Role::Italic            => "underline",
      Role::BoldItalic        => "bold underline",
      Role::Underline         => "underline",
      Role::Code              => "reverse",
      Role::CodeBlock         => "",
      Role::Quote             => "dim",
      Role::Image             => "dim",
      Role::SyntaxKeyword     => "bold",
      Role::SyntaxString      => "",
      Role::SyntaxComment     => "dim",
      Role::SyntaxFunction    => "",
      Role::SyntaxType        => "",
      Role::SyntaxConstant    => "",
      Role::SyntaxOperator    => "",
      Role::SyntaxPunctuation => "",
      Role::SyntaxProperty    => "",
      Role::SyntaxTag         => "",
      Role::Link              => "underline",
      Role::LinkFocus         => "reverse",
      Role::TextSelection     => "reverse",
      Role::PageHeader        => "bold",
      Role::Title             => "bold",
      Role::Version           => "dim",
      Role::Close             => "",
      Role::Border            => "dim",
      Role::Thumb             => "bold",
      Role::Rule              => "dim",
      Role::Field             => "",
      Role::Prompt            => "bold",
      Role::Placeholder       => "dim",
      Role::Cursor            => "reverse",
      Role::Message           => "",
      Role::Status            => "",
      Role::StatusSeparator   => "dim",
      Role::Name              => "bold",
      Role::Detail            => "dim",
      Role::Selection         => "reverse",
      Role::Hover             => "bold",
      Role::Mark              => "bold underline",
      Role::Hit               => "bold",
      Role::Popup             => "",
    }

    # Config keys of the roles: `heading1`, `bold-italic`, `code-block`...
    KEYS = Role.values.to_h { |role| {Theme.key(role), role} }

    @@default_specs : Hash(Role, Spec)? = nil
    @@monochrome_specs : Hash(Role, Spec)? = nil

    # The config key of *role*.
    def self.key(role : Role) : String
      role.to_s.underscore.tr("_", "-")
    end

    # Parses a spec; raises `Error` on unknown words.
    def self.parse(text : String) : Spec
      attr = Attr::None
      fg = nil
      bg = nil
      background = false
      text.downcase.split.each do |word|
        if extra = ATTRIBUTES[word]?
          attr |= extra
        elsif word == "on"
          raise Error.new("\"on\" given twice in #{text.inspect}") if background
          background = true
        else
          paint = paint(word) || raise Error.new("unknown color or attribute #{word.inspect} in #{text.inspect}")
          if background
            raise Error.new("two background colors in #{text.inspect}") if bg
            bg = paint
          else
            raise Error.new("two foreground colors in #{text.inspect}") if fg
            fg = paint
          end
        end
      end
      raise Error.new("\"on\" without a color in #{text.inspect}") if background && bg.nil?
      Spec.new(attr, fg || Paint.new, bg || Paint.new)
    end

    private def self.paint(word : String) : Paint?
      match = word.match(PAINT) || return nil
      name = match[1]
      paint = COLORS[name]? || fixed(name) || return nil
      if digits = match[3]?
        amount = digits.to_i
        return nil if amount > 100
        paint = paint.copy_with(ramp: match[2] == "-" ? -amount : amount)
      end
      paint
    end

    private def self.fixed(name : String) : Paint?
      if name.starts_with?('#')
        return nil unless name.size == 7 && name[1..].each_char.all?(&.hex?)
        Paint.new(Base::Fixed, Color.rgb(name[1, 2].to_i(16), name[3, 2].to_i(16), name[5, 2].to_i(16)))
      elsif (index = name.to_i?) && 0 <= index <= 255
        Paint.new(Base::Fixed, Color.palette(index))
      end
    end

    # `DEFAULT` parsed.
    def self.default_specs : Hash(Role, Spec)
      @@default_specs ||= DEFAULT.transform_values { |text| parse(text) }
    end

    # `MONOCHROME` parsed.
    def self.monochrome_specs : Hash(Role, Spec)
      @@monochrome_specs ||= MONOCHROME.transform_values { |text| parse(text) }
    end

    getter specs : Hash(Role, Spec)

    # The default theme with *overrides* (from `[colors]` in config.ini).
    def initialize(overrides : Hash(Role, Spec) = {} of Role => Spec)
      @specs = Theme.default_specs.merge(overrides)
    end

    # The style id of every role for *palette* at *depth*, indexed by
    # `Role#value`. At `ColorDepth::None` the roles take `MONOCHROME`.
    def styles(palette : Palette, depth : ColorDepth) : Array(UInt16)
      table = depth.none? ? Theme.monochrome_specs : @specs
      Role.values.map { |role| Styles.id(table[role].style(palette)) }
    end
  end
end
