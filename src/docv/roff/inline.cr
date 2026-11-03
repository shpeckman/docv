# src/docv/roff/inline.cr
module Docv::Roff
  class Engine
    # Formats an interpolated text line into the builder. Returns true when
    # the line ends with `\c` (the next input line continues it).
    def emit(text : String) : Bool
      Inline.new(self, nil).run(text)
    end

    # Formats *text* into plain characters without changing any state
    # (widths, string comparison, headings).
    def plain_text(text : String) : String
      return text unless text.includes?('\\') || !@translations.empty?
      String.build { |io| Inline.new(self, io).run(text) }
    end
  end

  # The inline formatter: turns escapes into characters, font and color
  # changes, motions and continuation.
  class Inline
    @buffer = String::Builder.new
    @break_after = false

    def initialize(@engine : Engine, @sink : IO?)
    end

    # Formats *text*; returns true when it ended with `\c`.
    def run(text : String) : Bool
      continued = format(Cursor.new(text))
      flush
      @engine.builder.break_line if @break_after && @sink.nil?
      continued
    end

    private def format(reader : Cursor) : Bool
      while char = reader.take
        if char != '\\' || !reader.has_next?
          put_char(char)
          next
        end
        escape = reader.take.not_nil!
        case escape
        when '\\', 'e', 'E' then put("\\")
        when '-'            then put("-")
        when '.'            then put(".")
        when '\''           then put("´")
        when '`'            then put("`")
        when '_'            then put("_")
        when ' ', '~', '0'  then put(" ")
        when '|', '^', '&', ')', '%', ':', '/', ',', '{', '}', 'u', 'd', 'r', '\n'
        when '!'
          break
        when '?'
          skip_transparent(reader)
        when 'c'
          return true
        when 'p'
          @break_after = true
        when 't', 'a'
          put("\t")
        when '('
          name = String.build { |io| 2.times { reader.take.try { |c| io << c } } }
          glyph(name)
        when '['
          glyph(read_until(reader, ']'))
        when 'C'
          glyph(@engine.read_delimited(reader))
        when 'N'
          code = @engine.read_delimited(reader).to_i?
          put(code.chr.to_s) if code && 0 < code <= 0x10FFFF
        when 'f'
          name = @engine.read_name(reader)
          state { @engine.select_font(name) }
        when 'F', 'Y'
          @engine.read_name(reader)
        when 'k'
          name = @engine.read_name(reader)
          @engine.registers.set(name, 0_i64) unless @sink
        when 's'
          skip_size(reader)
        when 'm'
          name = @engine.read_name(reader)
          state do
            env = @engine.env
            env.prev_fg, env.fg = env.fg, (name.empty? ? env.prev_fg : Colors[name]? || env.fg)
          end
        when 'M'
          name = @engine.read_name(reader)
          state do
            env = @engine.env
            env.prev_bg, env.bg = env.bg, (name.empty? ? env.prev_bg : Colors[name]? || env.bg)
          end
        when 'h'
          arg = @engine.read_delimited(reader)
          columns = Numeric.columns(arg.lstrip('|'), 'm') || 0
          put(" " * columns) if columns > 0
        when 'l'
          rule(@engine.read_delimited(reader))
        when 'v', 'x', 'X', 'D', 'L', 'H', 'S', 'R', 'A', 'B', 'w'
          @engine.read_delimited(reader)
        when 'O'
          reader.current_char == '[' ? (reader.next_char; read_until(reader, ']')) : reader.next_char
        when 'Z'
          format(Cursor.new(@engine.read_delimited(reader)))
        when 'b', 'o'
          pile = @engine.read_delimited(reader)
          format(Cursor.new(first_glyph(pile)))
        when 'z', 'j'
        when 'n', '*', 'g', 'V'
          @engine.read_name(reader)
        when '$'
          reader.next_char
        else
          put(escape.to_s)
        end
      end
      false
    end

    private def put_char(char : Char) : Nil
      unless @engine.translations.empty?
        if mapped = @engine.translations[char]?
          @buffer << mapped
          return
        end
      end
      unless @engine.glyphs.empty?
        if defined = @engine.glyphs[char.to_s]?
          format(Cursor.new(defined))
          return
        end
      end
      @buffer << (char == '\u0001' ? '\t' : char)
    end

    private def put(text : String) : Nil
      @buffer << text
    end

    private def glyph(name : String) : Nil
      if defined = @engine.glyphs[name]?
        format(Cursor.new(defined))
      elsif found = Chars[name]?
        put(found)
      elsif name.size == 1
        put(name)
      end
    end

    # Applies a state change (font, color) after flushing text set in the
    # previous state; skipped when only collecting plain text.
    private def state(&) : Nil
      return if @sink
      flush
      yield
    end

    private def flush : Nil
      return if @buffer.empty?
      text = @buffer.to_s
      @buffer = String::Builder.new
      if sink = @sink
        sink << text
      else
        @engine.builder.text(text, @engine.env.style)
      end
    end

    private def read_until(reader : Cursor, terminator : Char) : String
      String.build do |io|
        while char = reader.take
          break if char == terminator
          io << char
        end
      end
    end

    private def skip_transparent(reader : Cursor) : Nil
      while char = reader.take
        if char == '\\' && reader.has_next? && reader.current_char == '?'
          reader.next_char
          return
        end
      end
    end

    private def skip_size(reader : Cursor) : Nil
      return unless reader.has_next?
      reader.next_char if reader.current_char == '+' || reader.current_char == '-'
      return unless reader.has_next?
      case reader.current_char
      when '('
        reader.next_char
        reader.next_char if reader.has_next? && (reader.current_char == '+' || reader.current_char == '-')
        2.times { reader.next_char }
      when '['
        reader.next_char
        read_until(reader, ']')
      when '\''
        reader.next_char
        read_until(reader, '\'')
      else
        first = reader.current_char
        return unless first.ascii_number?
        reader.next_char
        reader.next_char if '1' <= first <= '3' && reader.has_next? && reader.current_char.ascii_number?
      end
    end

    # `\l'Nc'`: a horizontal rule of N in character c (default box rule).
    private def rule(arg : String) : Nil
      match = arg.match(/\A\|?([0-9.+\-*\/()]+[uinmcpPvMsz]?)(.*)\z/)
      return unless match
      columns = Numeric.columns(match[1], 'm') || 0
      return if columns <= 0
      char = match[2].empty? ? "─" : String.build { |io| Inline.new(@engine, io).run(match[2]) }
      char = "─" if char.empty?
      put(char * columns)
    end

    private def first_glyph(text : String) : String
      return text if text.empty?
      if text.starts_with?('\\')
        cursor = Cursor.new(text)
        cursor.next_char
        case cursor.current_char
        when '(' then return text[0, 4]
        when '['
          close = text.index(']')
          return close ? text[0..close] : text
        else
          return text[0, 2]
        end
      end
      text[0].to_s
    end
  end
end
