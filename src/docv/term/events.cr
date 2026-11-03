# src/docv/term/events.cr
module Docv::Term
  # Kitty keyboard protocol key numbers for keys that are not text.
  module Key
    ESCAPE    =    27
    ENTER     =    13
    TAB       =     9
    BACKSPACE =   127
    INSERT    = 57348
    DELETE    = 57349
    LEFT      = 57350
    RIGHT     = 57351
    UP        = 57352
    DOWN      = 57353
    PAGE_UP   = 57354
    PAGE_DOWN = 57355
    HOME      = 57356
    END       = 57357

    CAPS_LOCK    = 57358
    SCROLL_LOCK  = 57359
    NUM_LOCK     = 57360
    PRINT_SCREEN = 57361
    PAUSE        = 57362
    MENU         = 57363

    # `F1` is 57364; `F1 + n - 1` is F*n* up to F35.
    F1  = 57364
    F35 = 57398

    KP_0         = 57399
    KP_9         = 57408
    KP_DECIMAL   = 57409
    KP_DIVIDE    = 57410
    KP_MULTIPLY  = 57411
    KP_SUBTRACT  = 57412
    KP_ADD       = 57413
    KP_ENTER     = 57414
    KP_EQUAL     = 57415
    KP_SEPARATOR = 57416
    KP_LEFT      = 57417
    KP_RIGHT     = 57418
    KP_UP        = 57419
    KP_DOWN      = 57420
    KP_PAGE_UP   = 57421
    KP_PAGE_DOWN = 57422
    KP_HOME      = 57423
    KP_END       = 57424
    KP_INSERT    = 57425
    KP_DELETE    = 57426
    KP_BEGIN     = 57427

    MEDIA_FIRST = 57428
    MEDIA_LAST  = 57440

    # Modifier keys: LEFT_SHIFT (57441) through ISO_LEVEL5_SHIFT (57454).
    MODIFIER_FIRST = 57441
    MODIFIER_LAST  = 57454

    # Keypad keys and the navigation keys they duplicate.
    KEYPAD = {
      KP_ENTER => ENTER, KP_LEFT => LEFT, KP_RIGHT => RIGHT, KP_UP => UP, KP_DOWN => DOWN,
      KP_PAGE_UP => PAGE_UP, KP_PAGE_DOWN => PAGE_DOWN, KP_HOME => HOME, KP_END => END,
      KP_INSERT => INSERT, KP_DELETE => DELETE,
    }

    # Legacy `CSI 1 ; mods <letter>` and SS3 finals.
    LETTERS = {
      'A' => UP, 'B' => DOWN, 'C' => RIGHT, 'D' => LEFT, 'E' => KP_BEGIN, 'F' => END, 'H' => HOME,
      'P' => F1, 'Q' => F1 + 1, 'R' => F1 + 2, 'S' => F1 + 3,
    }

    # Legacy `CSI number ; mods ~` keys.
    TILDE = {
      2 => INSERT, 3 => DELETE, 5 => PAGE_UP, 6 => PAGE_DOWN, 7 => HOME, 8 => END,
      11 => F1, 12 => F1 + 1, 13 => F1 + 2, 14 => F1 + 3, 15 => F1 + 4, 17 => F1 + 5,
      18 => F1 + 6, 19 => F1 + 7, 20 => F1 + 8, 21 => F1 + 9, 23 => F1 + 10, 24 => F1 + 11,
      29 => MENU, 57427 => KP_BEGIN,
    }

    # True for the modifier keys themselves.
    def self.modifier?(key : Int32) : Bool
      MODIFIER_FIRST <= key <= MODIFIER_LAST
    end
  end

  # Modifier state; the wire value is `1 +` these bits.
  @[Flags]
  enum Mods : UInt8
    Shift
    Alt
    Ctrl
    Super
    Hyper
    Meta
    CapsLock
    NumLock

    # Lock bits are level state, not part of a shortcut.
    LOCKS = CapsLock | NumLock
    # Modifiers that make a key a command rather than text.
    COMMAND = Ctrl | Super | Hyper | Meta

    # The modifiers without lock state.
    def normalized : Mods
      self & ~LOCKS
    end
  end

  enum KeyAction : UInt8
    Press   = 1
    Repeat  = 2
    Release = 3
  end

  # A key report: key number (un-shifted codepoint or `Key` constant), the
  # shifted and base-layout alternates, modifiers, action and text.
  record KeyEvent, key : Int32, mods : Mods = Mods::None, action : KeyAction = KeyAction::Press,
    shifted : Int32? = nil, base : Int32? = nil, text : String? = nil

  enum MouseButton : UInt8
    Left
    Middle
    Right
    None
    WheelUp
    WheelDown
    WheelLeft
    WheelRight
    Aux8
    Aux9
    Aux10
    Aux11
  end

  enum MouseAction : UInt8
    Press
    Release
    Drag
    Hover
    Scroll
    Leave
  end

  # A mouse report in raw coordinates: pixels under SGR-pixel mode (1016),
  # 1-based cells under plain SGR (1006).
  record MouseEvent, action : MouseAction, button : MouseButton, mods : Mods, x : Int32, y : Int32

  # In-band resize (`CSI 48 ; h ; w ; hpx ; wpx t`).
  record ResizeEvent, rows : Int32, cols : Int32, height : Int32, width : Int32

  # Focus gained or lost.
  record FocusEvent, focused : Bool

  # Window restored or minimized.
  record VisibilityEvent, visible : Bool

  # Dark or light color scheme.
  record ColorSchemeEvent, dark : Bool

  # DECRQM answer: `value` 1 set, 2 reset, 0 unknown.
  record ModeReport, mode : Int32, value : Int32

  # Cell size in pixels (`CSI 6 ; h ; w t`).
  record CellSizeReport, height : Int32, width : Int32

  # Current kitty keyboard flags (`CSI ? flags u`).
  record KeyboardFlagsReport, flags : Int32

  # Terminal colors in answer to an OSC 21 query: key (`foreground`,
  # `background`, a palette index) to value (`rgb:rr/gg/bb`, empty when
  # unset), as the terminal sent them.
  record ColorsReport, colors : Hash(String, String)

  alias Event = KeyEvent | MouseEvent | ResizeEvent | FocusEvent | VisibilityEvent | ColorSchemeEvent |
                ModeReport | CellSizeReport | KeyboardFlagsReport | ColorsReport
end
