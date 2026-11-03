# src/docv/palette.cr
module Docv
  # The colors of the terminal theme as RGB: the default foreground and
  # background and the 256-color palette. A terminal reports its theme in
  # answer to an OSC 21 query (`set`); until then xterm's values stand in,
  # on a black or white background for a dark or light scheme.
  #
  # Colors can be ramped toward the foreground or the background, and
  # reduced to what the terminal shows.
  #
  # ```
  # palette = Docv::Palette.new(dark: true)
  # palette.set("background", "rgb:28/2c/34")
  # palette.ramp(palette.background, 10) # 10% toward the foreground
  # ```
  class Palette
    # A 24-bit color value.
    record RGB, red : UInt8, green : UInt8, blue : UInt8 do
      # Relative luminance, 0.0 (black) to 1.0 (white).
      def luminance : Float64
        (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255.0
      end

      # Squared distance to *other*.
      def distance(other : RGB) : Int32
        (red.to_i - other.red) ** 2 + (green.to_i - other.green) ** 2 + (blue.to_i - other.blue) ** 2
      end

      # The color *amount* (0.0-1.0) of the way to *other*.
      def mix(other : RGB, amount : Float64) : RGB
        RGB.new(blend(red, other.red, amount), blend(green, other.green, amount), blend(blue, other.blue, amount))
      end

      private def blend(from : UInt8, to : UInt8, amount : Float64) : UInt8
        (from + (to.to_f - from) * amount).round.clamp(0, 255).to_u8
      end
    end

    # xterm's values of the 16 ANSI colors.
    ANSI = [
      {0, 0, 0}, {205, 0, 0}, {0, 205, 0}, {205, 205, 0}, {0, 0, 238}, {205, 0, 205}, {0, 205, 205}, {229, 229, 229},
      {127, 127, 127}, {255, 0, 0}, {0, 255, 0}, {255, 255, 0}, {92, 92, 255}, {255, 0, 255}, {0, 255, 255}, {255, 255, 255},
    ]
    # Channel levels of the 6×6×6 color cube (palette entries 16-231).
    CUBE = [0, 95, 135, 175, 215, 255]

    getter foreground : RGB
    getter background : RGB
    # True once the terminal reported a color.
    getter? reported : Bool = false

    @colors : Array(RGB)

    def initialize(dark : Bool = true)
      @colors = Array(RGB).new(256) { |index| Palette.standard(index) }
      @foreground = dark ? @colors[7] : @colors[0]
      @background = dark ? @colors[0] : @colors[15]
    end

    # xterm's value of palette entry *index*.
    def self.standard(index : Int32) : RGB
      if index < 16
        red, green, blue = ANSI[index]
        RGB.new(red.to_u8, green.to_u8, blue.to_u8)
      elsif index < 232
        cube = index - 16
        RGB.new(CUBE[cube // 36].to_u8, CUBE[cube // 6 % 6].to_u8, CUBE[cube % 6].to_u8)
      else
        level = (8 + (index - 232) * 10).to_u8
        RGB.new(level, level, level)
      end
    end

    # Parses a color value of OSC 21: `rgb:r/g/b` (1-4 hex digits per
    # channel, scaled), `#rgb` to `#rrrrggggbbbb` (most significant bits) or
    # `rgbi:r/g/b` (0.0-1.0); an `@alpha` suffix is ignored. `nil` for an
    # empty or unknown value.
    def self.parse(value : String) : RGB?
      text = value.split('@').first.strip.downcase
      if text.starts_with?("rgb:")
        channels = text[4..].split('/')
        return nil unless channels.size == 3
        red, green, blue = channels.map { |channel| scaled(channel) || return nil }
        RGB.new(red, green, blue)
      elsif text.starts_with?("rgbi:")
        channels = text[5..].split('/')
        return nil unless channels.size == 3
        red, green, blue = channels.map { |channel| ((channel.to_f? || return nil).clamp(0.0, 1.0) * 255).round.to_u8 }
        RGB.new(red, green, blue)
      elsif text.starts_with?('#')
        digits = text[1..]
        return nil unless digits.size.in?(3, 6, 9, 12) && digits.each_char.all?(&.hex?)
        width = digits.size // 3
        red, green, blue = (0...3).map { |channel| significant(digits[channel * width, width]) }
        RGB.new(red, green, blue)
      end
    end

    private def self.scaled(hex : String) : UInt8?
      return nil unless 1 <= hex.size <= 4 && hex.each_char.all?(&.hex?)
      (hex.to_i(16) * 255 // (16 ** hex.size - 1)).to_u8
    end

    private def self.significant(hex : String) : UInt8
      value = hex.to_i(16)
      shift = 4 * hex.size - 8
      (shift >= 0 ? value >> shift : value << -shift).to_u8
    end

    # Sets the color of an OSC 21 *key* (`foreground`, `background` or a
    # palette index) from *value*; false for keys and values it does not
    # take.
    def set(key : String, value : String) : Bool
      rgb = Palette.parse(value) || return false
      case key
      when "foreground" then @foreground = rgb
      when "background" then @background = rgb
      else
        index = key.to_i? || return false
        return false unless 0 <= index < 256
        @colors[index] = rgb
      end
      @reported = true
      true
    end

    # True when the background is dark.
    def dark? : Bool
      @background.luminance < 0.5
    end

    # The RGB value of *color* as a foreground or background.
    def rgb(color : Color, foreground : Bool) : RGB
      if color.default?
        foreground ? @foreground : @background
      elsif color.rgb?
        RGB.new(color.red, color.green, color.blue)
      else
        @colors[color.index]
      end
    end

    # *rgb* moved *percent* toward the foreground (positive) or the
    # background (negative).
    def ramp(rgb : RGB, percent : Int32) : RGB
      return rgb if percent == 0
      rgb.mix(percent > 0 ? @foreground : @background, percent.abs.clamp(0, 100) / 100.0)
    end

    # *color* as the terminal shows it at *depth*: RGB colors, and palette
    # entries past the ANSI colors at `ColorDepth::Ansi`, become the nearest
    # palette entry; at `ColorDepth::None` every color is the default.
    def reduce(color : Color, depth : ColorDepth) : Color
      case depth
      in .true_color? then color
      in .none?       then Color::DEFAULT
      in .palette?    then color.rgb? ? Color.palette(nearest(rgb(color, true), 256)) : color
      in .ansi?
        return color if color.default? || (color.palette? && color.index < 16)
        Color.palette(nearest(rgb(color, true), 16))
      end
    end

    private def nearest(target : RGB, count : Int32) : Int32
      best = 0
      best_distance = Int32::MAX
      count.times do |index|
        distance = @colors[index].distance(target)
        if distance < best_distance
          best_distance = distance
          best = index
        end
      end
      best
    end
  end
end
