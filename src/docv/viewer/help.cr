# src/docv/viewer/help.cr
module Docv
  class Viewer
    # The floating help: the keys of the page view and the search bar as
    # they are bound (`ACTION_HELP`, `FIELD_HELP`), and the mouse gestures,
    # in a box over the content.
    class Help
      # A help line: keys or a gesture and what they do; a section title when
      # *heading*.
      record Line, keys : String, text : String = "", heading : Bool = false

      TITLE = "Help"
      # Widest keys column.
      KEYS_WIDTH = 30

      # Mouse gestures and what they do.
      MOUSE = [
        {"wheel", "scroll"},
        {"Shift-wheel", "scroll sideways"},
        {"drag in the text", "select and copy"},
        {"double-click a word", "select and copy it"},
        {"triple-click", "select and copy the paragraph"},
        {"drag a thumb, click a track", "scroll"},
        {"click a link", "follow it"},
        {"click the search bar", "focus it"},
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

      def initialize(bindings : Bindings, field_bindings : FieldBindings)
        section("Keys")
        Action.values.each do |action|
          keys = bindings.keys(action)
          @lines << Line.new(names(keys), ACTION_HELP[action]) unless keys.empty?
        end
        section("Search bar")
        @lines << Line.new("text", "type; a leading / searches the manual")
        FieldAction.values.each do |action|
          keys = field_bindings.keys(action)
          @lines << Line.new(names(keys), FIELD_HELP[action]) unless keys.empty?
        end
        section("Mouse")
        MOUSE.each { |gesture, text| @lines << Line.new(gesture, text) }
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

      # Scrolls by *delta* lines in a box on *frame*.
      def scroll(delta : Int32, frame : Frame) : Nil
        @top = (@top + delta).clamp(0, Math.max(@lines.size - rows(frame), 0))
      end

      # Lines shown at once on *frame*.
      def rows(frame : Frame) : Int32
        Math.max(Math.min(@lines.size, frame.content_rows - 2), 1)
      end

      # Draws the help centered over the content area of *frame* with the
      # role style ids *styles*: on `Popup`, edges in `Border`, the title in
      # `Title`, section titles in `Heading1` and keys in `Name`. `▲` and `▼`
      # in the edges mark more lines above and below.
      def draw(screen : Screen, frame : Frame, styles : Array(UInt16)) : Nil
        fill = styles[Theme::Role::Popup.value]
        style = ->(role : Theme::Role) { Styles.merge(fill, styles[role.value]) }
        keys_width = Math.min(@lines.max_of { |line| line.heading ? 0 : Unicode.text_width(line.keys) }, KEYS_WIDTH)
        text_width = @lines.max_of { |line| Unicode.text_width(line.heading ? line.keys : line.text) }
        width = Math.min(keys_width + 2 + text_width + 4, frame.inner_cols)
        visible = rows(frame)
        height = visible + 2
        row = Frame::TOP + Math.max((frame.content_rows - height) // 2, 0)
        col = Frame::INNER + Math.max((frame.inner_cols - width) // 2, 0)
        line = style.call(Theme::Role::Border)
        frame.box(screen, row, col, height, width, TITLE, line, fill, style.call(Theme::Role::Title))
        left = col + 2
        limit = col + width - 2
        visible.times do |offset|
          entry = @lines[@top + offset]? || break
          y = row + 1 + offset
          if entry.heading
            screen.write(y, left, Unicode.truncate(entry.keys, limit - left), style.call(Theme::Role::Heading1))
            next
          end
          screen.write(y, left, Unicode.truncate(entry.keys, Math.min(keys_width, limit - left)), style.call(Theme::Role::Name))
          start = left + keys_width + 2
          screen.write(y, start, Unicode.truncate(entry.text, limit - start), style.call(Theme::Role::Text)) if start < limit
        end
        screen[row, col + width - 2] = Cell.new('▲', line) if @top > 0
        screen[row + height - 1, col + width - 2] = Cell.new('▼', line) if @top + visible < @lines.size
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
