# src/docv/viewer/bindings.cr

module Docv
  class Viewer
    # Actions of the page view.
    enum Action
      Top
      Bottom
      ToggleWrap
      NextLink
      PrevLink
      FollowLink
      Back
      OpenPage
      Find
      FindNext
      FindPrevious
      ToggleDock
      SavePages
      Help
      Escape
      Redraw
      Quit
    end

    # Actions of the dock's search field; text keys insert.
    enum FieldAction
      Accept
      Cancel
      DeleteBack
      Clear
      Next
      Previous
      Expand
      Collapse
    end

    # Actions of the dock's tree; unbound keys go to the page view.
    enum TreeAction
      Next
      Previous
      Open
      Expand
      Collapse
      Field
      Leave
    end

    # Page view bindings: {modifiers, key (codepoint or `Term::Key`), action}.
    # Text keys bound nowhere start finding in the page; the mouse scrolls.
    DEFAULT_BINDINGS = [
      {Term::Mods::None, Term::Key::PAGE_UP, Action::Top},
      {Term::Mods::None, Term::Key::PAGE_DOWN, Action::Bottom},
      {Term::Mods::Alt, 'z'.ord, Action::ToggleWrap},
      {Term::Mods::None, Term::Key::TAB, Action::NextLink},
      {Term::Mods::Shift, Term::Key::TAB, Action::PrevLink},
      {Term::Mods::None, Term::Key::ENTER, Action::FollowLink},
      {Term::Mods::None, Term::Key::BACKSPACE, Action::Back},
      {Term::Mods::Alt, Term::Key::LEFT, Action::Back},
      {Term::Mods::Ctrl, 'f'.ord, Action::Find},
      {Term::Mods::Ctrl, 'o'.ord, Action::OpenPage},
      {Term::Mods::None, Term::Key::F1 + 2, Action::FindNext},
      {Term::Mods::Shift, Term::Key::F1 + 2, Action::FindPrevious},
      {Term::Mods::Ctrl, 'b'.ord, Action::ToggleDock},
      {Term::Mods::Ctrl, 's'.ord, Action::SavePages},
      {Term::Mods::None, Term::Key::F1, Action::Help},
      {Term::Mods::None, Term::Key::ESCAPE, Action::Escape},
      {Term::Mods::Ctrl, 'l'.ord, Action::Redraw},
      {Term::Mods::Ctrl, 'q'.ord, Action::Quit},
      {Term::Mods::Ctrl, 'c'.ord, Action::Quit},
    ]

    # :nodoc:
    # Help text of the page view's actions, by help section, in help order.
    ACTION_HELP = {
      "General" => {
        Action::Help       => "help",
        Action::OpenPage   => "search all pages",
        Action::Find       => "find in the page (or just type)",
        Action::ToggleDock => "show or hide the dock",
        Action::SavePages  => "save the generated pages of the shard into its man directory",
        Action::Redraw     => "redraw",
        Action::Quit       => "quit",
      },
      "Viewer" => {
        Action::Top          => "top",
        Action::Bottom       => "bottom",
        Action::FindNext     => "next match",
        Action::FindPrevious => "previous match",
        Action::NextLink     => "next link",
        Action::PrevLink     => "previous link",
        Action::FollowLink   => "follow the link",
        Action::Back         => "back",
        Action::ToggleWrap   => "wrap or unwrap",
        Action::Escape       => "clear link focus and selection",
      },
    }

    # :nodoc:
    FIELD_HELP = {
      FieldAction::Accept     => "go to the match, or open the page",
      FieldAction::Cancel     => "to the picker",
      FieldAction::DeleteBack => "delete a character",
      FieldAction::Clear      => "clear",
      FieldAction::Next       => "next match or page",
      FieldAction::Previous   => "previous match or page",
      FieldAction::Expand     => "unfold the group",
      FieldAction::Collapse   => "fold the group",
    }

    # Dock tree bindings, in the same form as `DEFAULT_BINDINGS`.
    TREE_BINDINGS = [
      {Term::Mods::None, Term::Key::DOWN, TreeAction::Next},
      {Term::Mods::None, Term::Key::UP, TreeAction::Previous},
      {Term::Mods::None, Term::Key::ENTER, TreeAction::Open},
      {Term::Mods::None, Term::Key::RIGHT, TreeAction::Expand},
      {Term::Mods::None, Term::Key::LEFT, TreeAction::Collapse},
      {Term::Mods::None, Term::Key::TAB, TreeAction::Field},
      {Term::Mods::None, Term::Key::ESCAPE, TreeAction::Leave},
    ]

    # :nodoc:
    TREE_HELP = {
      TreeAction::Next     => "next row",
      TreeAction::Previous => "previous row",
      TreeAction::Open     => "open the page, or fold or unfold the group",
      TreeAction::Expand   => "unfold the group",
      TreeAction::Collapse => "fold the group",
      TreeAction::Field    => "to the search field",
      TreeAction::Leave    => "to the viewer",
    }

    # Search field bindings, in the same form as `DEFAULT_BINDINGS`.
    FIELD_BINDINGS = [
      {Term::Mods::None, Term::Key::ENTER, FieldAction::Accept},
      {Term::Mods::None, Term::Key::ESCAPE, FieldAction::Cancel},
      {Term::Mods::None, Term::Key::TAB, FieldAction::Cancel},
      {Term::Mods::None, Term::Key::BACKSPACE, FieldAction::DeleteBack},
      {Term::Mods::Ctrl, 'u'.ord, FieldAction::Clear},
      {Term::Mods::None, Term::Key::DOWN, FieldAction::Next},
      {Term::Mods::None, Term::Key::UP, FieldAction::Previous},
      {Term::Mods::None, Term::Key::RIGHT, FieldAction::Expand},
      {Term::Mods::None, Term::Key::LEFT, FieldAction::Collapse},
    ]

    # Maps keys (modifiers and key number) to values of type *T*.
    class Keymap(T)
      @table = Hash({Term::Mods, Int32}, T).new

      # Creates a keymap from {modifiers, key, value} *entries*; later ones win.
      def initialize(entries : Enumerable({Term::Mods, Int32, T}))
        entries.each { |mods, key, value| @table[{mods, key}] = value }
      end

      # Binds *binding* ({modifiers, key}) to *value*.
      def []=(binding : {Term::Mods, Int32}, value : T) : T
        @table[binding] = value
      end

      # The bindings of *value*, in the order they were made.
      def keys(value : T) : Array({Term::Mods, Int32})
        @table.compact_map { |binding, bound| bound == value ? binding : nil }
      end

      # :nodoc:
      # By physical key, then reported key, then shifted symbol without Shift.
      def lookup(event : Term::KeyEvent) : T?
        mods = event.mods.normalized
        if base = event.base
          if value = @table[{mods, base}]?
            return value
          end
        end
        if value = @table[{mods, event.key}]?
          return value
        end
        if mods.shift? && (shifted = event.shifted)
          return @table[{mods & ~Term::Mods::Shift, shifted}]?
        end
        nil
      end
    end

    # Page view key bindings (`DEFAULT_BINDINGS` unless given).
    class Bindings < Keymap(Action)
      def initialize(entries = DEFAULT_BINDINGS)
        super(entries)
      end
    end

    # Dock tree key bindings (`TREE_BINDINGS` unless given).
    class TreeBindings < Keymap(TreeAction)
      def initialize(entries = TREE_BINDINGS)
        super(entries)
      end
    end

    # Search field key bindings (`FIELD_BINDINGS` unless given).
    class FieldBindings < Keymap(FieldAction)
      def initialize(entries = FIELD_BINDINGS)
        super(entries)
      end
    end
  end
end
