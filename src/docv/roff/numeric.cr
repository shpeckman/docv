# src/docv/roff/numeric.cr

# :nodoc:
module Docv::Roff
  # roff numeric expressions in terminal basic units.
  module Numeric
    # Basic units per scale indicator.
    SCALE = {
      'u' => 1.0, 'n' => 24.0, 'm' => 24.0, 'i' => 240.0, 'c' => 240.0 / 2.54,
      'p' => 240.0 / 72.0, 'P' => 40.0, 'v' => 40.0, 'M' => 0.24, 's' => 1.0, 'z' => 1.0,
      'f' => 65536.0,
    }

    # Clamp for converted column and line counts; page typos would allocate huge lines.
    MAX_EXTENT = 1000

    # Units per character column.
    COLUMN = 24
    # Units per output line.
    LINE = 40

    # Evaluates *text* fully; `nil` when it is not a valid expression.
    def self.eval(text : String, unit : Char = 'u') : Int64?
      value, pos = parse(text, 0, unit)
      return nil unless value
      pos = skip_space(text, pos)
      pos >= text.size ? value : nil
    end

    # Evaluates *text* to columns (rounded) with default scale *unit*.
    def self.columns(text : String, unit : Char = 'n') : Int32?
      eval(text, unit).try { |value| (value / COLUMN).round.clamp(-MAX_EXTENT, MAX_EXTENT).to_i }
    end

    # Evaluates *text* to output lines (rounded) with default scale *unit*.
    def self.lines(text : String, unit : Char = 'v') : Int32?
      eval(text, unit).try { |value| (value / LINE).round.clamp(-MAX_EXTENT, MAX_EXTENT).to_i }
    end

    # Value at *pos* (or `nil`) and the position after it; operators have no precedence.
    def self.parse(text : String, pos : Int32, unit : Char) : {Int64?, Int32}
      value, pos = term(text, pos, unit)
      return {nil, pos} unless value
      loop do
        op, after = operator(text, pos)
        break unless op
        rhs, after = term(text, after, unit)
        break unless rhs
        value = apply(op, value, rhs)
        pos = after
      end
      {value, pos}
    end

    private def self.term(text : String, pos : Int32, unit : Char) : {Int64?, Int32}
      return {nil, pos} if pos >= text.size
      case char = text[pos]
      when '('
        value, after = parse(text, pos + 1, unit)
        return {nil, pos} unless value && text[after]? == ')'
        {value, after + 1}
      when '-'
        value, after = term(text, pos + 1, unit)
        value ? {0_i64 &- value, after} : {nil, pos}
      when '+'
        term(text, pos + 1, unit)
      when '|'
        term(text, pos + 1, unit)
      else
        return {nil, pos} unless char.ascii_number? || char == '.'
        start = pos
        while pos < text.size && (text[pos].ascii_number? || text[pos] == '.')
          pos += 1
        end
        number = text[start...pos].to_f? || 0.0
        scale = SCALE[unit]? || 1.0
        if (indicator = text[pos]?) && SCALE.has_key?(indicator)
          scale = SCALE[indicator]
          pos += 1
        end
        {(number * scale).clamp(-1e15, 1e15).round.to_i64, pos}
      end
    end

    private def self.operator(text : String, pos : Int32) : {String?, Int32}
      return {nil, pos} if pos >= text.size
      two = text[pos, 2]
      case two
      when "<=", ">=", "==", "!=", "<>", ">?", "<?"
        return {two, pos + 2}
      end
      case text[pos]
      when '+', '-', '*', '/', '%', '<', '>', '=', '&', ':'
        {text[pos].to_s, pos + 1}
      else
        {nil, pos}
      end
    end

    private def self.apply(op : String, a : Int64, b : Int64) : Int64
      case op
      when "+"        then a &+ b
      when "-"        then a &- b
      when "*"        then a &* b
      when "/"        then b == 0 ? 0_i64 : a // b
      when "%"        then b == 0 ? 0_i64 : a % b
      when "<"        then a < b ? 1_i64 : 0_i64
      when ">"        then a > b ? 1_i64 : 0_i64
      when "<="       then a <= b ? 1_i64 : 0_i64
      when ">="       then a >= b ? 1_i64 : 0_i64
      when "=", "=="  then a == b ? 1_i64 : 0_i64
      when "!=", "<>" then a != b ? 1_i64 : 0_i64
      when "&"        then a > 0 && b > 0 ? 1_i64 : 0_i64
      when ":"        then a > 0 || b > 0 ? 1_i64 : 0_i64
      when ">?"       then Math.max(a, b)
      when "<?"       then Math.min(a, b)
      else                 a
      end
    end

    private def self.skip_space(text : String, pos : Int32) : Int32
      while pos < text.size && text[pos].whitespace?
        pos += 1
      end
      pos
    end
  end
end
