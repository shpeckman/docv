# src/docv/markdown.cr

require "html"
require "uri"
require "markd"

module Docv
  # Markdown documents (CommonMark with GitHub extensions) parsed into a
  # `Document`. Links become `Span#link` targets, headings get GitHub anchors
  # (`Document#anchors`), and raw HTML keeps only its text.
  module Markdown
    # File name extensions of Markdown documents (also with `.gz`).
    EXTENSIONS = Set{".md", ".markdown", ".mdown", ".mkd", ".mkdn"}

    # :nodoc:
    # Replaces the spaces of code spans, so they never wrap.
    NO_BREAK = '\u00A0'

    # :nodoc:
    QUOTE_INDENT = 2
    # :nodoc:
    CODE_INDENT = 4
    # :nodoc:
    CODE_TABS = Tabs.new(repeat: 8)

    # :nodoc:
    # List bullets by nesting depth (repeating).
    BULLETS = ["•", "◦", "▪"]
    # :nodoc:
    CHECKBOXES = {false => "☐", true => "☑"}

    # :nodoc:
    ATTRIBUTES = {
      Markd::Node::Type::Strong        => Attr::Bold,
      Markd::Node::Type::Emphasis      => Attr::Italic,
      Markd::Node::Type::Strikethrough => Attr::Strike,
    }

    # :nodoc:
    ALIGNS = {"left" => Table::CellAlign::Left, "center" => Table::CellAlign::Center, "right" => Table::CellAlign::Right}

    # :nodoc:
    # Raw HTML: comments, processing instructions, declarations and tags.
    HTML_MARKUP = /<!--.*?-->|<\?.*?\?>|<![^>]*>|<\/?[A-Za-z][^>]*>/m
    # :nodoc:
    # The scheme that makes a link destination an absolute URL.
    SCHEME = /\A[A-Za-z][A-Za-z0-9+.\-]*:/
    # :nodoc:
    # Characters a heading anchor leaves out.
    SLUG_DROP = /[^\p{L}\p{M}\p{N}\p{Pc}\- ]/

    # True for a file named like a Markdown document (`EXTENSIONS`).
    def self.file?(path : String) : Bool
      EXTENSIONS.includes?(File.extname(path.rchop(".gz")).downcase)
    end

    # :nodoc:
    OPTIONS = Markd::Options.new(gfm: true, autolink: true)
    # :nodoc:
    PLAIN_OPTIONS = Markd::Options.new(gfm: true)

    # Parses Markdown *text*; *highlight* syntax-highlights code blocks
    # labeled with a language (`Syntax`).
    def self.parse(text : String, highlight : Bool = false) : Document
      Converter.new(highlight).run(tree(text))
    end

    # The markd tree of *text*, parsed as GitHub Markdown.
    def self.tree(text : String) : Markd::Node
      Markd::Parser.parse(text, OPTIONS)
    rescue ArgumentError
      Markd::Parser.parse(text, PLAIN_OPTIONS)
    end

    # The GitHub anchor of heading *text*: lower case, punctuation dropped,
    # spaces as dashes.
    def self.slug(text : String) : String
      text.downcase.gsub(SLUG_DROP, "").tr(" ", "-")
    end

    # The title of an alert node (`> [!NOTE]`): the given title, or the type
    # as a word (`Note`).
    def self.alert_title(node : Markd::Node) : String
      title = node.data["title"]?.to_s
      title == node.data["alert"]?.to_s ? title.capitalize : title
    end

    # A one-line description of *text*: its first heading and first paragraph,
    # joined by a dash.
    def self.description(text : String) : String
      blocks = parse(text).blocks
      heading = blocks.find(&.kind.heading?).try(&.text.strip)
      paragraph = blocks.find { |block| block.kind.text? && block.fill? && !block.text.blank? }.try(&.text.strip)
      [heading, paragraph].compact.join(" — ")
    end

    # Builds the blocks of a markd tree.
    private class Converter
      @doc = Document.new
      # Where blocks go: body indent, quote bar columns, list depth.
      @indent = 0
      @bars = [] of Int32
      @depth = 0
      # A blank is due before the next block; tight lists go without.
      @space = false
      @tight = false
      # The list marker for the next block.
      @tag : Array(Span)? = nil
      @tag_indent = 0
      # Inline text state; `@single_line` turns line breaks into spaces.
      @attr = Attr::None
      @markup = Markup::None
      @link = 0
      @single_line = false
      @targets = {} of Target => Int32
      @slugs = {} of String => Int32

      def initialize(@highlight : Bool)
      end

      def run(root : Markd::Node) : Document
        @doc.format = Format::Markdown
        children(root)
        flush_tag
        @doc
      end

      private def children(node : Markd::Node) : Nil
        child = node.first_child?
        while child
          block(child)
          child = child.next?
        end
      end

      private def block(node : Markd::Node) : Nil
        case node.type
        when .paragraph?      then paragraph(node)
        when .heading?        then heading(node)
        when .list?           then list(node)
        when .block_quote?    then quote(node, nil)
        when .alert?          then quote(node, Markdown.alert_title(node))
        when .code_block?     then code(node)
        when .html_block?     then html(node)
        when .thematic_break? then rule
        when .table?          then table(node)
        else                       children(node)
        end
      end

      # --- blocks ------------------------------------------------------------

      private def paragraph(node : Markd::Node) : Nil
        lines = inline_lines(node)
        return if lines.all?(&.empty?)
        lines.each_with_index do |spans, index|
          block = index == 0 ? emit(BlockKind::Text) : add(BlockKind::Text)
          block.spans = spans
        end
        @space = !@tight
      end

      private def heading(node : Markd::Node) : Nil
        spans = single_line { inline_lines(node) }.first
        block = emit(BlockKind::Heading)
        block.level = (node.data["level"]?.as?(Int32) || 1).clamp(1, 6)
        block.spans = spans
        text = block.text.strip
        @doc.title = text if block.level == 1 && @doc.title.empty?
        anchor(text, @doc.blocks.size - 1)
        @space = true
      end

      # Body indent: the marker's width plus a space (the widest number's).
      private def list(node : Markd::Node) : Nil
        separate
        flush_tag
        ordered = node.data["type"]? == "ordered"
        number = node.data["start"]?.as?(Int32) || 1
        delimiter = node.data["delimiter"]?.as?(String) || "."
        width = ordered ? "#{number + count(node) - 1}#{delimiter}".size + 1 : 2
        tight, depth, indent = @tight, @depth, @indent
        @tight = node.data["tight"]? != false
        item = node.first_child?
        first = true
        while item
          @space = !@tight unless first
          marker = if ordered
                     "#{number}#{delimiter}"
                   elsif item.data["type"]? == "checkbox"
                     CHECKBOXES[item.data["checked"]? == true]
                   else
                     BULLETS[depth % BULLETS.size]
                   end
          @tag = [Span.new(marker)]
          @tag_indent = indent
          @indent = indent + width
          @depth = depth + 1
          children(item)
          flush_tag
          @indent = indent
          number += 1
          first = false
          item = item.next?
        end
        @tight, @depth = tight, depth
        @space = true
      end

      # A block quote, or an alert with its *title* on the first line.
      private def quote(node : Markd::Node, title : String?) : Nil
        separate
        flush_tag
        indent, bars = @indent, @bars
        @bars = bars + [indent]
        @indent = indent + QUOTE_INDENT
        add(BlockKind::Text).spans = [Span.new(title, Styles.id(Style.new(Attr::Bold)))] if title
        children(node)
        @indent, @bars = indent, bars
        @space = true
      end

      # One unfilled block per line.
      private def code(node : Markd::Node) : Nil
        style = Styles.id(Style.new(markup: Markup::CodeBlock))
        start = @doc.blocks.size
        node.text.chomp.split('\n').each_with_index do |line, index|
          block = index == 0 ? emit(BlockKind::Text) : add(BlockKind::Text)
          block.indent = @indent + CODE_INDENT
          block.fill = false
          block.tabs = CODE_TABS
          line = line.rchop('\r')
          block.spans = [Span.new(line, style)] unless line.empty?
        end
        if @highlight && (language = Syntax.language(node.fence_language))
          blocks = @doc.blocks[start..].select { |block| block.kind.text? && !block.fill? }
          Syntax.apply(blocks, language)
        end
        @space = true
      end

      # Raw HTML without its tags, a paragraph per blank-separated part.
      private def html(node : Markd::Node) : Nil
        text = HTML.unescape(node.text.gsub(HTML_MARKUP, ""))
        text.split(/\n[ \t]*\n/).each do |part|
          words = part.split
          next if words.empty?
          emit(BlockKind::Text).spans = [Span.new(words.join(' '))]
          @space = true
        end
      end

      private def rule : Nil
        emit(BlockKind::Rule)
        @space = true
      end

      private def table(node : Markd::Node) : Nil
        table = Table.new
        row_node = node.first_child?
        while row_node
          heading = row_node.data["heading"]? == true
          row = Table::Row.new(Table::RowKind::Data)
          cell_node = row_node.first_child?
          while cell_node
            align = ALIGNS[cell_node.data["align"]?.to_s]? || Table::CellAlign::Left
            saved = @attr
            @attr |= Attr::Bold if heading
            spans = single_line { inline_lines(cell_node) }.first
            @attr = saved
            row.cells << Table::Cell.new(Table::CellKind::Text, align, spans, block: true)
            cell_node = cell_node.next?
          end
          table.rows << row
          table.rows << Table::Row.new(Table::RowKind::Rule) if heading && row_node.next?
          row_node = row_node.next?
        end
        table.columns = table.rows.max_of? { |row| row.cells.size } || 0
        return if table.columns == 0
        table.frame = Table::Frame::Box
        table.vrules = Array.new(table.columns + 1, 1)
        table.expand = true
        emit(BlockKind::Table).table = table
        @space = true
      end

      # --- block placement ---------------------------------------------------

      # A new block after a due blank, taking the pending list tag (on an
      # empty text block before it unless it is text).
      private def emit(kind : BlockKind) : Block
        separate
        flush_tag unless kind.text?
        block = add(kind)
        if tag = @tag
          block.tag = tag
          block.tag_indent = @tag_indent
          @tag = nil
        end
        block
      end

      # A new block at the current indent and quote bars.
      private def add(kind : BlockKind) : Block
        block = Block.new(kind)
        block.indent = @indent
        block.bars = @bars.dup unless @bars.empty?
        @doc.blocks << block
        block
      end

      private def separate : Nil
        return unless @space
        @space = false
        add(BlockKind::Blank).lines = 1 unless @doc.blocks.empty?
      end

      # Puts a pending list tag on an empty text block.
      private def flush_tag : Nil
        tag = @tag || return
        @tag = nil
        block = add(BlockKind::Text)
        block.tag = tag
        block.tag_indent = @tag_indent
      end

      private def count(node : Markd::Node) : Int32
        total = 0
        child = node.first_child?
        while child
          total += 1
          child = child.next?
        end
        total
      end

      # Repeated slugs get `-1`, `-2`... as on GitHub.
      private def anchor(text : String, index : Int32) : Nil
        slug = Markdown.slug(text)
        seen = @slugs[slug]?
        @slugs[slug] = (seen || 0) + 1
        @doc.anchors[seen ? "#{slug}-#{seen}" : slug] = index
      end

      # --- inlines -----------------------------------------------------------

      # Spans of *node*'s inlines, one array per hard-broken line.
      private def inline_lines(node : Markd::Node) : Array(Array(Span))
        lines = [[] of Span]
        inline(node, lines)
        lines
      end

      private def single_line(& : -> Array(Array(Span))) : Array(Array(Span))
        saved = @single_line
        @single_line = true
        lines = yield
        @single_line = saved
        lines
      end

      private def inline(node : Markd::Node, lines : Array(Array(Span))) : Nil
        child = node.first_child?
        while child
          case child.type
          when .text?        then append(lines, child.text)
          when .soft_break?  then append(lines, " ")
          when .line_break?  then @single_line ? append(lines, " ") : (lines << [] of Span)
          when .code?        then marked(Markup::Code) { append(lines, child.text.gsub(' ', NO_BREAK)) }
          when .html_inline? then nil
          when .link?        then link(child, lines)
          when .image?       then image(child, lines)
          else
            if attr = ATTRIBUTES[child.type]?
              saved = @attr
              @attr |= attr
              inline(child, lines)
              @attr = saved
            else
              inline(child, lines)
            end
          end
          child = child.next?
        end
      end

      private def append(lines : Array(Array(Span)), text : String) : Nil
        return if text.empty?
        spans = lines.last
        style = Styles.id(Style.new(@attr, markup: @markup))
        if (last = spans.last?) && last.style == style && last.link == @link
          spans[-1] = Span.new(last.text + text, style, @link)
        else
          spans << Span.new(text, style, @link)
        end
      end

      private def marked(markup : Markup, &) : Nil
        saved = @markup
        @markup = markup
        yield
        @markup = saved
      end

      private def link(node : Markd::Node, lines : Array(Array(Span))) : Nil
        saved = @link
        @link = target_id(node.data["destination"]?.as?(String) || "")
        inline(node, lines)
        @link = saved
      end

      # An image stands as its description (the file name without one).
      private def image(node : Markd::Node, lines : Array(Array(Span))) : Nil
        text = String.build { |io| plain(node, io) }.strip
        text = File.basename(node.data["destination"]?.to_s) if text.empty?
        marked(Markup::Image) { append(lines, text) }
      end

      private def plain(node : Markd::Node, io : IO) : Nil
        child = node.first_child?
        while child
          io << child.text if child.type.text? || child.type.code?
          plain(child, io)
          child = child.next?
        end
      end

      # Interns *destination* as a `Target`; `0` when empty.
      private def target_id(destination : String) : Int32
        return 0 if destination.empty?
        target = if destination.starts_with?('#')
                   Target.new(TargetKind::Anchor, "", URI.decode(destination[1..]))
                 elsif destination.matches?(SCHEME)
                   Target.new(TargetKind::Url, destination)
                 else
                   path, _, part = destination.partition('#')
                   Target.new(TargetKind::File, URI.decode(path), URI.decode(part))
                 end
        @targets[target] ||= begin
          @doc.links << target
          @doc.links.size
        end
      end
    end
  end
end
