# src/docv/viewer/help.cr

module Docv
  class Viewer
    # :nodoc:
    # The help screen, built from the current bindings: keys, mouse and
    # configuration under indented headings, descriptions wrapped to the width.
    class Help
      # A heading, or keys (a gesture, a setting) and what they do, indented
      # by *depth*; continuation lines of a wrapped description have no keys.
      record Line, keys : String, text : String = "", depth : Int32 = 0, heading : Bool = false

      # Title row heading while the help is shown.
      TITLE = "HELP"
      # Columns per depth.
      INDENT = 2
      # Widest keys column, indentation included; longer keys put their
      # description on the next line.
      KEYS_WIDTH = 24
      # Narrowest description; narrower screens scroll the help sideways.
      MIN_TEXT = 20

      # Lines of the search field and the picker besides their bindings.
      FIELD_TEXT = {"text", "find in the page; with a leading /, search all pages"}
      TREE_OTHER = {"other keys", "as in the viewer"}

      MOUSE = [
        {"wheel", "scroll"},
        {"Shift-wheel", "scroll sideways"},
        {"scrollbar", "drag or click to scroll"},
        {"drag over text", "select and copy"},
        {"double-click", "copy the word"},
        {"triple-click", "copy the paragraph"},
        {"click a link", "follow it"},
        {"click a picker row", "open the page, or fold or unfold the group"},
        {"click the search field", "focus it"},
        {"drag the dock's edge", "resize the dock"},
        {"click #{Frame::NAME}", "help"},
        {"point at the heading", "show the page's source and date"},
        {"click #{Frame::CLOSE}", "quit"},
        {"back button", "back"},
      ]

      # Descriptions of `[section]`s other than their list of keys.
      CONFIG_TEXT = {"colors" => "a style per role"}

      # Names of keys that are not text.
      KEY_NAMES = {
        Term::Key::ENTER => "Enter", Term::Key::TAB => "Tab", Term::Key::BACKSPACE => "Backspace",
        Term::Key::ESCAPE => "Esc", Term::Key::UP => "↑", Term::Key::DOWN => "↓", Term::Key::LEFT => "←",
        Term::Key::RIGHT => "→", Term::Key::PAGE_UP => "PgUp", Term::Key::PAGE_DOWN => "PgDn",
        Term::Key::HOME => "Home", Term::Key::END => "End", Term::Key::INSERT => "Ins",
        Term::Key::DELETE => "Del", ' '.ord => "Space",
      }

      # Modifier prefixes, in the order they are written.
      MOD_NAMES = [
        {Term::Mods::Ctrl, "Ctrl-"}, {Term::Mods::Alt, "Alt-"}, {Term::Mods::Super, "Super-"},
        {Term::Mods::Shift, "Shift-"},
      ]

      # Lines before wrapping.
      getter entries = [] of Line
      # First visible line.
      getter top = 0
      # Columns scrolled sideways.
      getter left = 0
      # Column of the descriptions, from the left of the help.
      getter column = 0
      @lines = [] of Line
      @cols = -1
      @width = 0

      def initialize(bindings : Bindings, field_bindings : FieldBindings,
                     tree_bindings : TreeBindings = TreeBindings.new)
        heading("KEYS", 0)
        ACTION_HELP.each do |title, actions|
          heading(title, 1)
          actions.each { |action, text| bound(bindings.keys(action), text) }
        end
        heading("Search field", 1)
        @entries << Line.new(*FIELD_TEXT, 2)
        FIELD_HELP.each { |action, text| bound(field_bindings.keys(action), text) }
        heading("Picker", 1)
        TREE_HELP.each { |action, text| bound(tree_bindings.keys(action), text) }
        @entries << Line.new(*TREE_OTHER, 2)
        heading("MOUSE", 0)
        MOUSE.each { |gesture, text| @entries << Line.new(gesture, text, 1) }
        heading("CONFIG", 0)
        @entries << Line.new("file", Config.path, 1)
        Config::KEYS.each do |name, keys|
          @entries << Line.new("[#{name}]", CONFIG_TEXT[name]? || keys.join(", "), 1)
        end
        @entries << Line.new("docv-config(5)", "every setting", 1)
        widest = @entries.max_of { |line| line.heading ? 0 : line.depth * INDENT + Unicode.text_width(line.keys) }
        @column = Math.min(widest, KEYS_WIDTH) + 2
      end

      # The lines for *frame*, descriptions wrapped to its width.
      def lines(frame : Frame) : Array(Line)
        cols = frame.content_cols
        return @lines if cols == @cols
        @cols = cols
        @lines = [] of Line
        span = Math.max(cols - @column, MIN_TEXT)
        @entries.each do |entry|
          next @lines << entry if entry.heading || entry.text.empty?
          parts = Help.wrap(entry.text, span)
          if entry.depth * INDENT + Unicode.text_width(entry.keys) + 2 > @column
            @lines << Line.new(entry.keys, "", entry.depth)
          else
            @lines << Line.new(entry.keys, parts.shift, entry.depth)
          end
          parts.each { |part| @lines << Line.new("", part, entry.depth) }
        end
        @width = @lines.max_of do |line|
          line.text.empty? ? line.depth * INDENT + Unicode.text_width(line.keys) : @column + Unicode.text_width(line.text)
        end
        @top = @top.clamp(0, max_top(frame))
        @left = @left.clamp(0, max_left(frame))
        @lines
      end

      # Columns of the widest line on *frame*.
      def width(frame : Frame) : Int32
        lines(frame)
        @width
      end

      # *text* split at spaces into lines of at most *width* columns; a longer
      # word takes a line of its own.
      def self.wrap(text : String, width : Int32) : Array(String)
        lines = [] of String
        current = ""
        text.split(' ', remove_empty: true).each do |word|
          candidate = current.empty? ? word : "#{current} #{word}"
          if current.empty? || Unicode.text_width(candidate) <= width
            current = candidate
          else
            lines << current
            current = word
          end
        end
        lines << current
      end

      # The name of a key binding: `j`, `Ctrl-f`, `Shift-Tab`, `F5`.
      def self.key_name(mods : Term::Mods, key : Int32) : String
        name = KEY_NAMES[key]? ||
               (Term::Key::F1 <= key <= Term::Key::F35 ? "F#{key - Term::Key::F1 + 1}" : key.chr.to_s)
        String.build do |io|
          MOD_NAMES.each { |mod, prefix| io << prefix if mods.includes?(mod) }
          io << name
        end
      end

      def scroll(delta : Int32, frame : Frame) : Nil
        @top = (@top + delta).clamp(0, max_top(frame))
      end

      def rows(frame : Frame) : Int32
        Math.max(frame.content_rows, 1)
      end

      def max_top(frame : Frame) : Int32
        Math.max(lines(frame).size - rows(frame), 0)
      end

      def scroll_x(delta : Int32, frame : Frame) : Nil
        @left = (@left + delta).clamp(0, max_left(frame))
      end

      def max_left(frame : Frame) : Int32
        Math.max(width(frame) - frame.content_cols, 0)
      end

      def draw(screen : Screen, frame : Frame, styles : Array(UInt16)) : Nil
        lines = lines(frame)
        origin = frame.left
        limit = origin + frame.content_cols
        start = origin - @left
        rows(frame).times do |offset|
          line = lines[@top + offset]? || break
          y = Frame::TOP + offset
          col = start + line.depth * INDENT
          if line.heading
            put(screen, y, origin, limit, col, line.keys, styles[HEADING_ROLES[line.depth].value])
            next
          end
          put(screen, y, origin, limit, col, line.keys, styles[Theme::Role::Name.value])
          put(screen, y, origin, limit, start + @column, line.text, styles[Theme::Role::Text.value])
        end
      end

      # Writes the part of *text*, starting at screen column *col*, that lies
      # within *origin*...*limit*.
      private def put(screen : Screen, row : Int32, origin : Int32, limit : Int32, col : Int32, text : String,
                      style : UInt16) : Nil
        text.each_grapheme do |grapheme|
          cluster = grapheme.to_s
          width = Unicode.width(cluster)
          next if width == 0
          break if col + width > limit
          if col >= origin
            screen[row, col] = Cell.from(cluster, style)
            screen[row, col + 1] = Cell.continuation(style) if width == 2
          end
          col += width
        end
      end

      # A blank line separates a heading from lines other than headings.
      private def heading(title : String, depth : Int32) : Nil
        @entries << Line.new("") unless @entries.empty? || @entries.last.heading
        @entries << Line.new(title, depth: depth, heading: true)
      end

      private def bound(keys : Array({Term::Mods, Int32}), text : String) : Nil
        @entries << Line.new(names(keys), text, 2) unless keys.empty?
      end

      private def names(keys : Array({Term::Mods, Int32})) : String
        keys.join(' ') { |mods, key| Help.key_name(mods, key) }
      end
    end
  end
end
