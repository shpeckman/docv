# src/docv/crystal_pages/roff.cr
module Docv
  module CrystalPages
    # roff escaping for man(7) output.
    module Roff
      # Indentation of nested blocks, in ens.
      INDENT = 4

      # Characters roff reads as escapes or typesets as typographic glyphs,
      # with their literal spellings.
      GLYPHS = {'\\' => "\\e", '-' => "\\-", '\'' => "\\(aq", '`' => "\\(ga", '~' => "\\(ti", '^' => "\\(ha"}

      # Writes *char* so roff prints it literally; non-ASCII characters become
      # `\[uXXXX]`, valid in any encoding.
      def self.escape(char : Char, io : IO) : Nil
        if glyph = GLYPHS[char]?
          io << glyph
        elsif char.ascii?
          io << char
        else
          io << "\\[u"
          char.ord.to_s(io, 16, precision: 4, upcase: true)
          io << ']'
        end
      end

      def self.escape(text : String, io : IO) : Nil
        text.each_char { |char| escape(char, io) }
      end

      def self.escape(text : String) : String
        String.build { |io| escape(text, io) }
      end

      # Double-quoted macro argument.
      def self.quote(text : String) : String
        %("#{escape(text).gsub('"', "\\(dq")}")
      end

      def self.bold(text : String) : String
        "\\fB#{escape(text)}\\fR"
      end

      # Writes *text* as one text line that is never read as a request.
      def self.line(text : String, io : IO) : Nil
        io << "\\&" if text.starts_with?('.')
        escape(text, io)
        io << '\n'
      end

      # Writes *text* as literal lines for a no-fill display.
      def self.lines(text : String, io : IO) : Nil
        text.each_line { |line| line(line, io) }
      end
    end

    # Renders the inline content of a markd node as roff: code spans,
    # emphasis, links, images and line breaks.
    class Inline
      FONTS = {
        {false, false} => "\\fR",
        {true, false}  => "\\fB",
        {false, true}  => "\\fI",
        {true, true}   => "\\f(BI",
      }

      # Roff for the inline children of *node*. *bold* sets the base font,
      # *urls* appends external link targets, *upcase* capitalizes
      # everything outside code spans, and *first* replaces the text of the
      # first text node.
      def self.render(node : Markd::Node, *, bold : Bool = false, urls : Bool = true, upcase : Bool = false,
                      first : String? = nil) : String
        String.build do |io|
          io << FONTS[{true, false}] if bold
          new(io, bold, urls, upcase, first).children(node)
          io << FONTS[{false, false}] if bold
        end
      end

      # Roff for the first block of Markdown *text*, inline only.
      def self.markdown(text : String, *, urls : Bool = true) : String
        block = CrystalPages.blocks(text).first? || return ""
        render(block, urls: urls)
      end

      @bold : Int32
      @italic = 0
      @line_start = true

      def initialize(@io : IO, bold : Bool, @urls : Bool, @upcase : Bool, @first : String?)
        @bold = bold ? 1 : 0
      end

      def children(node : Markd::Node) : Nil
        child = node.first_child?
        while child
          inline(child)
          child = child.next?
        end
      end

      private def inline(node : Markd::Node) : Nil
        case node.type
        when .text?
          text = @first || node.text
          @first = nil
          text.each_char { |char| literal(char) }
        when .soft_break?  then newline
        when .line_break?  then hard_break
        when .code?        then code(node.text)
        when .emphasis?    then styled(node, 0, 1)
        when .strong?      then styled(node, 1, 0)
        when .link?        then link(node)
        when .html_inline? then nil
        else                    children(node)
        end
      end

      # A code span in bold; `\%` before each word keeps it from being
      # hyphenated.
      private def code(text : String) : Nil
        font(1, 0)
        @io << "\\%"
        text.each_char do |char|
          Roff.escape(char, @io)
          @io << "\\%" if char == ' '
        end
        font(-1, 0)
      end

      private def styled(node : Markd::Node, bold : Int32, italic : Int32) : Nil
        font(bold, italic)
        children(node)
        font(-bold, -italic)
      end

      # The link text, then the URL of an external link in angle brackets
      # unless the text is the URL.
      private def link(node : Markd::Node) : Nil
        children(node)
        url = node.data["destination"]?.to_s
        external = url.includes?("://") || url.starts_with?("mailto:")
        return unless @urls && external
        text = CrystalPages.plain(node)
        return if text == url || text == url.lchop("mailto:")
        emit(" <")
        Roff.escape(url, @io)
        emit(">")
      end

      private def newline : Nil
        @io << '\n'
        @line_start = true
      end

      private def hard_break : Nil
        @io << "\n.br\n"
        @line_start = true
      end

      private def literal(char : Char) : Nil
        char = char.upcase if @upcase
        @io << "\\&" if @line_start && char == '.'
        @line_start = false
        Roff.escape(char, @io)
      end

      private def emit(text : String) : Nil
        @io << text
        @line_start = false
      end

      private def font(bold : Int32, italic : Int32) : Nil
        @bold += bold
        @italic += italic
        emit(FONTS[{@bold > 0, @italic > 0}])
      end
    end

    # Writes markd blocks as roff. With *sections*, headings become `.SH`
    # and `.SS` as on a page of their own; otherwise, inside a page section,
    # they become bold paragraphs.
    class Renderer
      # Roff macro for each heading level when the text is a whole page.
      SECTIONS = {1 => ".SH", 2 => ".SH", 3 => ".SS"}

      # Flag words that open a paragraph in Crystal doc comments, shown as
      # bold labels.
      FLAG = /\A(BUG|DEPRECATED|EXPERIMENTAL|FIXME|NOTE|OPTIMIZE|TODO|WARNING)(?:\(([^)]*)\))?:?(?=\s|\z)/

      # Bullet of unordered list items.
      BULLET = "\\(bu"

      # Whether a table was written, which needs the `tbl` preprocessor.
      getter? tables = false

      def initialize(@io : IO, @sections : Bool = false)
      end

      def render(blocks : Array(Markd::Node)) : Nil
        blocks.each { |block| render(block) }
      end

      def render(block : Markd::Node) : Nil
        case block.type
        when .heading?        then heading(block)
        when .paragraph?      then @io << ".PP\n"; paragraph(block)
        when .code_block?     then code(block.text.chomp)
        when .list?           then list(block)
        when .block_quote?    then indent { render(CrystalPages.children(block)) }
        when .alert?          then alert(block)
        when .table?          then table(block)
        when .thematic_break? then @io << ".PP\n\\(em\\(em\\(em\n"
        when .html_block?     then html(block)
        end
      end

      # A tagged paragraph: *head* is the roff that opens it (`.IP` or `.TP`
      # and its tag), the first paragraph of *blocks* continues on it and the
      # remaining blocks keep its indentation.
      def item(head : String, blocks : Array(Markd::Node)) : Nil
        @io << head << '\n'
        rest = blocks
        if (first = blocks.first?) && first.type.paragraph?
          paragraph(first)
          rest = blocks[1..]
        elsif blocks.empty?
          @io << "\\&\n"
        end
        return if rest.empty?
        @io << ".RS\n"
        render(rest)
        @io << ".RE\n"
      end

      private def heading(block : Markd::Node) : Nil
        level = block.data["level"]?.as?(Int32) || 1
        if @sections && (command = SECTIONS[level]?)
          @io << command << '\n' << Inline.render(block, upcase: command == ".SH") << '\n'
        else
          @io << ".PP\n" << Inline.render(block, bold: true) << '\n'
        end
      end

      private def paragraph(block : Markd::Node) : Nil
        first = block.first_child?
        if first && first.type.text? && (md = first.text.match(FLAG))
          @io << Roff.bold("#{md[1]}#{md[2]?.try { |detail| " (#{detail})" }}:") << ' '
          @io << Inline.render(block, first: first.text[md.end..].lstrip) << '\n'
        else
          @io << Inline.render(block) << '\n'
        end
      end

      private def code(text : String) : Nil
        @io << ".PP\n"
        indent do
          @io << ".EX\n"
          Roff.lines(text, @io)
          @io << ".EE\n"
        end
      end

      private def alert(block : Markd::Node) : Nil
        indent do
          @io << ".PP\n" << Roff.bold(Markdown.alert_title(block)) << '\n'
          render(CrystalPages.children(block))
        end
      end

      private def list(block : Markd::Node) : Nil
        items = CrystalPages.children(block)
        ordered = block.data["type"]? == "ordered"
        start = block.data["start"]?.as?(Int32) || 1
        width = ordered ? "#{start + items.size - 1}.".size + 1 : 2
        items.each_with_index do |item, index|
          marker = if ordered
                     "#{start + index}."
                   elsif item.data["type"]? == "checkbox"
                     Roff.escape(Markdown::CHECKBOXES[item.data["checked"]? == true])
                   else
                     BULLET
                   end
          item(".IP #{marker} #{width}", CrystalPages.children(item))
        end
      end

      private def table(block : Markd::Node) : Nil
        rows = CrystalPages.children(block)
        return if rows.empty?
        @tables = true
        columns = rows.max_of { |row| CrystalPages.children(row).size }
        formats = Array.new(columns - 1, "l") << "lx"
        @io << ".PP\n.TS\ntab(\t);\n" << formats.join(' ') << ".\n"
        rows.each_with_index do |row, index|
          row(CrystalPages.children(row), index == 0)
          @io << "_\n" if index == 0
        end
        @io << ".TE\n"
      end

      private def row(cells : Array(Markd::Node), header : Bool) : Nil
        cells.each_with_index do |cell, index|
          text = Inline.render(cell, bold: header).gsub('\t', ' ')
          @io << '\t' if index > 0
          @io << "T{\n" << (text.empty? ? "\\&" : text) << "\nT}"
        end
        @io << '\n'
      end

      # The text of raw HTML without its tags, a paragraph per run of lines.
      private def html(block : Markd::Node) : Nil
        HTML.unescape(block.text.gsub(Markdown::HTML_MARKUP, "")).split(/\n[ \t]*\n/).each do |part|
          words = part.split
          next if words.empty?
          @io << ".PP\n"
          Roff.line(words.join(' '), @io)
        end
      end

      private def indent(&) : Nil
        @io << ".RS " << Roff::INDENT << '\n'
        yield
        @io << ".RE\n"
      end
    end
  end
end
