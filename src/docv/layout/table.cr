# src/docv/layout/table.cr

module Docv
  class Layout
    # :nodoc:
    class TableLayout
      RULE_STYLE = 0_u16

      @widths = [] of Int32
      @numeric_left = [] of Int32
      @numeric_right = [] of Int32
      @separators = [] of Int32

      def initialize(@table : Table, @layout : Layout)
      end

      def rows(indent : Int32, width : Int32, wrap : Bool) : Array(Row)
        columns = @table.columns
        return [] of Row if columns == 0
        @table.rows.each do |row|
          while row.kind.data? && row.cells.size < columns
            row.cells << Table::Cell.new(Table::CellKind::Text, Table::CellAlign::Left)
          end
        end
        measure(columns, indent, width, wrap)
        total = table_width
        shift = @table.center? && total < width - indent ? (width - indent - total) // 2 : 0
        left = indent + shift
        rows = [] of Row
        framed = @table.frame.box? || @table.frame.double_box?
        double = @table.frame.double_box?
        rows << rule_row(left, :top, double) if framed
        data_rows = @table.rows
        data_rows.each_with_index do |row, index|
          case row.kind
          in .rule?        then rows << rule_row(left, :middle, false)
          in .double_rule? then rows << rule_row(left, :middle, true)
          in .data?
            rows.concat(data_row(row, left))
            if @table.allbox? && index < data_rows.size - 1 && data_rows[index + 1].kind.data?
              rows << rule_row(left, :middle, false)
            end
          end
        end
        rows << rule_row(left, :bottom, double) if framed
        rows
      end

      private def measure(columns : Int32, indent : Int32, width : Int32, wrap : Bool) : Nil
        @widths = Array.new(columns) { |column| @table.min_widths[column]? || 0 }
        @numeric_left = Array.new(columns, 0)
        @numeric_right = Array.new(columns, 0)
        block_natural = Array.new(columns, 0)
        blocks = Set(Int32).new
        @separators = Array.new(columns + 1) do |position|
          rules = @table.vrules[position]? || 0
          if position == 0 || position == columns
            rules > 0 ? rules + 1 : 0
          else
            gap = @table.gaps[position - 1]? || 3
            rules > 0 ? Math.max(gap, rules + 2) : gap
          end
        end
        @table.rows.each do |row|
          next unless row.kind.data?
          row.cells.each_with_index do |cell, column|
            next unless cell.kind.text?
            next if spans(row, column) > 1
            if cell.block?
              blocks << column
              block_natural[column] = Math.max(block_natural[column], text_width(cell))
            elsif cell.align.numeric?
              left, right = numeric_parts(cell)
              @numeric_left[column] = Math.max(@numeric_left[column], left)
              @numeric_right[column] = Math.max(@numeric_right[column], right)
              @widths[column] = Math.max(@widths[column], @numeric_left[column] + @numeric_right[column])
            else
              @widths[column] = Math.max(@widths[column], text_width(cell))
            end
          end
        end
        unless blocks.empty?
          fixed = table_width_without(blocks)
          share = wrap ? Math.max((width - indent - fixed) // blocks.size, 10) : Int32::MAX
          blocks.each do |column|
            @widths[column] = Math.max(@widths[column], Math.min(block_natural[column], share))
          end
        end
        @table.rows.each do |row|
          next unless row.kind.data?
          row.cells.each_with_index do |cell, column|
            count = spans(row, column)
            next unless count > 1 && cell.kind.text?
            needed = text_width(cell)
            available = span_width(column, count)
            if needed > available
              last = column + count - 1
              @widths[last] += needed - available
            end
          end
        end
        expand(width - indent - table_width) if @table.expand?
      end

      # Spreads *room* over the columns by width; the last takes the remainder.
      private def expand(room : Int32) : Nil
        return if room <= 0 || @widths.empty?
        natural = @widths.sum
        given = 0
        if natural > 0
          @widths.each_index do |column|
            share = room * @widths[column] // natural
            @widths[column] += share
            given += share
          end
        end
        @widths[-1] += room - given
      end

      private def table_width : Int32
        @widths.sum + @separators.sum
      end

      private def table_width_without(blocks : Set(Int32)) : Int32
        @widths.each_with_index.sum { |(w, column)| blocks.includes?(column) ? 0 : w } + @separators.sum
      end

      # Columns the cell at *column* covers (itself plus `s` cells).
      private def spans(row : Table::Row, column : Int32) : Int32
        count = 1
        while column + count < @table.columns && (next_cell = row.cells[column + count]?) && next_cell.kind.h_span?
          count += 1
        end
        count
      end

      private def span_width(column : Int32, count : Int32) : Int32
        width = 0
        count.times do |offset|
          width += @widths[column + offset]
          width += @separators[column + offset + 1] if offset < count - 1
        end
        width
      end

      private def text_width(cell : Table::Cell) : Int32
        cell.spans.sum { |span| Unicode.text_width(span.text.gsub(' ', ' ')) }
      end

      private def numeric_parts(cell : Table::Cell) : {Int32, Int32}
        text = cell.spans.join(&.text)
        point = numeric_point(text)
        {Unicode.text_width(text[0, point]), Unicode.text_width(text[point..])}
      end

      private def numeric_point(text : String) : Int32
        if dot = text.rindex(/\.\d/)
          return dot
        end
        last_digit = text.rindex(/\d/)
        last_digit ? last_digit + 1 : text.size
      end

      private def data_row(row : Table::Row, left : Int32) : Array(Row)
        columns = @table.columns
        contents = Array(Array(Row)?).new(columns, nil)
        height = 1
        column = 0
        while column < columns
          cell = row.cells[column]
          count = spans(row, column)
          if cell.kind.text?
            width = span_width(column, count)
            lines = cell_lines(cell, width, column, count)
            contents[column] = lines
            height = Math.max(height, lines.size)
          end
          column += count
        end
        (0...height).map do |line_index|
          target = Row.new
          target.pad(left)
          put_separator(target, 0)
          column = 0
          while column < columns
            cell = row.cells[column]
            count = spans(row, column)
            width = span_width(column, count)
            start = target.col
            case cell.kind
            in .rule?
              width.times { target.cells << rule_cell('─') }
            in .double_rule?
              width.times { target.cells << rule_cell('═') }
            in .text?
              line = contents[column].try(&.[line_index]?) || Row.new
              target.offset = 0 if target.offset < 0
              place(target, line, width, cell, column)
            in .v_span?, .h_span?
            end
            target.pad(start + width)
            column += count
            put_separator(target, column)
          end
          target
        end
      end

      # Links of the returned rows count columns from the cell's start.
      private def cell_lines(cell : Table::Cell, width : Int32, column : Int32, count : Int32) : Array(Row)
        pieces = @layout.tokenize(cell.spans)
        if cell.block?
          @layout.flow(pieces, 0, 0, width, true, Tabs::DEFAULT)
        else
          rows = @layout.flow(pieces, 0, 0, Int32::MAX, false, Tabs::DEFAULT)
          [rows.first? || Row.new]
        end
      end

      private def place(target : Row, line : Row, width : Int32, cell : Table::Cell, column : Int32) : Nil
        size = line.cells.size
        pad = case cell.align
              in .right?  then width - size
              in .center? then (width - size) // 2
              in .numeric?
                left, _ = numeric_parts(cell)
                @numeric_left[column] - left
              in .alpha? then (width - size) // 2
              in .left?  then 0
              end
        pad = 0 if cell.block? && !cell.align.right? && !cell.align.center?
        target.pad(target.col + Math.max(pad, 0))
        start = target.col
        line.links.each { |link| target.links << link.copy_with(col: link.col + start) }
        target.cells.concat(line.cells)
      end

      private def put_separator(target : Row, position : Int32) : Nil
        size = @separators[position]? || 0
        return if size == 0
        rules = @table.vrules[position]? || 0
        start = target.col
        if rules > 0
          columns = @table.columns
          mark = position == 0 ? 0 : position == columns ? size - 1 : size // 2
          size.times do |offset|
            target.cells << (offset == mark ? rule_cell(rules > 1 ? '║' : '│') : Cell::BLANK)
          end
        else
          target.pad(start + size)
        end
      end

      private def rule_row(left : Int32, place : Symbol, double : Bool) : Row
        target = Row.new
        target.pad(left)
        line = double ? '═' : '─'
        columns = @table.columns
        (0..columns).each do |position|
          size = @separators[position]
          rules = @table.vrules[position]? || 0
          mark = position == 0 ? 0 : position == columns ? size - 1 : size // 2
          size.times do |offset|
            if rules > 0 && offset == mark
              target.cells << rule_cell(junction(place, position, columns, double))
            else
              target.cells << rule_cell(line)
            end
          end
          target.cells.concat(Array.new(@widths[position], rule_cell(line))) if position < columns
        end
        target
      end

      private def junction(place : Symbol, position : Int32, columns : Int32, double : Bool) : Char
        edge = position == 0 ? :left : position == columns ? :right : :inner
        if double
          case {place, edge}
          when {:top, :left}     then '╒'
          when {:top, :right}    then '╕'
          when {:top, :inner}    then '╤'
          when {:bottom, :left}  then '╘'
          when {:bottom, :right} then '╛'
          when {:bottom, :inner} then '╧'
          when {:middle, :left}  then '╞'
          when {:middle, :right} then '╡'
          else                        '╪'
          end
        else
          case {place, edge}
          when {:top, :left}     then '┌'
          when {:top, :right}    then '┐'
          when {:top, :inner}    then '┬'
          when {:bottom, :left}  then '└'
          when {:bottom, :right} then '┘'
          when {:bottom, :inner} then '┴'
          when {:middle, :left}  then '├'
          when {:middle, :right} then '┤'
          else                        '┼'
          end
        end
      end

      private def rule_cell(char : Char) : Cell
        Cell.new(char, RULE_STYLE)
      end
    end
  end
end
