# src/docv/roff/engine.cr

# :nodoc:
module Docv::Roff
  # A natively implemented macro package (man, mdoc).
  abstract class Package
    def initialize(@engine : Engine)
    end

    abstract def handles?(name : String) : Bool

    # *line* holds the arguments, already interpolated in copy mode.
    abstract def call(name : String, line : String) : Nil

    abstract def format : Format

    # Called once at the end of input.
    def finish : Nil
    end
  end

  # An input source on the input stack.
  class Frame
    enum Kind : UInt8
      File
      Macro
      Body
      While
    end

    getter kind : Kind
    getter lines : Array(String)
    getter name : String
    property args : Array(String)
    property pos : Int32 = 0
    property? broken : Bool = false

    def initialize(@kind : Kind, @lines : Array(String), @name : String = "", @args = [] of String)
    end

    def done? : Bool
      @pos >= @lines.size
    end

    def finish : Nil
      @pos = @lines.size
    end
  end

  # The roff interpreter; drives a native macro package and a `Builder`.
  class Engine
    # Input stack depth limit (guards macro recursion).
    MAX_DEPTH = 120
    # Iteration limit of one `.while` loop.
    MAX_LOOP = 10_000

    getter doc : Document
    getter builder : Builder
    getter registers = Registers.new
    getter source : Source
    getter options : Options
    getter env : Env = Env.new

    # Strings and macros share one namespace, as in groff.
    @macros = Hash(String, Array(String)).new
    @frames = [] of Frame
    @cc = '.'
    @c2 = '\''
    @ec = '\\'
    @escapes = true
    @saved_ec = '\\'
    @translations = Hash(Char, String).new
    @glyphs = Hash(String, String).new
    @conditions = [] of Bool
    @env_stack = [] of Env
    @envs = Hash(String, Env).new
    @font_positions = {"1" => "R", "2" => "I", "3" => "B", "4" => "BI"}
    @font_aliases = Hash(String, String).new
    @input_trap = 0
    @input_trap_macro : String? = nil
    @input_trap_continued = false
    @end_macro : String? = nil
    @blank_macro : String? = nil
    @space_macro : String? = nil
    @diversions = [] of {String, Array(String)}
    @line_hooks = [] of ->
    @line_capture : (Array(Span) ->)? = nil
    @halted = false
    @next_file : String? = nil
    @package : Package? = nil
    @man : Package? = nil
    @mdoc : Package? = nil
    @columns = 78

    def initialize(@source : Source = Source.new, @columns : Int32 = 78, @options : Options = Options.new)
      @doc = Document.new
      @builder = Builder.new(@env)
      @env.line_length = @columns
      @env.prev_line_length = @columns
      @env.title_length = @columns
      predefine
    end

    def env=(env : Env) : Env
      @builder.env = env
      @env = env
    end

    private def man : Package
      @man ||= Macros::Man.new(self)
    end

    private def mdoc : Package
      @mdoc ||= Macros::Mdoc.new(self)
    end

    # Interprets *text* and returns the document.
    def run(text : String) : Document
      run_frame(Frame.new(Frame::Kind::File, split_lines(text), @source.path || ""))
      while (next_file = @next_file) && !@halted
        @next_file = nil
        content = @source.include(next_file)
        break unless content
        run_frame(Frame.new(Frame::Kind::File, split_lines(content), next_file))
      end
      if (end_macro = @end_macro) && !@halted
        call_name(end_macro, "")
      end
      close_diversions
      @package.try &.finish
      @builder.finish
      @doc.blocks = @builder.blocks
      @doc.format = @package.try(&.format) || Format::Roff
      run_pipes
      @doc
    ensure
      close_streams
    end

    # --- input stack -------------------------------------------------------

    def run_frame(frame : Frame) : Nil
      return if @frames.size >= MAX_DEPTH
      floor = @frames.size
      @frames << frame
      while line = next_line(floor)
        process(line)
      end
      @frames.pop if @frames.size > floor
    end

    # Interprets *lines* as input (package macro bodies, conditional bodies).
    def run_lines(lines : Array(String), kind : Frame::Kind = Frame::Kind::Body) : Nil
      run_frame(Frame.new(kind, lines, "", current_args))
    end

    # Next input line from frames above *floor*, with escaped newlines joined.
    def next_line(floor : Int32) : String?
      return nil if @halted
      while @frames.size > floor
        frame = @frames.last
        if frame.done?
          return nil if @frames.size == floor + 1
          @frames.pop
          next
        end
        line = read_raw(frame)
        while continued?(line) && !frame.done?
          line = line.byte_slice(0, line.bytesize - 1) + read_raw(frame)
        end
        line = line.byte_slice(0, line.bytesize - 1) if continued?(line)
        return line
      end
      nil
    end

    private def read_raw(frame : Frame) : String
      line = frame.lines[frame.pos]
      frame.pos += 1
      frame.kind.file? ? translate_escape(line) : line
    end

    private def continued?(line : String) : Bool
      count = 0
      index = line.bytesize - 1
      while index >= 0 && line.byte_at(index) == '\\'.ord
        count += 1
        index -= 1
      end
      count.odd?
    end

    # Rewrites a line for `.ec`/`.eo` so the rest of the engine only sees backslashes.
    private def translate_escape(line : String) : String
      return line if @escapes && @ec == '\\'
      String.build(line.bytesize) do |io|
        line.each_char do |char|
          if char == '\\'
            io << "\\(rs"
          elsif @escapes && char == @ec
            io << '\\'
          else
            io << char
          end
        end
      end
    end

    private def split_lines(text : String) : Array(String)
      lines = text.split('\n')
      lines.pop if lines.last? == ""
      lines.map!(&.rchop('\r'))
    end

    def frame_depth : Int32
      @frames.size
    end

    def current_args : Array(String)
      @frames.reverse_each { |frame| return frame.args if frame.kind.macro? }
      [] of String
    end

    private def macro_frame : Frame?
      @frames.reverse_each { |frame| return frame if frame.kind.macro? }
      nil
    end

    # --- line dispatch -----------------------------------------------------

    def process(line : String) : Nil
      line = strip_closing_braces(line)
      return if line.nil?
      unless @diversions.empty?
        return if divert(line)
      end
      if line.empty? || line.each_char.all? { |char| char == ' ' || char == '\t' }
        blank_line
        return
      end
      first = line[0]
      if first == @cc || first == @c2
        control(line[1..], first == @c2)
      else
        text_line(line)
      end
    end

    # Drops leading `\}`; `nil` when nothing else is on the line.
    private def strip_closing_braces(line : String) : String?
      return line unless line.includes?("\\}")
      stripped = line
      loop do
        if stripped.starts_with?("\\}")
          stripped = stripped[2..]
        elsif (stripped.starts_with?(@cc) || stripped.starts_with?(@c2)) && stripped[1..].lstrip(" \t").starts_with?("\\}")
          rest = stripped[1..].lstrip(" \t")[2..]
          stripped = rest.lstrip(" \t").empty? ? "" : "#{stripped[0]}#{rest}"
        else
          break
        end
      end
      return nil if stripped.empty? && !line.empty?
      stripped
    end

    private def control(rest : String, no_break : Bool) : Nil
      rest = rest.lstrip(" \t")
      return if rest.empty? || rest.starts_with?("\\\"") || rest.starts_with?("\\#")
      name, args = split_name(rest)
      name = interpolate(name, true) if name.includes?('\\')
      return if name.empty?
      dispatch(name, args, no_break)
    end

    private def split_name(rest : String) : {String, String}
      index = 0
      bytes = rest.to_slice
      while index < bytes.size
        byte = bytes[index]
        break if byte == ' '.ord || byte == '\t'.ord
        if byte == '\\'.ord && index + 1 < bytes.size
          following = bytes[index + 1]
          break if index > 0 && following != '*'.ord && following != 'n'.ord && following != '$'.ord
          break if following == '"'.ord || following == '#'.ord || following == '{'.ord || following == '}'.ord
        end
        index += 1
      end
      name = rest.byte_slice(0, index)
      args = rest.byte_slice(index, rest.bytesize - index)
      args = args.lstrip(" \t")
      {name, args}
    end

    # Runs *name* with uninterpolated *args*.
    def dispatch(name : String, args : String, no_break : Bool = false) : Nil
      if name == "TS"
        Tbl.new(self).run(args)
      elsif body = @macros[name]?
        invoke(name, body, split_args(interpolate(args, true)))
      elsif package = package_for(name)
        package.call(name, interpolate(args, true))
      elsif !request(name, args, no_break)
        @doc.messages << "unknown request or macro: #{name}" if @doc.messages.size < 200
      end
    end

    # Runs *name* with an already interpolated *line* (packages calling macros).
    def call_name(name : String, line : String) : Nil
      if body = @macros[name]?
        invoke(name, body, split_args(line))
      elsif package = package_for(name)
        package.call(name, line)
      else
        request(name, line, false)
      end
    end

    def defined?(name : String) : Bool
      @macros.has_key?(name)
    end

    def invoke(name : String, body : Array(String), args : Array(String)) : Nil
      run_frame(Frame.new(Frame::Kind::Macro, body, name, args))
    end

    private def package_for(name : String) : Package?
      if package = @package
        return package if package.handles?(name)
        return nil
      end
      chosen = if name == "Dd" || name == "Dt" || name == "Sh"
                 mdoc
               elsif man.handles?(name)
                 man
               elsif mdoc.handles?(name)
                 mdoc
               end
      @package = chosen
      chosen
    end

    # Splits at blanks; double quotes group, and `""` inside them is a literal quote.
    def split_args(line : String) : Array(String)
      args = [] of String
      reader = Char::Reader.new(line)
      while reader.has_next?
        char = reader.current_char
        if char == ' ' || char == '\t'
          reader.next_char
          next
        end
        arg = String.build do |io|
          if char == '"'
            reader.next_char
            while reader.has_next?
              char = reader.current_char
              if char == '"'
                reader.next_char
                if reader.has_next? && reader.current_char == '"'
                  io << '"'
                  reader.next_char
                else
                  break
                end
              else
                io << char
                reader.next_char
              end
            end
          else
            while reader.has_next?
              char = reader.current_char
              break if char == ' ' || char == '\t'
              io << char
              reader.next_char
              if char == '\\' && reader.has_next?
                io << reader.current_char
                reader.next_char
              end
            end
          end
        end
        args << arg
      end
      args
    end

    # --- text lines ----------------------------------------------------------

    private def blank_line : Nil
      if handler = @blank_macro
        call_name(handler, "")
        return
      end
      if @env.fill?
        @builder.blank(1)
      else
        @builder.break_line
        @builder.blank(1, hard: true)
      end
    end

    private def text_line(line : String) : Nil
      if @env.fill? && (line[0] == ' ' || line[0] == '\t')
        if handler = @space_macro
          call_name(handler, "")
        else
          @builder.break_line
        end
      end
      continued = emit(interpolate(line, false))
      text_line_done(continued)
    end

    # Ends an output line: space or break, captures, hooks, `.ce`/`.rj` counts, input traps.
    def text_line_done(continued : Bool = false) : Nil
      return if continued
      if capture = @line_capture
        @line_capture = nil
        capture.call(@builder.end_capture)
      end
      if @env.fill? && @env.center == 0 && @env.rjust == 0
        @builder.word_space
      else
        @builder.break_line
      end
      @env.center -= 1 if @env.center > 0
      @env.rjust -= 1 if @env.rjust > 0
      @env.underline -= 1 if @env.underline > 0
      unless @line_hooks.empty?
        hooks = @line_hooks.dup
        @line_hooks.clear
        hooks.each &.call
      end
      if @input_trap > 0
        @input_trap -= 1
        if @input_trap == 0 && (handler = @input_trap_macro)
          @input_trap_macro = nil
          call_name(handler, "")
        end
      end
    end

    # Runs *hook* after the next output-producing input line.
    def after_next_line(&hook : ->) : Nil
      @line_hooks << hook
    end

    # Hands the spans of the next input line to *block* (`.TP` tags, bare `.SH`).
    def capture_next_line(&block : Array(Span) ->) : Nil
      @builder.begin_capture
      @line_capture = block
    end

    def capturing_line? : Bool
      !@line_capture.nil?
    end

    # --- conditionals --------------------------------------------------------

    # Evaluates a conditional; returns the result and the body.
    def condition(raw : String) : {Bool, String}
      text = raw.lstrip(" \t")
      negate = false
      while text.starts_with?('!')
        negate = !negate
        text = text[1..]
      end
      result, rest = evaluate_condition(text)
      {negate ? !result : result, rest.lstrip(" \t")}
    end

    private def evaluate_condition(text : String) : {Bool, String}
      return {false, ""} if text.empty?
      first = text[0]
      second = text[1]?
      if "ntoev".includes?(first) && (second.nil? || second == ' ' || second == '\t' || second == '\\')
        return {first == 'n' || first == 'o', text[1..]}
      end
      if "cdrmFS".includes?(first) && (second == ' ' || second == '\t')
        rest = text[1..].lstrip(" \t")
        word, after = split_word(rest)
        name = interpolate(word, true)
        result = case first
                 when 'c' then true
                 when 'd' then @macros.has_key?(name) || !!@package.try(&.handles?(name))
                 when 'r' then @registers.has_key?(name) || !builtin_register(name).nil?
                 when 'm' then !Colors[name]?.nil?
                 else          true
                 end
        return {result, after}
      end
      if !first.ascii_number? && !"+-(|\\.".includes?(first) && !first.ascii_letter?
        return string_condition(text, first)
      end
      expression, rest = split_expression(text)
      value = Numeric.eval(interpolate(expression, true), 'u') || 0_i64
      {value > 0, rest}
    end

    private def string_condition(text : String, delim : Char) : {Bool, String}
      parts = [] of String
      pos = 1
      start = 1
      bytes = text.to_slice
      delim_byte = delim.ord
      while pos < bytes.size && parts.size < 2
        if bytes[pos] == '\\'.ord
          pos += 2
          next
        end
        if delim.ascii? && bytes[pos] == delim_byte
          parts << text.byte_slice(start, pos - start)
          start = pos + 1
        end
        pos += 1
      end
      return {false, ""} if parts.size < 2
      rest = text.byte_slice(Math.min(pos, bytes.size), bytes.size - Math.min(pos, bytes.size))
      {plain_text(interpolate(parts[0], false)) == plain_text(interpolate(parts[1], false)), rest}
    end

    private def split_word(text : String) : {String, String}
      index = text.index(/[ \t]/) || text.size
      {text[0, index], text[index..]}
    end

    # The expression of a numeric condition ends at a blank or `\{`.
    private def split_expression(text : String) : {String, String}
      bytes = text.to_slice
      pos = 0
      while pos < bytes.size
        byte = bytes[pos]
        break if byte == ' '.ord || byte == '\t'.ord
        if byte == '\\'.ord && pos + 1 < bytes.size
          case bytes[pos + 1]
          when '{'.ord then break
          when 'w'.ord, 'B'.ord, 'A'.ord, 'R'.ord
            delim = bytes[pos + 2]?
            pos += 3
            while pos < bytes.size && bytes[pos] != delim
              pos += 1
            end
            pos += 1
            next
          else
            pos += 2
            next
          end
        end
        pos += 1
      end
      {text.byte_slice(0, pos), text.byte_slice(pos, bytes.size - pos)}
    end

    # Runs or skips a conditional body (single line or `\{ ... \}` block).
    def conditional_body(result : Bool, body : String) : Nil
      depth = brace_depth(body)
      if result
        content = body.starts_with?("\\{") ? body[2..].lstrip(" \t") : body
        process(content) unless content.empty?
      elsif depth > 0
        floor = @frames.size - 1
        while depth > 0 && (line = next_line(floor))
          depth += brace_depth(line)
        end
      end
    end

    private def brace_depth(text : String) : Int32
      return 0 unless text.includes?('\\')
      depth = 0
      bytes = text.to_slice
      pos = 0
      while pos < bytes.size - 1
        if bytes[pos] == '\\'.ord
          case bytes[pos + 1]
          when '{'.ord then depth += 1
          when '}'.ord then depth -= 1
          end
          pos += 2
        else
          pos += 1
        end
      end
      depth
    end

    # `.ie`: remembers the result for `.el`.
    def if_else(raw : String) : Nil
      result, body = condition(raw)
      @conditions << result
      conditional_body(result, body)
    end

    # `.el`: runs when the matching `.ie` failed.
    def else_branch(raw : String) : Nil
      previous = @conditions.pop?
      conditional_body(previous == false, raw.lstrip(" \t"))
    end

    # `.while`, at most `MAX_LOOP` iterations.
    def while_loop(raw : String) : Nil
      text = raw.lstrip(" \t")
      result, body = condition(text)
      lines = [] of String
      if body.starts_with?("\\{")
        lines << body[2..].lstrip(" \t")
        depth = brace_depth(body)
        floor = @frames.size - 1
        while depth > 0 && (line = next_line(floor))
          depth += brace_depth(line)
          lines << line
        end
      else
        lines << body
      end
      lines.reject!(&.empty?)
      count = 0
      while result && count < MAX_LOOP && !@halted
        frame = Frame.new(Frame::Kind::While, lines, "while", current_args)
        run_frame(frame)
        break if frame.broken?
        count += 1
        result, _ = condition(text)
      end
    end

    # `.break` (*break_out*) and `.continue`.
    def leave_loop(break_out : Bool) : Nil
      @frames.reverse_each do |frame|
        frame.finish
        if frame.kind.while?
          frame.broken = break_out
          return
        end
      end
    end

    # `.return`.
    def return_from_macro : Nil
      @frames.reverse_each do |frame|
        frame.finish
        break if frame.kind.macro?
      end
    end

    # `.shift`: drops the first *count* macro arguments.
    def shift_args(count : Int32) : Nil
      macro_frame.try { |frame| frame.args = frame.args[Math.min(count, frame.args.size)..] }
    end

    # `.ex`, `.ab`.
    def halt : Nil
      @halted = true
    end

    # `.nx`: continues with *name* after the current file.
    def next_file(name : String) : Nil
      @next_file = name
      @frames.each &.finish
    end

    # --- definitions ---------------------------------------------------------

    # Reads a macro body up to *terminator* in copy mode.
    def read_body(terminator : String) : Array(String)
      body = [] of String
      floor = @frames.size - 1
      while line = next_line(floor)
        if terminator?(line, terminator)
          unless terminator == "."
            call_name(terminator, "")
          end
          break
        end
        body << interpolate(line, true, braces: true)
      end
      body
    end

    private def terminator?(line : String, terminator : String) : Bool
      return false if line.empty?
      return false unless line[0] == @cc || line[0] == @c2
      rest = line[1..].lstrip(" \t")
      if terminator == "."
        rest.starts_with?('.') && rest[1..].strip.empty? || rest == "." || rest.starts_with?(". ")
      else
        name, _ = split_name(rest)
        name == terminator
      end
    end

    # Skips input up to *terminator* (`.ig`).
    def skip_until(terminator : String) : Nil
      floor = @frames.size - 1
      while line = next_line(floor)
        break if terminator?(line, terminator)
      end
    end

    def macro_body(name : String) : Array(String)?
      @macros[name]?
    end

    def set_macro(name : String, body : Array(String)) : Nil
      @macros[name] = body
    end

    def remove_macro(name : String) : Nil
      @macros.delete(name)
    end

    def rename_macro(from : String, to : String) : Nil
      @macros.delete(from).try { |body| @macros[to] = body }
    end

    # A multi-line macro joins its lines.
    def string(name : String) : String?
      @macros[name]?.try { |body| body.size == 1 ? body[0] : body.join('\n') }
    end

    def set_string(name : String, value : String) : Nil
      @macros[name] = [value]
    end

    # --- characters and fonts ------------------------------------------------

    def control_char=(char : Char) : Char
      @cc = char
    end

    def no_break_char=(char : Char) : Char
      @c2 = char
    end

    # `.ec`; `nil` restores the backslash.
    def escape_char(char : Char?) : Nil
      @escapes = true
      @ec = char || '\\'
    end

    def escapes_off : Nil
      @escapes = false
    end

    def save_escape : Nil
      @saved_ec = @ec
    end

    def restore_escape : Nil
      @ec = @saved_ec
      @escapes = true
    end

    getter translations : Hash(Char, String)
    getter glyphs : Hash(String, String)

    # Resolves a font name or position through `.fp` and `.ftr`.
    def font_named(name : String) : Font?
      name = @font_positions[name]? || name
      name = @font_aliases[name]? || name
      return nil if name.empty?
      Font.from_name(name)
    end

    def font_position(position : String, name : String) : Nil
      @font_positions[position] = name
    end

    def font_alias(from : String, to : String) : Nil
      @font_aliases[from] = to
    end

    # Sets the font from a name; `P` (or empty) restores the previous one.
    def select_font(name : String) : Nil
      if name.empty? || name == "P"
        @env.previous_font
      elsif font = font_named(name)
        @env.font = font
      end
    end

    # --- environments --------------------------------------------------------

    # `.ev name`.
    def push_env(name : String) : Nil
      @env_stack << @env
      self.env = @envs[name] ||= begin
        env = Env.new
        env.line_length = @columns
        env.title_length = @columns
        env
      end
    end

    # `.ev` without a name.
    def pop_env : Nil
      @env_stack.pop?.try { |env| self.env = env }
    end

    # `.evc name`.
    def copy_env(name : String) : Nil
      @envs[name]?.try { |source| self.env = source.copy }
    end

    # --- traps and diversions ------------------------------------------------

    def input_trap(lines : Int32, handler : String?, continued : Bool) : Nil
      @input_trap = lines
      @input_trap_macro = handler
      @input_trap_continued = continued
    end

    property end_macro : String?
    property blank_macro : String?
    property space_macro : String?

    # `.di`/`.da`/`.box`/`.boxa`; a `nil` *name* ends the innermost diversion.
    def diversion(name : String?, append : Bool) : Nil
      if name
        lines = append ? (@macros[name]? || [] of String) : [] of String
        @diversions << {name, lines}
      else
        close_diversion
      end
    end

    private def divert(line : String) : Bool
      if line.starts_with?(@cc) || line.starts_with?(@c2)
        name, _ = split_name(line[1..].lstrip(" \t"))
        return false if {"di", "da", "box", "boxa"}.includes?(name)
      end
      @diversions.last[1] << line
      true
    end

    private def close_diversion : Nil
      name, lines = @diversions.pop? || return
      @macros[name] = lines
      @registers.set("dn", lines.size.to_i64 * Numeric::LINE)
      width = lines.max_of? { |line| Unicode.text_width(line) } || 0
      @registers.set("dl", width.to_i64 * Numeric::COLUMN)
    end

    private def close_diversions : Nil
      until @diversions.empty?
        close_diversion
      end
    end

    # --- registers -----------------------------------------------------------

    # Read-only and computed registers; `nil` when *name* is not built in.
    def builtin_register(name : String) : Int64?
      now = Time.local
      case name
      when ".$"                          then current_args.size.to_i64
      when ".l"                          then @env.line_length.to_i64 * Numeric::COLUMN
      when ".lt"                         then @env.title_length.to_i64 * Numeric::COLUMN
      when ".i"                          then @env.indent.to_i64 * Numeric::COLUMN
      when ".in"                         then (@env.temp_indent || @env.indent).to_i64 * Numeric::COLUMN
      when ".u"                          then @env.fill? ? 1_i64 : 0_i64
      when ".j"                          then @env.adjust.value.to_i64
      when ".f"                          then @env.font.value.to_i64 + 1
      when ".ce"                         then @env.center.to_i64
      when ".s", ".ps"                   then 10_i64
      when ".v"                          then Numeric::LINE.to_i64
      when ".H"                          then Numeric::COLUMN.to_i64
      when ".V"                          then Numeric::LINE.to_i64
      when ".A", ".T", ".g", ".P", ".nH" then 1_i64
      when ".C", ".cp", ".o", ".k", ".n", ".z", ".d", ".h", ".w", ".x0", ".ne", ".br", ".pe", ".ns", ".hy"
        name == ".ns" ? (@builder.no_space? ? 1_i64 : 0_i64) : 0_i64
      when ".x"       then 1_i64
      when ".y"       then 23_i64
      when ".Y"       then 0_i64
      when ".p"       then 1_000_000_i64
      when ".t", ".R" then 1_000_000_i64
      when ".c", "c." then @frames.last?.try(&.pos.to_i64) || 0_i64
      when "%"        then 1_i64
      when ".pn"      then 1_i64
      when "$$"       then Process.pid.to_i64
      when "dw"       then now.day_of_week.value.to_i64 % 7 + 1
      when "dy"       then now.day.to_i64
      when "mo"       then now.month.to_i64
      when "yr"       then now.year.to_i64 - 1900
      when "year"     then now.year.to_i64
      when "hours"    then now.hour.to_i64
      when "minutes"  then now.minute.to_i64
      when "seconds"  then now.second.to_i64
      when ".tabs"    then 0_i64
      end
    end

    # `\n`: a nonzero *sign* auto-increments (`\n+x`); an unknown register is set to 0.
    def register_text(name : String, sign : Int32 = 0) : String
      if register = @registers[name]?
        value = sign == 0 ? register.value : @registers.step(name, sign)
        return Registers.render(value, register.format)
      end
      if value = builtin_register(name)
        return value.to_s
      end
      @registers.set(name, 0_i64)
      "0"
    end

    # 0 when undefined.
    def register_value(name : String) : Int64
      @registers[name]?.try(&.value) || builtin_register(name) || 0_i64
    end

    private def predefine : Nil
      set_string(".T", "utf8")
      set_string(".m", "")
      set_string(".M", "")
      set_string(".fam", "T")
      set_string(".fn", "R")
      set_string(".ev", "0")
      set_string("R", "®")
      set_string("Tm", "™")
      set_string("lq", "“")
      set_string("rq", "”")
      set_string("S", "")
      set_string("HF", "B")
      @registers.set("PD", 1_i64)
      @registers.set("IN", 7_i64 * Numeric::COLUMN)
      @registers.set("LL", @columns.to_i64 * Numeric::COLUMN)
      @registers.set("cR", 0_i64)
      @registers.set("C", 0_i64)
      @registers.set("D", 0_i64)
      @registers.set("U", 0_i64)
      @registers.set("X", 0_i64)
    end
  end
end
