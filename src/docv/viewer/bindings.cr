# src/docv/viewer/bindings.cr

module Docv
  class Viewer
    # Actions of the page view.
    enum Action
      LineDown
      LineUp
      PageDown
      PageUp
      HalfDown
      HalfUp
      Top
      Bottom
      Left
      Right
      HalfLeft
      HalfRight
      LineStart
      LineEnd
      ToggleWrap
      NextLink
      PrevLink
      FollowLink
      Back
      OpenPage
      Find
      ToggleDock
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
      PageNext
      PagePrevious
      Expand
      Collapse
      ScrollLeft
      ScrollRight
      Switch
    end

    # Actions of the dock's tree; unbound keys go to the page view.
    enum TreeAction
      Next
      Previous
      PageNext
      PagePrevious
      First
      Last
      Open
      Expand
      Collapse
      ScrollLeft
      ScrollRight
      Field
      Leave
    end

    # Page view bindings: {modifiers, key (codepoint or `Term::Key`), action}.
    DEFAULT_BINDINGS = [
      {Term::Mods::None, 'j'.ord, Action::LineDown},
      {Term::Mods::None, Term::Key::DOWN, Action::LineDown},
      {Term::Mods::Ctrl, 'n'.ord, Action::LineDown},
      {Term::Mods::Ctrl, 'e'.ord, Action::LineDown},
      {Term::Mods::None, 'k'.ord, Action::LineUp},
      {Term::Mods::None, Term::Key::UP, Action::LineUp},
      {Term::Mods::Ctrl, 'p'.ord, Action::LineUp},
      {Term::Mods::Ctrl, 'y'.ord, Action::LineUp},
      {Term::Mods::None, ' '.ord, Action::PageDown},
      {Term::Mods::Ctrl, 'f'.ord, Action::PageDown},
      {Term::Mods::None, Term::Key::PAGE_DOWN, Action::PageDown},
      {Term::Mods::None, 'b'.ord, Action::PageUp},
      {Term::Mods::Ctrl, 'b'.ord, Action::PageUp},
      {Term::Mods::Shift, ' '.ord, Action::PageUp},
      {Term::Mods::None, Term::Key::PAGE_UP, Action::PageUp},
      {Term::Mods::None, 'd'.ord, Action::HalfDown},
      {Term::Mods::Ctrl, 'd'.ord, Action::HalfDown},
      {Term::Mods::None, 'u'.ord, Action::HalfUp},
      {Term::Mods::Ctrl, 'u'.ord, Action::HalfUp},
      {Term::Mods::None, 'g'.ord, Action::Top},
      {Term::Mods::None, '<'.ord, Action::Top},
      {Term::Mods::None, Term::Key::HOME, Action::Top},
      {Term::Mods::None, 'G'.ord, Action::Bottom},
      {Term::Mods::None, '>'.ord, Action::Bottom},
      {Term::Mods::None, Term::Key::END, Action::Bottom},
      {Term::Mods::None, 'l'.ord, Action::Right},
      {Term::Mods::None, 'H'.ord, Action::HalfLeft},
      {Term::Mods::None, 'L'.ord, Action::HalfRight},
      {Term::Mods::None, '0'.ord, Action::LineStart},
      {Term::Mods::None, '$'.ord, Action::LineEnd},
      {Term::Mods::None, 'w'.ord, Action::ToggleWrap},
      {Term::Mods::None, Term::Key::TAB, Action::NextLink},
      {Term::Mods::Shift, Term::Key::TAB, Action::PrevLink},
      {Term::Mods::None, Term::Key::ENTER, Action::FollowLink},
      {Term::Mods::None, Term::Key::BACKSPACE, Action::Back},
      {Term::Mods::Alt, Term::Key::LEFT, Action::Back},
      {Term::Mods::None, 'f'.ord, Action::Find},
      {Term::Mods::None, 't'.ord, Action::Find},
      {Term::Mods::None, '/'.ord, Action::OpenPage},
      {Term::Mods::None, 'o'.ord, Action::OpenPage},
      {Term::Mods::None, 'p'.ord, Action::ToggleDock},
      {Term::Mods::None, 'h'.ord, Action::Help},
      {Term::Mods::None, Term::Key::ESCAPE, Action::Escape},
      {Term::Mods::Ctrl, 'l'.ord, Action::Redraw},
      {Term::Mods::None, 'q'.ord, Action::Quit},
      {Term::Mods::None, 'Q'.ord, Action::Quit},
      {Term::Mods::Ctrl, 'c'.ord, Action::Quit},
    ]

    # :nodoc:
    ACTION_HELP = {
      Action::LineDown   => "line down",
      Action::LineUp     => "line up",
      Action::PageDown   => "page down",
      Action::PageUp     => "page up",
      Action::HalfDown   => "half a page down",
      Action::HalfUp     => "half a page up",
      Action::Top        => "top",
      Action::Bottom     => "bottom",
      Action::Left       => "scroll left",
      Action::Right      => "scroll right",
      Action::HalfLeft   => "scroll left half a screen",
      Action::HalfRight  => "scroll right half a screen",
      Action::LineStart  => "line start",
      Action::LineEnd    => "line end",
      Action::ToggleWrap => "wrapped / unwrapped layout",
      Action::NextLink   => "next link",
      Action::PrevLink   => "previous link",
      Action::FollowLink => "follow the focused link",
      Action::Back       => "back to the previous page",
      Action::OpenPage   => "search pages and project documents (in the dock)",
      Action::Find       => "find in the page (in the dock)",
      Action::ToggleDock => "open or close the dock: search field and tree of pages",
      Action::Help       => "this help",
      Action::Escape     => "clear focus, selection and message",
      Action::Redraw     => "redraw",
      Action::Quit       => "quit",
    }

    # :nodoc:
    FIELD_HELP = {
      FieldAction::Accept       => "back to the page at the match / open the page / fold or unfold the group",
      FieldAction::Cancel       => "to the tree",
      FieldAction::DeleteBack   => "delete a character",
      FieldAction::Clear        => "clear the field",
      FieldAction::Next         => "next match or page",
      FieldAction::Previous     => "previous match or page",
      FieldAction::PageNext     => "a screenful of matches or pages down",
      FieldAction::PagePrevious => "a screenful of matches or pages up",
      FieldAction::Expand       => "unfold the page group, or step into it",
      FieldAction::Collapse     => "fold the page group, or step out to it",
      FieldAction::ScrollLeft   => "scroll the tree left",
      FieldAction::ScrollRight  => "scroll the tree right",
      FieldAction::Switch       => "to the tree",
    }

    # Dock tree bindings, in the same form as `DEFAULT_BINDINGS`.
    TREE_BINDINGS = [
      {Term::Mods::None, 'j'.ord, TreeAction::Next},
      {Term::Mods::None, Term::Key::DOWN, TreeAction::Next},
      {Term::Mods::Ctrl, 'n'.ord, TreeAction::Next},
      {Term::Mods::None, 'k'.ord, TreeAction::Previous},
      {Term::Mods::None, Term::Key::UP, TreeAction::Previous},
      {Term::Mods::Ctrl, 'p'.ord, TreeAction::Previous},
      {Term::Mods::None, Term::Key::PAGE_DOWN, TreeAction::PageNext},
      {Term::Mods::None, Term::Key::PAGE_UP, TreeAction::PagePrevious},
      {Term::Mods::None, 'g'.ord, TreeAction::First},
      {Term::Mods::None, Term::Key::HOME, TreeAction::First},
      {Term::Mods::None, 'G'.ord, TreeAction::Last},
      {Term::Mods::None, Term::Key::END, TreeAction::Last},
      {Term::Mods::None, Term::Key::ENTER, TreeAction::Open},
      {Term::Mods::None, 'l'.ord, TreeAction::Expand},
      {Term::Mods::None, Term::Key::RIGHT, TreeAction::Expand},
      {Term::Mods::None, Term::Key::LEFT, TreeAction::Collapse},
      {Term::Mods::None, 'H'.ord, TreeAction::ScrollLeft},
      {Term::Mods::Shift, Term::Key::LEFT, TreeAction::ScrollLeft},
      {Term::Mods::None, 'L'.ord, TreeAction::ScrollRight},
      {Term::Mods::Shift, Term::Key::RIGHT, TreeAction::ScrollRight},
      {Term::Mods::None, Term::Key::TAB, TreeAction::Field},
      {Term::Mods::None, Term::Key::ESCAPE, TreeAction::Leave},
    ]

    # :nodoc:
    TREE_HELP = {
      TreeAction::Next         => "next page or group",
      TreeAction::Previous     => "previous page or group",
      TreeAction::PageNext     => "a screenful down",
      TreeAction::PagePrevious => "a screenful up",
      TreeAction::First        => "first row",
      TreeAction::Last         => "last row",
      TreeAction::Open         => "open the page / fold or unfold the group",
      TreeAction::Expand       => "unfold the group, or step into it",
      TreeAction::Collapse     => "fold the group, or step out to it",
      TreeAction::ScrollLeft   => "scroll the tree left",
      TreeAction::ScrollRight  => "scroll the tree right",
      TreeAction::Field        => "to the search field",
      TreeAction::Leave        => "back to the page",
    }

    # Search field bindings, in the same form as `DEFAULT_BINDINGS`.
    FIELD_BINDINGS = [
      {Term::Mods::None, Term::Key::ENTER, FieldAction::Accept},
      {Term::Mods::None, Term::Key::ESCAPE, FieldAction::Cancel},
      {Term::Mods::Ctrl, 'c'.ord, FieldAction::Cancel},
      {Term::Mods::Ctrl, 'g'.ord, FieldAction::Cancel},
      {Term::Mods::None, Term::Key::BACKSPACE, FieldAction::DeleteBack},
      {Term::Mods::Ctrl, 'u'.ord, FieldAction::Clear},
      {Term::Mods::None, Term::Key::DOWN, FieldAction::Next},
      {Term::Mods::Ctrl, 'n'.ord, FieldAction::Next},
      {Term::Mods::None, Term::Key::UP, FieldAction::Previous},
      {Term::Mods::Ctrl, 'p'.ord, FieldAction::Previous},
      {Term::Mods::Shift, Term::Key::TAB, FieldAction::Previous},
      {Term::Mods::None, Term::Key::PAGE_DOWN, FieldAction::PageNext},
      {Term::Mods::None, Term::Key::PAGE_UP, FieldAction::PagePrevious},
      {Term::Mods::None, Term::Key::RIGHT, FieldAction::Expand},
      {Term::Mods::None, Term::Key::LEFT, FieldAction::Collapse},
      {Term::Mods::Shift, Term::Key::LEFT, FieldAction::ScrollLeft},
      {Term::Mods::Shift, Term::Key::RIGHT, FieldAction::ScrollRight},
      {Term::Mods::None, Term::Key::TAB, FieldAction::Switch},
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
