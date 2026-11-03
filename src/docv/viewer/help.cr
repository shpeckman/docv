# src/docv/viewer/help.cr

module Docv
  class Viewer
    # :nodoc:
    # The help screen, built from the current bindings.
    class Help
      # Keys or a gesture and what they do, or a section title when *heading*.
      record Line, keys : String, text : String = "", heading : Bool = false

      # Title row heading while the help is shown.
      TITLE = "HELP"
      # Widest keys column.
      KEYS_WIDTH = 30

      MOUSE = [
        {"wheel", "scroll"},
        {"Shift-wheel", "scroll sideways (the page or the tree)"},
        {"drag in the text", "select and copy"},
        {"double-click a word", "select and copy it"},
        {"triple-click", "select and copy the paragraph"},
        {"drag a thumb, click a track", "scroll"},
        {"click a link", "follow it"},
        {"click a page or group in the tree", "open it, or fold or unfold it"},
        {"click the search field", "focus it"},
        {"drag the dock's edge", "resize the dock"},
        {"click #{Frame::NAME}", "this help"},
        {"point at the page's heading", "show its source and date"},
        {"click #{Frame::CLOSE}", "quit"},
        {"back button", "back to the previous page"},
      ]

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

      getter lines = [] of Line
      # First visible line.
      getter top = 0
      # Columns scrolled sideways.
      getter left = 0
      # Columns of the keys column and of the widest line.
      getter keys_width = 0
      getter width = 0

      def initialize(bindings : Bindings, field_bindings : FieldBindings,
                     tree_bindings : TreeBindings = TreeBindings.new)
        section("Keys")
        Action.values.each do |action|
          keys = bindings.keys(action)
          @lines << Line.new(names(keys), ACTION_HELP[action]) unless keys.empty?
        end
        section("Search field")
        @lines << Line.new("text", "type: find in the page; a leading / searches the manual")
        FieldAction.values.each do |action|
          keys = field_bindings.keys(action)
          @lines << Line.new(names(keys), FIELD_HELP[action]) unless keys.empty?
        end
        section("Tree")
        TreeAction.values.each do |action|
          keys = tree_bindings.keys(action)
          @lines << Line.new(names(keys), TREE_HELP[action]) unless keys.empty?
        end
        @lines << Line.new("other keys", "go to the page")
        section("Mouse")
        MOUSE.each { |gesture, text| @lines << Line.new(gesture, text) }
        @keys_width = Math.min(@lines.max_of { |line| line.heading ? 0 : Unicode.text_width(line.keys) }, KEYS_WIDTH)
        @width = @lines.max_of do |line|
          line.heading ? Unicode.text_width(line.keys) : @keys_width + 2 + Unicode.text_width(line.text)
        end
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
        Math.max(@lines.size - rows(frame), 0)
      end

      def scroll_x(delta : Int32, frame : Frame) : Nil
        @left = (@left + delta).clamp(0, max_left(frame))
      end

      def max_left(frame : Frame) : Int32
        Math.max(@width - frame.content_cols, 0)
      end

      def draw(screen : Screen, frame : Frame, styles : Array(UInt16)) : Nil
        origin = frame.left
        limit = origin + frame.content_cols
        start = origin - @left
        rows(frame).times do |offset|
          entry = @lines[@top + offset]? || break
          y = Frame::TOP + offset
          if entry.heading
            put(screen, y, origin, limit, start, entry.keys, styles[Theme::Role::Heading1.value])
            next
          end
          put(screen, y, origin, Math.min(start + @keys_width, limit), start, Unicode.truncate(entry.keys, @keys_width),
            styles[Theme::Role::Name.value])
          put(screen, y, origin, limit, start + @keys_width + 2, entry.text, styles[Theme::Role::Text.value])
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

      private def section(title : String) : Nil
        @lines << Line.new("") unless @lines.empty?
        @lines << Line.new(title, heading: true)
      end

      private def names(keys : Array({Term::Mods, Int32})) : String
        keys.join(' ') { |mods, key| Help.key_name(mods, key) }
      end
    end
  end
end
