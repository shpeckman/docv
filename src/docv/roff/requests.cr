# src/docv/roff/requests.cr
module Docv::Roff
  class Engine
    # Requests that change nothing on a terminal reflowing viewer: page
    # geometry and traps, type sizes and spacing, hyphenation, kerning,
    # ligatures, output devices and debugging output.
    NO_OP = Set{
      "bd", "class", "color", "composite", "cp", "cs", "device", "devicem", "dt", "fam",
      "fc", "fl", "fspecial", "fzoom", "hc", "hcode", "hla", "hlm", "hpf", "hpfa", "hpfcode", "hw",
      "hy", "hym", "hys", "kern", "lc", "lf", "lg", "linetabs", "ls", "mc", "mk", "mso", "msoh",
      "msoquiet", "ne", "nh", "nm", "nn", "nroff", "os", "output", "pc", "pev",
      "pl", "pline", "pm", "pn", "pnr", "po", "ps", "psbb", "ptr", "pvs", "rt",
      "shc", "sizes", "special", "spreadwarn", "ss", "sv", "tag", "taga", "tkf", "troff",
      "uf", "vpt", "vs", "warn", "warnscale", "wh", "ch", "backtrace",
      "asciify", "unformat", "tc",
    }

    # Requests that cause a break unless called with the no-break control
    # character.
    BREAKING = Set{"bp", "br", "brp", "ce", "fi", "nf", "rj", "sp", "in", "ti"}

    # Runs a roff request; returns false when *name* is not a request.
    def request(name : String, raw : String, no_break : Bool) : Bool
      if UNSAFE.includes?(name)
        if @options.unsafe
          @builder.break_line if (name == "cf" || name == "trf") && !no_break
          unsafe_request(name, raw)
        end
        return true
      end
      @builder.break_line if BREAKING.includes?(name) && !no_break
      case name
      # definitions
      when "de", "de1"   then define(raw, append: false, indirect: false)
      when "dei", "dei1" then define(raw, append: false, indirect: true)
      when "am", "am1"   then define(raw, append: true, indirect: false)
      when "ami", "ami1" then define(raw, append: true, indirect: true)
      when "ds", "ds1"   then define_string(raw, append: false)
      when "as", "as1"   then define_string(raw, append: true)
      when "rm"          then args(raw).each { |key| remove_macro(key) }
      when "rn"          then two(raw) { |from, to| rename_macro(from, to) }
      when "als"         then two(raw) { |new_name, old| macro_body(old).try { |body| set_macro(new_name, body) } }
      when "ig"          then skip_until(args(raw).first? || ".")
      when "chop"        then args(raw).first?.try { |key| string(key).try { |value| set_string(key, value.rchop) } }
      when "length"      then length_request(raw)
      when "substring"   then substring(raw)
      when "stringup"    then args(raw).first?.try { |key| string(key).try { |value| set_string(key, value.upcase) } }
      when "stringdown"  then args(raw).first?.try { |key| string(key).try { |value| set_string(key, value.downcase) } }
        # registers
      when "nr"  then number_register(raw)
      when "rr"  then args(raw).each { |reg| @registers.delete(reg) }
      when "rnn" then two(raw) { |from, to| @registers.rename(from, to) }
      when "aln" then two(raw) { |new_name, old| @registers.alias(new_name, old) }
      when "af"  then two(raw) { |reg, format| @registers.format(reg, format) }
        # control flow and input
      when "if"               then conditional_body(*condition(raw))
      when "ie"               then if_else(raw)
      when "el"               then else_branch(raw)
      when "while"            then while_loop(raw)
      when "break"            then leave_loop(true)
      when "continue"         then leave_loop(false)
      when "return"           then return_from_macro
      when "shift"            then shift_args(args(raw).first?.try(&.to_i?) || 1)
      when "nop"              then process(raw) unless raw.empty?
      when "do"               then process("#{@cc}#{raw}") unless raw.empty?
      when "so", "soquiet"    then include_file(args(raw).first?)
      when "nx"               then args(raw).first?.try { |file| next_file(file) }
      when "ex"               then halt
      when "ab"               then abort_request(raw)
      when "tm", "tm1", "tmc" then message(raw)
      when "em"               then @end_macro = args(raw).first?
      when "blm"              then @blank_macro = args(raw).first?
      when "lsm"              then @space_macro = args(raw).first?
      when "it", "itc"        then trap_request(raw, name == "itc")
      when "di", "box"        then diversion(args(raw).first?, append: false)
      when "da", "boxa"       then diversion(args(raw).first?, append: true)
      when "ev"               then (env_name = args(raw).first?) ? push_env(env_name) : pop_env
      when "evc"              then args(raw).first?.try { |env_name| copy_env(env_name) }
        # characters
      when "cc"                               then self.control_char = args(raw).first?.try(&.[0]?) || '.'
      when "c2"                               then self.no_break_char = args(raw).first?.try(&.[0]?) || '\''
      when "ec"                               then escape_char(args(raw).first?.try(&.[0]?))
      when "eo"                               then escapes_off
      when "ecs"                              then save_escape
      when "ecr"                              then restore_escape
      when "tr", "trin", "trnt"               then translate(raw)
      when "char", "fchar", "fschar", "schar" then define_glyph(raw)
      when "rchar", "rfschar"                 then args(raw).each { |glyph| @glyphs.delete(glyph_name(glyph)) }
        # fonts and colors
      when "ft"       then select_font(args(raw).first? || "P")
      when "fp"       then two(raw) { |position, font| font_position(position, font) }
      when "ftr"      then two(raw) { |from, to| font_alias(from, to) }
      when "ul", "cu" then @env.underline = args(raw).first?.try(&.to_i?) || 1
      when "gcolor"   then color(raw, foreground: true)
      when "fcolor"   then color(raw, foreground: false)
      when "defcolor" then define_color(raw)
        # filling, breaking and spacing
      when "br", "brp"
      when "fi" then @env.fill = true
      when "nf" then @env.fill = false
      when "ad" then adjust(raw)
      when "na" then @env.adjust = Align::Left
      when "ce" then @env.center = count(raw)
      when "rj" then @env.rjust = count(raw)
      when "sp" then space(raw, no_break)
      when "bp" then @builder.blank(1)
      when "ns" then @builder.no_space = true
      when "rs" then @builder.no_space = false
      when "in" then indent(raw)
      when "ti" then temp_indent(raw)
      when "ll" then line_length(raw)
      when "lt" then title_length(raw)
      when "ta" then tabs(raw)
      when "tl" then title(raw)
      else
        return NO_OP.includes?(name)
      end
      true
    end

    # Arguments interpolated in copy mode.
    private def args(raw : String) : Array(String)
      split_args(interpolate(raw, true))
    end

    private def two(raw : String, & : String, String ->) : Nil
      list = args(raw)
      yield list[0], list[1] if list.size >= 2
    end

    private def count(raw : String) : Int32
      args(raw).first?.try { |text| Numeric.eval(text, 'u').try(&.to_i) } || 1
    end

    private def define(raw : String, append : Bool, indirect : Bool) : Nil
      list = args(raw)
      name = list[0]? || return
      terminator = list[1]? || "."
      if indirect
        name = string(name) || name
        terminator = list[1]?.try { |key| string(key) } || "."
      end
      body = read_body(terminator)
      if append && (existing = macro_body(name))
        set_macro(name, existing + body)
      else
        set_macro(name, body)
      end
    end

    private def define_string(raw : String, append : Bool) : Nil
      name, value = split_name(raw)
      return if name.empty?
      value = value[1..] if value.starts_with?('"')
      value = interpolate(value, true)
      if append
        set_string(name, (string(name) || "") + value)
      else
        set_string(name, value)
      end
    end

    private def length_request(raw : String) : Nil
      name, value = split_name(raw)
      value = value[1..] if value.starts_with?('"')
      @registers.set(name, plain_text(interpolate(value, false)).size.to_i64) unless name.empty?
    end

    private def substring(raw : String) : Nil
      list = args(raw)
      name = list[0]? || return
      value = string(name) || return
      size = value.size
      first = Numeric.eval(list[1]? || "0", 'u').try(&.to_i) || 0
      last = list[2]?.try { |text| Numeric.eval(text, 'u').try(&.to_i) } || size - 1
      first += size if first < 0
      last += size if last < 0
      first, last = last, first if first > last
      set_string(name, first < size ? value[first.clamp(0, size)..last.clamp(0, size - 1)] : "")
    end

    private def number_register(raw : String) : Nil
      list = args(raw)
      return if list.size < 2
      set_register_expression(list[0], list[1], list[2]?)
    end

    private def include_file(name : String?) : Nil
      return unless name
      content = @source.include(name)
      if content
        run_frame(Frame.new(Frame::Kind::File, split_lines(content), name))
      else
        @doc.messages << "cannot open include: #{name}"
      end
    end

    private def abort_request(raw : String) : Nil
      message(raw) unless raw.empty?
      halt
    end

    private def message(raw : String) : Nil
      @doc.messages << interpolate(raw, true) if @doc.messages.size < 200
    end

    private def trap_request(raw : String, continued : Bool) : Nil
      list = args(raw)
      lines = list[0]?.try { |text| Numeric.eval(text, 'u').try(&.to_i) } || 0
      input_trap(lines, list[1]?, continued)
    end

    private def translate(raw : String) : Nil
      text = plain_text(interpolate(raw, false)).strip
      chars = text.chars
      index = 0
      while index < chars.size
        from = chars[index]
        to = chars[index + 1]? || ' '
        if to == from
          @translations.delete(from)
        else
          @translations[from] = to.to_s
        end
        index += 2
      end
    end

    private def define_glyph(raw : String) : Nil
      name, value = split_name(raw)
      return if name.empty?
      value = value[1..] if value.starts_with?('"')
      @glyphs[glyph_name(name)] = interpolate(value, true)
    end

    private def glyph_name(text : String) : String
      if text.starts_with?("\\(") && text.size >= 4
        text[2, 2]
      elsif text.starts_with?("\\[")
        text[2...(text.index(']') || text.size)]
      elsif text.starts_with?("\\C'") && text.size > 3
        text[3...(text.index('\'', 3) || text.size)]
      else
        text
      end
    end

    private def color(raw : String, foreground : Bool) : Nil
      name = args(raw).first? || ""
      if foreground
        @env.prev_fg, @env.fg = @env.fg, (name.empty? ? @env.prev_fg : Colors[name]? || @env.fg)
      else
        @env.prev_bg, @env.bg = @env.bg, (name.empty? ? @env.prev_bg : Colors[name]? || @env.bg)
      end
    end

    private def define_color(raw : String) : Nil
      list = args(raw)
      return if list.size < 3
      Colors.define(list[0], list[1], list[2..].join(' '))
    end

    private def adjust(raw : String) : Nil
      mode = args(raw).first? || "b"
      @env.adjust = case mode
                    when "l"      then Align::Left
                    when "r"      then Align::Right
                    when "c"      then Align::Center
                    when "b", "n" then Align::Both
                    else
                      case Numeric.eval(mode, 'u')
                      when 1 then Align::Right
                      when 3 then Align::Center
                      when 0 then Align::Left
                      else        Align::Both
                      end
                    end
    end

    private def space(raw : String, no_break : Bool) : Nil
      lines = args(raw).first?.try { |text| Numeric.lines(text) } || 1
      return if lines <= 0
      if @env.fill?
        @builder.blank(lines)
      else
        @builder.blank(lines, hard: !@builder.no_space?)
      end
    end

    # Applies a relative (`+N`, `-N`) or absolute value in columns.
    private def relative(text : String, current : Int32) : Int32?
      return nil if text.empty?
      sign = text[0]
      value = Numeric.columns(sign == '+' || sign == '-' ? text[1..] : text, 'm') || return nil
      case sign
      when '+' then current + value
      when '-' then current - value
      else          value
      end
    end

    private def indent(raw : String) : Nil
      text = args(raw).first?
      new_indent = text ? relative(text, @env.indent) : @env.prev_indent
      return unless new_indent
      @env.prev_indent = @env.indent
      @env.indent = Math.max(new_indent, 0)
    end

    private def temp_indent(raw : String) : Nil
      text = args(raw).first? || return
      relative(text, @env.indent).try { |value| @env.temp_indent = Math.max(value, 0) }
    end

    private def line_length(raw : String) : Nil
      text = args(raw).first?
      value = text ? relative(text, @env.line_length) : @env.prev_line_length
      return unless value
      @env.prev_line_length = @env.line_length
      @env.line_length = value
    end

    private def title_length(raw : String) : Nil
      text = args(raw).first? || return
      relative(text, @env.title_length).try { |value| @env.title_length = value }
    end

    private def tabs(raw : String) : Nil
      list = args(raw)
      if list.empty?
        @env.tabs = Tabs::DEFAULT
        return
      end
      stops = [] of Int32
      repeat = [] of Int32
      repeating = false
      previous = 0
      list.each do |item|
        if item == "T"
          repeating = true
          next
        end
        spec = item.rstrip("LRC")
        position = if spec.starts_with?('+')
                     previous + (Numeric.columns(spec[1..], 'm') || 0)
                   else
                     Numeric.columns(spec, 'm') || previous
                   end
        repeating ? (repeat << position) : (stops << position)
        previous = position
      end
      step = if repeating && !repeat.empty?
               repeat.first - (stops.last? || 0)
             elsif stops.size >= 2
               stops[-1] - stops[-2]
             else
               stops.first? || 5
             end
      stops.concat(repeat)
      @env.tabs = Tabs.new(stops, Math.max(step, 1))
    end

    # `.tl 'left'center'right'`: a three-part title line.
    private def title(raw : String) : Nil
      text = interpolate(raw, false).lstrip
      return if text.empty?
      delim = text[0]
      parts = text[1..].split(delim)
      left, center, right = parts[0]? || "", parts[1]? || "", parts[2]? || ""
      @builder.break_line
      [left, center, right].map(&.gsub('%', '1')).reject(&.empty?).each_with_index do |part, index|
        @builder.text("   ", 0_u16) if index > 0
        emit(part)
      end
      @builder.break_line
    end
  end
end
