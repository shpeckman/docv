# src/docv/roff/interpolate.cr
module Docv::Roff
  class Engine
    # Maximum nesting of string interpolation.
    MAX_INTERPOLATION = 32

    # Expands strings (`\*`), registers (`\n`, `\g`), macro arguments (`\$`),
    # widths (`\w`), `\B`, `\A`, `\R`, `\V` (environment variables, with
    # `Options#unsafe` only) and comments. In copy mode (macro
    # bodies, string values, macro arguments) `\\` becomes `\`, `\.` becomes
    # `.` and `\t`/`\a` become literal characters; other escapes are kept for
    # the inline formatter.
    # Conditional braces `\{` `\}` are kept only with *braces* (macro
    # bodies, where they still have to delimit blocks when the body runs).
    def interpolate(text : String, copy : Bool, depth : Int32 = 0, braces : Bool = false) : String
      return text unless text.includes?('\\')
      String.build(text.bytesize + 16) { |io| interpolate_into(io, text, copy, depth, braces) }
    end

    private def interpolate_into(io : IO, text : String, copy : Bool, depth : Int32, braces : Bool = false) : Nil
      reader = Cursor.new(text)
      while reader.has_next?
        char = reader.current_char
        reader.next_char
        unless char == '\\'
          io << char
          next
        end
        unless reader.has_next?
          io << '\\' unless copy
          break
        end
        escape = reader.current_char
        reader.next_char
        case escape
        when '\\'
          copy ? (io << '\\') : (io << "\\\\")
        when '.'
          copy ? (io << '.') : (io << "\\.")
        when '"'
          break
        when '#'
          break
        when 'n'
          sign = 0
          if reader.has_next? && (reader.current_char == '+' || reader.current_char == '-')
            sign = reader.current_char == '+' ? 1 : -1
            reader.next_char
          end
          io << register_text(read_name(reader), sign)
        when 'g'
          name = read_name(reader)
          io << (@registers[name]?.try(&.format) || "")
        when '*'
          name, args = read_string_name(reader)
          if (value = string(name)) && depth < MAX_INTERPOLATION
            if args.empty?
              interpolate_into(io, value, copy, depth + 1)
            else
              run_with_args(args) { interpolate_into(io, value, copy, depth + 1) }
            end
          end
        when '$'
          interpolate_into(io, macro_argument(reader), copy, depth + 1) if depth < MAX_INTERPOLATION
        when 'V'
          name = read_name(reader)
          io << (ENV[name]? || "") if @options.unsafe
        when 'w'
          arg = read_delimited(reader)
          width = Unicode.text_width(plain_text(interpolate(arg, false, depth + 1)))
          io << width * Numeric::COLUMN
        when 'B'
          arg = read_delimited(reader)
          io << (Numeric.eval(interpolate(arg, true, depth + 1)) ? '1' : '0')
        when 'A'
          arg = read_delimited(reader)
          io << (arg.empty? || arg.each_char.any? { |c| c.whitespace? || c.control? } ? '0' : '1')
        when 'R'
          arg = interpolate(read_delimited(reader), true, depth + 1).lstrip
          name, _, expr = arg.partition(' ')
          set_register_expression(name, expr.strip) unless name.empty?
        when '{', '}'
          io << '\\' << escape if braces
        when 't'
          copy ? (io << '\t') : (io << "\\t")
        when 'a'
          copy ? (io << '\t') : (io << "\\a")
        when 'E'
          io << '\\'
        when '\n'
        else
          io << '\\' << escape
        end
      end
    end

    # Sets register *name* from an expression; a leading sign adds to the
    # current value.
    def set_register_expression(name : String, expr : String, increment : String? = nil) : Nil
      return if expr.empty?
      relative = expr[0] == '+' || expr[0] == '-'
      value = Numeric.eval(expr, 'u') || return
      value = value &+ register_value(name) if relative && @registers.has_key?(name)
      step = increment.try { |text| Numeric.eval(text, 'u') }
      @registers.set(name, value, step)
    end

    # Reads a one-character, `(xx` or `[name]` identifier.
    def read_name(reader : Cursor) : String
      return "" unless reader.has_next?
      char = reader.current_char
      reader.next_char
      case char
      when '('
        String.build do |io|
          2.times do
            break unless reader.has_next?
            io << reader.current_char
            reader.next_char
          end
        end
      when '['
        String.build do |io|
          while reader.has_next? && reader.current_char != ']'
            io << reader.current_char
            reader.next_char
          end
          reader.next_char if reader.has_next?
        end
      else
        char.to_s
      end
    end

    # Reads a string reference: `x`, `(xx` or `[name arg ...]`.
    private def read_string_name(reader : Cursor) : {String, Array(String)}
      return {"", [] of String} unless reader.has_next?
      if reader.current_char == '['
        reader.next_char
        inner = String.build do |io|
          while reader.has_next? && reader.current_char != ']'
            io << reader.current_char
            reader.next_char
          end
          reader.next_char if reader.has_next?
        end
        parts = split_args(inner)
        {parts.first? || "", parts.size > 1 ? parts[1..] : [] of String}
      else
        {read_name(reader), [] of String}
      end
    end

    # Reads the argument of an escape delimited by its first character.
    def read_delimited(reader : Cursor) : String
      return "" unless reader.has_next?
      delim = reader.current_char
      reader.next_char
      String.build do |io|
        while reader.has_next?
          char = reader.current_char
          reader.next_char
          break if char == delim
          io << char
          if char == '\\' && reader.has_next?
            io << reader.current_char
            reader.next_char
          end
        end
      end
    end

    private def macro_argument(reader : Cursor) : String
      return "" unless reader.has_next?
      args = current_args
      char = reader.current_char
      reader.next_char
      case char
      when '*' then args.join(' ')
      when '@' then args.map { |arg| "\"#{arg}\"" }.join(' ')
      when '^' then args.map { |arg| "\"#{arg.gsub('"', "\"\"")}\"" }.join(' ')
      when '0' then macro_frame.try(&.name) || ""
      when '('
        digits = String.build do |io|
          2.times do
            break unless reader.has_next?
            io << reader.current_char
            reader.next_char
          end
        end
        args[(digits.to_i? || 0) - 1]? || ""
      when '['
        digits = String.build do |io|
          while reader.has_next? && reader.current_char != ']'
            io << reader.current_char
            reader.next_char
          end
          reader.next_char if reader.has_next?
        end
        args[(digits.to_i? || 0) - 1]? || ""
      else
        char.ascii_number? ? (args[char.to_i - 1]? || "") : ""
      end
    end

    private def run_with_args(args : Array(String), &) : Nil
      @frames << Frame.new(Frame::Kind::Macro, [] of String, "string", args)
      begin
        yield
      ensure
        @frames.pop
      end
    end
  end
end
