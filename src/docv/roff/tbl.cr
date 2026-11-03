# src/docv/roff/tbl.cr
module Docv::Roff
  # The tbl(1) preprocessor: reads a `.TS` ... `.TE` region from the input
  # and adds a `Table` block.
  class Tbl
    # The layout of one cell from a format row.
    record Spec, kind : Table::CellKind, align : Table::CellAlign, font : Font?, width : Int32, gap : Int32

    @tab = '\t'
    @formats = [] of Array(Spec)
    @vrules = [] of Int32
    @table = Table.new

    def initialize(@engine : Engine)
    end

    # Reads the table body from the input stack and emits it.
    def run(args : String) : Nil
      lines = read_region
      index = 0
      if (first = lines[0]?) && options?(first)
        options(first)
        index = 1
      end
      index = formats(lines, index)
      data(lines, index)
      finish
    end

    private def read_region : Array(String)
      lines = [] of String
      floor = @engine.frame_depth - 1
      while line = @engine.next_line(floor)
        stripped = line.lstrip
        break if stripped.starts_with?(".TE") || stripped.starts_with?("'TE")
        next if stripped.starts_with?(".TH") || stripped.starts_with?("'TH")
        lines << line
      end
      lines
    end

    private def options?(line : String) : Bool
      line.rstrip.ends_with?(';')
    end

    private def options(line : String) : Nil
      text = line.rstrip.rchop(';')
      text.scan(/([a-zA-Z]+)\s*(?:\(([^)]*)\))?/) do |match|
        name = match[1].downcase
        value = match[2]?
        case name
        when "center", "centre"         then @table.center = true
        when "expand"                   then @table.expand = true
        when "box", "frame"             then @table.frame = Table::Frame::Box
        when "doublebox", "doubleframe" then @table.frame = Table::Frame::DoubleBox
        when "allbox"
          @table.allbox = true
          @table.frame = Table::Frame::Box
        when "tab"
          @tab = value.try(&.[0]?) || '\t'
        end
      end
    end

    # Parses format rows up to the one ending in `.`; returns the next index.
    private def formats(lines : Array(String), index : Int32) : Int32
      @formats.clear
      while index < lines.size
        line = lines[index]
        index += 1
        finished = line.rstrip.ends_with?('.')
        text = finished ? line.rstrip.rchop('.') : line
        text.split(',').each do |row|
          specs = format_row(row)
          @formats << specs unless specs.empty?
        end
        break if finished
      end
      @formats << [Spec.new(Table::CellKind::Text, Table::CellAlign::Left, nil, 0, 3)] if @formats.empty?
      index
    end

    private def format_row(row : String) : Array(Spec)
      specs = [] of Spec
      rules = [0]
      chars = row.chars
      index = 0
      while index < chars.size
        char = chars[index]
        index += 1
        case char
        when '|'
          rules[-1] += 1
          next
        when ' ', '\t'
          next
        end
        kind, align = key(char) || next
        font = nil
        width = 0
        gap = 3
        while index < chars.size
          modifier = chars[index]
          case modifier
          when 'b', 'B'
            font = Font::Bold
            index += 1
          when 'i', 'I'
            font = Font::Italic
            index += 1
          when 'f', 'F'
            index += 1
            name, index = font_name(chars, index)
            font = Font.from_name(name)
          when 'w', 'W'
            index += 1
            text, index = parenthesized(chars, index)
            width = Numeric.columns(text, 'n') || 0
          when 'p', 'P', 'v', 'V'
            index += 1
            index += 1 if index < chars.size && (chars[index] == '+' || chars[index] == '-')
            while index < chars.size && chars[index].ascii_number?
              index += 1
            end
          when 't', 'T', 'u', 'U', 'e', 'E', 'z', 'Z', 'x', 'X', 'd', 'D', 'm', 'M'
            index += 1
          when '0'..'9'
            start = index
            while index < chars.size && chars[index].ascii_number?
              index += 1
            end
            gap = chars[start...index].join.to_i
          when '(' # stray parenthesized argument
            _, index = parenthesized(chars, index)
          else
            break
          end
        end
        specs << Spec.new(kind, align, font, width, gap)
        rules << 0
      end
      @vrules = rules if @formats.empty? && !specs.empty?
      specs
    end

    private def key(char : Char) : {Table::CellKind, Table::CellAlign}?
      case char
      when 'l', 'L' then {Table::CellKind::Text, Table::CellAlign::Left}
      when 'r', 'R' then {Table::CellKind::Text, Table::CellAlign::Right}
      when 'c', 'C' then {Table::CellKind::Text, Table::CellAlign::Center}
      when 'n', 'N' then {Table::CellKind::Text, Table::CellAlign::Numeric}
      when 'a', 'A' then {Table::CellKind::Text, Table::CellAlign::Alpha}
      when 's', 'S' then {Table::CellKind::HSpan, Table::CellAlign::Left}
      when '^'      then {Table::CellKind::VSpan, Table::CellAlign::Left}
      when '_', '-' then {Table::CellKind::Rule, Table::CellAlign::Left}
      when '='      then {Table::CellKind::DoubleRule, Table::CellAlign::Left}
      end
    end

    private def font_name(chars : Array(Char), index : Int32) : {String, Int32}
      return {"R", index} if index >= chars.size
      if chars[index] == '('
        text, after = parenthesized(chars, index)
        return {text, after}
      end
      if chars[index] == '['
        close = (index...chars.size).find { |position| chars[position] == ']' } || chars.size
        return {chars[index + 1...close].join, close + 1}
      end
      start = index
      index += 1
      index += 1 if index < chars.size && chars[index].ascii_uppercase? && chars[start].ascii_uppercase?
      {chars[start...index].join, index}
    end

    private def parenthesized(chars : Array(Char), index : Int32) : {String, Int32}
      if index < chars.size && chars[index] == '('
        close = (index...chars.size).find { |position| chars[position] == ')' } || chars.size
        {chars[index + 1...close].join, close + 1}
      else
        start = index
        while index < chars.size && (chars[index].ascii_number? || chars[index] == '.')
          index += 1
        end
        index += 1 if index < chars.size && Numeric::SCALE.has_key?(chars[index])
        {chars[start...index].join, index}
      end
    end

    private def data(lines : Array(String), index : Int32) : Nil
      row_number = 0
      while index < lines.size
        line = lines[index]
        index += 1
        stripped = line.strip
        if stripped == ".T&" || stripped == "'T&"
          index = formats(lines, index)
          row_number = 0
          next
        end
        if stripped == "_" || stripped == "-"
          @table.rows << Table::Row.new(Table::RowKind::Rule)
          next
        end
        if stripped == "="
          @table.rows << Table::Row.new(Table::RowKind::DoubleRule)
          next
        end
        if line.starts_with?('.') || line.starts_with?('\'')
          next
        end
        specs = @formats[Math.min(row_number, @formats.size - 1)]
        while rule_row?(specs) && row_number < @formats.size
          double = specs.all?(&.kind.double_rule?)
          @table.rows << Table::Row.new(double ? Table::RowKind::DoubleRule : Table::RowKind::Rule)
          row_number += 1
          specs = @formats[Math.min(row_number, @formats.size - 1)]
        end
        row_number += 1
        fields = line.split(@tab)
        cells = [] of Table::Cell
        field_index = 0
        specs.each_with_index do |spec, column|
          if spec.kind.h_span? || spec.kind.v_span? || spec.kind.rule? || spec.kind.double_rule?
            cells << Table::Cell.new(spec.kind, spec.align)
            field_index += 1 if field_index < fields.size && (spec.kind.v_span? || spec.kind.rule? || spec.kind.double_rule?) && fields[field_index].empty?
            next
          end
          text = fields[field_index]? || ""
          field_index += 1
          if text.rstrip.ends_with?("T{")
            block_lines = [text.rstrip.rchop("T{")]
            rest = ""
            while index < lines.size
              block_line = lines[index]
              index += 1
              if block_line.starts_with?("T}")
                rest = block_line[2..]
                break
              end
              block_lines << block_line
            end
            cells << Table::Cell.new(Table::CellKind::Text, spec.align, block_spans(block_lines, spec.font), true)
            unless rest.empty?
              fields = fields[0...field_index] + rest.lstrip(@tab).split(@tab)
            end
            next
          end
          cells << cell(text, spec)
        end
        @table.rows << Table::Row.new(Table::RowKind::Data, cells)
      end
    end

    # A format row of only `_`/`=` keys draws a rule without taking input.
    private def rule_row?(specs : Array(Spec)) : Bool
      specs.all? { |spec| spec.kind.rule? || spec.kind.double_rule? }
    end

    private def cell(text : String, spec : Spec) : Table::Cell
      case text.strip
      when "\\^"
        return Table::Cell.new(Table::CellKind::VSpan, spec.align)
      when "_", "\\_"
        return Table::Cell.new(Table::CellKind::Rule, spec.align)
      when "=", "\\="
        return Table::Cell.new(Table::CellKind::DoubleRule, spec.align)
      end
      if text.starts_with?("\\R") && text.size >= 3
        fill = @engine.plain_text(@engine.interpolate(text[2..], false))
        return Table::Cell.new(Table::CellKind::Text, spec.align, [Span.new(fill * 20)])
      end
      Table::Cell.new(Table::CellKind::Text, spec.align, spans(text, spec.font))
    end

    private def spans(text : String, font : Font?) : Array(Span)
      env = @engine.env
      saved = env.font
      env.font = font if font
      result = @engine.builder.capture { @engine.emit(@engine.interpolate(text, false)) }
      env.font = saved
      result
    end

    private def block_spans(lines : Array(String), font : Font?) : Array(Span)
      text = lines.reject { |line| line.starts_with?('.') || line.starts_with?('\'') }.join(' ')
      spans(text, font)
    end

    private def finish : Nil
      columns = @formats.max_of?(&.size) || 0
      columns = Math.max(columns, @table.rows.max_of? { |row| row.cells.size } || 0)
      @table.columns = columns
      @table.rows.each do |row|
        next unless row.kind.data?
        while row.cells.size < columns
          row.cells << Table::Cell.new(Table::CellKind::Text, Table::CellAlign::Left)
        end
      end
      first = @formats.first? || [] of Spec
      @table.min_widths = Array.new(columns) { |column| @formats.max_of? { |specs| specs[column]?.try(&.width) || 0 } || 0 }
      @table.gaps = Array.new(columns) { |column| first[column]?.try(&.gap) || 3 }
      rules = @vrules.dup
      while rules.size < columns + 1
        rules << 0
      end
      @table.vrules = @table.allbox? ? Array.new(columns + 1, 1) : rules[0, columns + 1]
      if @table.frame.box? || @table.frame.double_box?
        @table.vrules[0] = Math.max(@table.vrules[0], 1)
        @table.vrules[columns] = Math.max(@table.vrules[columns], 1)
      end
      @engine.builder.table(@table, @engine.env.indent)
    end
  end
end
