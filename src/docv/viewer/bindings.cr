# src/docv/viewer/bindings.cr
module Docv
  class Viewer
    # Everything a key can do in the page view.
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
      Help
      Escape
      Redraw
      Quit
    end

    # Everything a key can do while the search bar has the keyboard. Text
    # keys insert.
    enum FieldAction
      Accept
      Cancel
      DeleteBack
      Clear
      Next
      Previous
      PageNext
      PagePrevious
    end

    # Page view bindings: modifiers, key number (codepoint or `Term::Key`),
    # action.
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
      {Term::Mods::None, Term::Key::LEFT, Action::Left},
      {Term::Mods::None, 'l'.ord, Action::Right},
      {Term::Mods::None, Term::Key::RIGHT, Action::Right},
      {Term::Mods::None, 'H'.ord, Action::HalfLeft},
      {Term::Mods::Shift, Term::Key::LEFT, Action::HalfLeft},
      {Term::Mods::None, 'L'.ord, Action::HalfRight},
      {Term::Mods::Shift, Term::Key::RIGHT, Action::HalfRight},
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
      {Term::Mods::None, 'h'.ord, Action::Help},
      {Term::Mods::None, Term::Key::ESCAPE, Action::Escape},
      {Term::Mods::Ctrl, 'l'.ord, Action::Redraw},
      {Term::Mods::None, 'q'.ord, Action::Quit},
      {Term::Mods::None, 'Q'.ord, Action::Quit},
      {Term::Mods::Ctrl, 'c'.ord, Action::Quit},
    ]

    # What each action does, for the help.
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
      Action::OpenPage   => "search pages and project documents",
      Action::Find       => "find in the page",
      Action::Help       => "this help",
      Action::Escape     => "clear focus, selection and message",
      Action::Redraw     => "redraw",
      Action::Quit       => "quit",
    }

    # What each search bar action does, for the help.
    FIELD_HELP = {
      FieldAction::Accept       => "stay at the match / open the page",
      FieldAction::Cancel       => "leave the search bar",
      FieldAction::DeleteBack   => "delete a character",
      FieldAction::Clear        => "clear the search bar",
      FieldAction::Next         => "next match or page",
      FieldAction::Previous     => "previous match or page",
      FieldAction::PageNext     => "a screenful of matches or pages down",
      FieldAction::PagePrevious => "a screenful of matches or pages up",
    }

    # Search bar bindings, in the same form as `DEFAULT_BINDINGS`.
    FIELD_BINDINGS = [
      {Term::Mods::None, Term::Key::ENTER, FieldAction::Accept},
      {Term::Mods::None, Term::Key::ESCAPE, FieldAction::Cancel},
      {Term::Mods::Ctrl, 'c'.ord, FieldAction::Cancel},
      {Term::Mods::Ctrl, 'g'.ord, FieldAction::Cancel},
      {Term::Mods::None, Term::Key::BACKSPACE, FieldAction::DeleteBack},
      {Term::Mods::Ctrl, 'u'.ord, FieldAction::Clear},
      {Term::Mods::None, Term::Key::DOWN, FieldAction::Next},
      {Term::Mods::Ctrl, 'n'.ord, FieldAction::Next},
      {Term::Mods::None, Term::Key::TAB, FieldAction::Next},
      {Term::Mods::None, Term::Key::UP, FieldAction::Previous},
      {Term::Mods::Ctrl, 'p'.ord, FieldAction::Previous},
      {Term::Mods::Shift, Term::Key::TAB, FieldAction::Previous},
      {Term::Mods::None, Term::Key::PAGE_DOWN, FieldAction::PageNext},
      {Term::Mods::None, Term::Key::PAGE_UP, FieldAction::PagePrevious},
    ]

    # Maps key events to values of *T*: first by physical key (base layout),
    # then by the reported key, then by the shifted symbol without its
    # shift.
    class Keymap(T)
      @table = Hash({Term::Mods, Int32}, T).new

      def initialize(entries : Enumerable({Term::Mods, Int32, T}))
        entries.each { |mods, key, value| @table[{mods, key}] = value }
      end

      # Binds *mods* + *key* to *value*.
      def []=(binding : {Term::Mods, Int32}, value : T) : T
        @table[binding] = value
      end

      # The bindings of *value*, in the order they were made.
      def keys(value : T) : Array({Term::Mods, Int32})
        @table.compact_map { |binding, bound| bound == value ? binding : nil }
      end

      # The value bound to *event*, if any.
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

    # Search bar key bindings (`FIELD_BINDINGS` unless given).
    class FieldBindings < Keymap(FieldAction)
      def initialize(entries = FIELD_BINDINGS)
        super(entries)
      end
    end
  end
end
