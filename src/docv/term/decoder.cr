# src/docv/term/decoder.cr

module Docv::Term
  # :nodoc:
  # Decodes input bytes into raw events; incomplete sequences wait for more.
  class Decoder
    # Longest control sequence accepted before it is discarded.
    MAX_SEQUENCE = 512
    # Longest OSC (`ESC ] ... ST`) accepted.
    MAX_OSC = 8192

    @pending = Bytes.empty

    def pending? : Bool
      !@pending.empty?
    end

    # Yields every complete event; the rest stays buffered.
    def feed(bytes : Bytes, & : Event ->) : Nil
      data = @pending.empty? ? bytes : concat(@pending, bytes)
      pos = 0
      while pos < data.size
        used = decode(data, pos, false) { |event| yield event }
        break if used == 0
        pos += used
      end
      @pending = pos < data.size ? data[pos..].dup : Bytes.empty
    end

    # Resolves buffered bytes after an input timeout: a lone ESC is Escape, `ESC ]` is Alt-].
    def flush(& : Event ->) : Nil
      data = @pending
      @pending = Bytes.empty
      pos = 0
      while pos < data.size
        used = decode(data, pos, true) { |event| yield event }
        pos += Math.max(used, 1)
      end
    end

    private def concat(a : Bytes, b : Bytes) : Bytes
      joined = Bytes.new(a.size + b.size)
      a.copy_to(joined)
      b.copy_to(joined + a.size)
      joined
    end

    # Decodes one event at *pos*; returns the bytes used (0: need more).
    private def decode(data : Bytes, pos : Int32, final : Bool, & : Event ->) : Int32
      byte = data[pos]
      case byte
      when 0x1b
        return escape(data, pos, final) { |event| yield event }
      when 0x0d
        yield KeyEvent.new(Key::ENTER)
      when 0x09
        yield KeyEvent.new(Key::TAB)
      when 0x7f, 0x08
        yield KeyEvent.new(Key::BACKSPACE)
      when 0x00
        yield KeyEvent.new(' '.ord, Mods::Ctrl)
      when 0x01..0x1a
        yield KeyEvent.new('a'.ord + byte - 1, Mods::Ctrl)
      when 0x1c..0x1f
        yield KeyEvent.new("\\]^_"[byte - 0x1c].ord, Mods::Ctrl)
      else
        return text(data, pos, final, Mods::None, 0) { |event| yield event }
      end
      1
    end

    private def text(data : Bytes, pos : Int32, final : Bool, mods : Mods, prefix : Int32, & : Event ->) : Int32
      byte = data[pos]
      length = if byte < 0x80
                 1
               elsif byte & 0xE0 == 0xC0
                 2
               elsif byte & 0xF0 == 0xE0
                 3
               elsif byte & 0xF8 == 0xF0
                 4
               else
                 1
               end
      if pos + length > data.size
        return final ? data.size - pos : 0
      end
      string = String.new(data[pos, length]).scrub
      char = string[0]
      if char.uppercase? && char.downcase != char
        yield KeyEvent.new(char.downcase.ord, mods | Mods::Shift, shifted: char.ord, text: string)
      else
        yield KeyEvent.new(char.ord, mods, text: mods.alt? ? nil : string)
      end
      prefix + length
    end

    private def escape(data : Bytes, pos : Int32, final : Bool, & : Event ->) : Int32
      if pos + 1 >= data.size
        return 0 unless final
        yield KeyEvent.new(Key::ESCAPE)
        return 1
      end
      case data[pos + 1]
      when '['.ord
        csi(data, pos, final) { |event| yield event }
      when ']'.ord
        osc(data, pos, final) { |event| yield event }
      when 'O'.ord
        if pos + 2 >= data.size
          return 0 unless final
          yield KeyEvent.new('O'.ord, Mods::Alt | Mods::Shift)
          return 2
        end
        if key = Key::LETTERS[data[pos + 2].unsafe_chr]?
          yield KeyEvent.new(key)
        end
        3
      when 0x1b
        yield KeyEvent.new(Key::ESCAPE)
        1
      when 0x0d
        yield KeyEvent.new(Key::ENTER, Mods::Alt)
        2
      when 0x7f, 0x08
        yield KeyEvent.new(Key::BACKSPACE, Mods::Alt)
        2
      else
        text(data, pos + 1, final, Mods::Alt, 1) { |event| yield event }
      end
    end

    private def csi(data : Bytes, pos : Int32, final : Bool, & : Event ->) : Int32
      index = pos + 2
      while index < data.size
        byte = data[index]
        break if 0x40 <= byte <= 0x7e
        unless 0x20 <= byte <= 0x3f
          return index - pos
        end
        index += 1
        return index - pos if index - pos > MAX_SEQUENCE
      end
      if index >= data.size
        return final ? data.size - pos : 0
      end
      body = String.new(data[pos + 2, index - pos - 2])
      dispatch(body, data[index].unsafe_chr) { |event| yield event }
      index + 1 - pos
    end

    # `ESC ] body ST` (ST is `ESC \` or BEL); unterminated at the timeout it is Alt-].
    private def osc(data : Bytes, pos : Int32, final : Bool, & : Event ->) : Int32
      index = pos + 2
      while index < data.size
        case data[index]
        when 0x07
          report(data[pos + 2, index - pos - 2]) { |event| yield event }
          return index + 1 - pos
        when 0x1b
          if index + 1 >= data.size
            break if final
            return 0
          end
          return index - pos unless data[index + 1] == '\\'.ord
          report(data[pos + 2, index - pos - 2]) { |event| yield event }
          return index + 2 - pos
        end
        index += 1
        return index - pos if index - pos > MAX_OSC
      end
      return 0 unless final
      yield KeyEvent.new(']'.ord, Mods::Alt)
      2
    end

    # An OSC 21 color report: `21;key=value;...`.
    private def report(body : Bytes, & : Event ->) : Nil
      text = String.new(body).scrub
      return unless text.starts_with?("21;")
      colors = {} of String => String
      text[3..].split(';').each do |field|
        key, equals, value = field.partition('=')
        colors[key.strip] = value.strip unless equals.empty?
      end
      yield ColorsReport.new(colors)
    end

    private def dispatch(body : String, final : Char, & : Event ->) : Nil
      prefix = body[0]? && "<=>?".includes?(body[0]) ? body[0] : nil
      params = prefix ? body[1..] : body
      intermediate = params.each_char.select { |char| 0x20 <= char.ord <= 0x2f }.join
      params = params.delete { |char| 0x20 <= char.ord <= 0x2f }
      case {prefix, final}
      when {'<', 'M'}, {'<', 'm'}
        mouse(params, final == 'm').try { |event| yield event }
      when {'?', 'u'}
        yield KeyboardFlagsReport.new(params.to_i? || 0)
      when {'?', 'n'}
        fields = numbers(params)
        case fields[0]?
        when 997 then yield ColorSchemeEvent.new(fields[1]? == 1)
        when 999 then yield VisibilityEvent.new(fields[1]? != 2)
        end
      when {'?', 'y'}
        if intermediate == "$"
          fields = numbers(params)
          yield ModeReport.new(fields[0]? || 0, fields[1]? || 0)
        end
      when {nil, 'u'}
        kitty(params).try { |event| yield event }
      when {nil, '~'}
        tilde(params).try { |event| yield event }
      when {nil, 't'}
        fields = numbers(params)
        case fields[0]?
        when 48
          yield ResizeEvent.new(fields[1]? || 0, fields[2]? || 0, fields[3]? || 0, fields[4]? || 0)
        when 6
          yield CellSizeReport.new(fields[1]? || 0, fields[2]? || 0)
        end
      when {nil, 'I'}
        yield FocusEvent.new(true)
      when {nil, 'O'}
        yield FocusEvent.new(false)
      when {nil, 'Z'}
        yield KeyEvent.new(Key::TAB, Mods::Shift)
      else
        if prefix.nil? && (key = Key::LETTERS[final]?)
          mods, action, _ = modifiers(params.split(';')[1]?)
          yield KeyEvent.new(key, mods, action)
        end
      end
    end

    private def numbers(params : String) : Array(Int32)
      params.split(';').map { |field| field.split(':').first.to_i? || 0 }
    end

    # Parses `mods:event`; returns modifiers, action and whether present.
    private def modifiers(field : String?) : {Mods, KeyAction, Bool}
      return {Mods::None, KeyAction::Press, false} if field.nil? || field.empty?
      parts = field.split(':')
      wire = parts[0].to_i? || 1
      mods = Mods.new(((wire - 1) & 0xff).to_u8)
      action = case parts[1]?.try(&.to_i?)
               when 2 then KeyAction::Repeat
               when 3 then KeyAction::Release
               else        KeyAction::Press
               end
      {mods, action, true}
    end

    # `CSI key:shifted:base ; mods:event ; text u`.
    private def kitty(params : String) : KeyEvent?
      fields = params.split(';')
      codes = (fields[0]? || "").split(':')
      key = codes[0]?.try(&.to_i?) || 0
      shifted = codes[1]?.try { |code| code.empty? ? nil : code.to_i? }
      base = codes[2]?.try { |code| code.empty? ? nil : code.to_i? }
      mods, action, _ = modifiers(fields[1]?)
      text = fields[2]?.try do |field|
        String.build do |io|
          field.split(':').each { |code| code.to_i?.try { |value| io << value.chr if 0x20 <= value <= 0x10FFFF } }
        end.presence
      end
      key = Key::KEYPAD[key]? || key
      KeyEvent.new(key, mods, action, shifted, base, text)
    end

    private def tilde(params : String) : KeyEvent?
      fields = params.split(';')
      number = fields[0]?.try(&.split(':').first.to_i?) || return nil
      key = Key::TILDE[number]? || return nil
      mods, action, _ = modifiers(fields[1]?)
      KeyEvent.new(key, mods, action)
    end

    # SGR mouse report, decoded in the priority order of the protocol.
    private def mouse(params : String, release : Bool) : MouseEvent?
      fields = numbers(params)
      return nil if fields.size < 3
      code, x, y = fields[0], fields[1], fields[2]
      mods = Mods::None
      mods |= Mods::Shift if code & 4 != 0
      mods |= Mods::Alt if code & 8 != 0
      mods |= Mods::Ctrl if code & 16 != 0
      low = code & 3
      if code & 256 != 0
        return MouseEvent.new(MouseAction::Leave, MouseButton::None, mods, x, y)
      end
      if code & 64 != 0
        button = MouseButton.new((MouseButton::WheelUp.value + low).to_u8)
        return MouseEvent.new(MouseAction::Scroll, button, mods, x, y)
      end
      if code & 32 != 0 && low == 3
        return MouseEvent.new(MouseAction::Hover, MouseButton::None, mods, x, y)
      end
      button = if code & 128 != 0
                 MouseButton.new((MouseButton::Aux8.value + low).to_u8)
               else
                 MouseButton.new(low.to_u8)
               end
      action = if release
                 MouseAction::Release
               elsif code & 32 != 0
                 MouseAction::Drag
               else
                 MouseAction::Press
               end
      MouseEvent.new(action, button, mods, x, y)
    end
  end
end
