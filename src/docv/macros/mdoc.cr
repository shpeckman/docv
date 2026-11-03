# src/docv/macros/mdoc.cr
require "./mdoc_data"

module Docv::Macros
  # The mdoc(7) semantic macro package, implemented natively on the roff
  # engine.
  class Mdoc < Roff::Package
    include MdocData

    # An argument of a macro line; quoted arguments are never macro names
    # or delimiters.
    record Token, text : String, quoted : Bool

    # An open `.Bl` list.
    class List
      property type : String
      property width : Int32
      property offset : Int32
      property? compact : Bool
      property saved_indent : Int32
      property base : Int32
      property items : Int32 = 0
      property table : Table? = nil
      property columns : Array(Int32) = [] of Int32

      def initialize(@type, @width, @offset, @compact, @saved_indent, @base)
      end
    end

    # An open `.Bd` display.
    record Display, indent : Int32, fill : Bool, center : Int32

    @name : String? = nil
    @section = ""
    @lists = [] of List
    @displays = [] of Display
    @spacing = true
    @no_space = false
    @in_function = false
    @function_args = 0
    @synopsis_function = false
    @synopsis_names = 0
    @references : Hash(String, Array(String))? = nil
    @authors_split : Bool? = nil
    @authors = 0
    @extending_head = false
    @head_list : List? = nil
    @base_font = Roff::Font::Regular
    @enclosure = {"", ""}
    @line_start = true
    @keep = 0
    @keep_block = false

    def handles?(name : String) : Bool
      MACROS.includes?(name)
    end

    def format : Format
      Format::Mdoc
    end

    def call(name : String, line : String) : Nil
      tokens = tokenize(line)
      @line_start = true
      case name
      when "Dd" then @engine.doc.date = plain_join(tokens)
      when "Dt" then title(tokens)
      when "Os" then @engine.doc.source = plain_join(tokens)
      when "Sh" then section(tokens, 1)
      when "Ss" then section(tokens, 2)
      when "Pp", "Lp"
        @engine.builder.blank(1)
      when "Nd"
        put("—", Roff::Font::Regular, :word)
        line_macro(tokens, 0)
      when "Bl" then begin_list(tokens)
      when "El" then end_list
      when "It" then item(tokens)
      when "Bd" then begin_display(tokens)
      when "Ed" then end_display
      when "D1", "Dl"
        one_line_display(tokens, literal: name == "Dl")
      when "Bf"
        @base_font = case tokens.first?.try(&.text)
                     when "-emphasis", "Em" then Roff::Font::Italic
                     when "-symbolic", "Sy" then Roff::Font::Bold
                     else                        Roff::Font::Regular
                     end
        @engine.env.font = @base_font
      when "Ef"
        @base_font = Roff::Font::Regular
        @engine.env.font = @base_font
      when "Bk"
        @keep_block = true
      when "Ek"
        @keep_block = false
      when "Hf", "Db", "Tg"
      when "Rs"
        @references = Hash(String, Array(String)).new
      when "Re"
        end_reference
      when "Sm"
        mode = tokens.first?.try(&.text)
        @spacing = mode.nil? ? !@spacing : mode == "on"
      when "Xc"
        finish_head if @extending_head
      else
        if name.starts_with?('%') && (references = @references)
          (references[name] ||= [] of String) << plain_join(tokens)
          return
        end
        synopsis_break_before(name, tokens)
        @engine.builder.no_word_space if name == "Ns" || name == "Ap"
        index = inline(name, tokens, 0, tokens.size)
        parse_range(tokens, index, tokens.size)
        synopsis_break_after(name)
        line_done
      end
    end

    # --- tokens and words ----------------------------------------------------

    private def tokenize(line : String) : Array(Token)
      tokens = [] of Token
      reader = Roff::Cursor.new(line)
      column = @lists.last?.try(&.type) == "column"
      while reader.has_next?
        char = reader.current_char
        if char == '\t' && column
          tokens << Token.new("Ta", false)
          reader.next_char
          next
        end
        if char == ' ' || char == '\t'
          reader.next_char
          next
        end
        if char == '"'
          reader.next_char
          text = String.build do |io|
            while c = reader.take
              if c == '"'
                if reader.has_next? && reader.current_char == '"'
                  io << '"'
                  reader.next_char
                else
                  break
                end
              else
                io << c
              end
            end
          end
          tokens << Token.new(text, true)
        else
          text = String.build do |io|
            while reader.has_next?
              c = reader.current_char
              break if c == ' ' || (c == '\t')
              io << c
              reader.next_char
              if c == '\\' && reader.has_next?
                io << reader.current_char
                reader.next_char
              end
            end
          end
          tokens << Token.new(text, false)
        end
      end
      tokens
    end

    private def delimiter(token : Token) : Symbol
      return :word if token.quoted
      case token.text
      when ".", ",", ":", ";", ")", "]", "?", "!" then :close
      when "(", "["                               then :open
      when "|"                                    then :middle
      else                                             :word
      end
    end

    private def callable?(token : Token) : Bool
      !token.quoted && CALLABLE.includes?(token.text)
    end

    # Sets *text* in *font* with mdoc spacing: closing delimiters attach to
    # the previous word, opening delimiters to the next.
    private def put(text : String, font : Roff::Font, kind : Symbol) : Nil
      builder = @engine.builder
      builder.no_word_space if kind == :close || @no_space || (!@spacing && !@line_start)
      @no_space = false
      @line_start = false
      env = @engine.env
      env.font = font == Roff::Font::Regular ? @base_font : font
      @engine.emit(text)
      env.font = @base_font
      if kind == :open
        @no_space = true
      else
        builder.word_space(hard: @keep > 0 && (@keep_block || @section == "SYNOPSIS"))
      end
    end

    private def line_done : Nil
      @no_space = false
      @engine.text_line_done
    end

    # Parses the tokens of a macro line from *index*: callable macros run,
    # other tokens are words.
    private def parse_range(tokens : Array(Token), index : Int32, stop : Int32) : Nil
      while index < stop
        token = tokens[index]
        if callable?(token)
          index = inline(token.text, tokens, index + 1, stop)
        else
          put(token.text, Roff::Font::Regular, delimiter(token))
          index += 1
        end
      end
    end

    private def line_macro(tokens : Array(Token), index : Int32) : Nil
      parse_range(tokens, index, tokens.size)
      line_done
    end

    # Index of the first callable macro at or after *index*.
    private def args_end(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      while index < stop && !callable?(tokens[index])
        index += 1
      end
      index
    end

    # Index where trailing closing delimiters of *index...stop* begin.
    private def trailing(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      cut = stop
      while cut > index && delimiter(tokens[cut - 1]) == :close
        cut -= 1
      end
      cut
    end

    # --- inline macros -------------------------------------------------------

    # Runs callable macro *name* on *tokens* from *index*; returns the index
    # after its arguments.
    private def inline(name : String, tokens : Array(Token), index : Int32, stop : Int32) : Int32
      if pair = ENCLOSE[name]?
        return enclose(name, pair, tokens, index, stop)
      end
      if open = OPEN[name]?
        put(open, Roff::Font::Regular, :open)
        return index
      end
      if close = CLOSE[name]?
        put(close, Roff::Font::Regular, :close)
        return index
      end
      case name
      when "Ns"
        @no_space = true
        @engine.builder.no_word_space
        index
      when "Ap"
        put("'", Roff::Font::Regular, :close)
        @no_space = true
        index
      when "Pf"
        if token = tokens[index]?
          put(token.text, Roff::Font::Regular, :word)
          @no_space = true
          index + 1
        else
          index
        end
      when "Ta"
        index
      when "Xo"
        index
      when "Xc"
        finish_head if @extending_head
        index
      when "Eo"
        if (token = tokens[index]?) && !callable?(token)
          put(token.text, Roff::Font::Regular, :open)
          index + 1
        else
          index
        end
      when "Ec"
        if (token = tokens[index]?) && !callable?(token)
          put(token.text, Roff::Font::Regular, :close)
          index + 1
        else
          index
        end
      when "Es"
        @enclosure = {tokens[index]?.try(&.text) || "", tokens[index + 1]?.try(&.text) || ""}
        Math.min(index + 2, stop)
      when "En"
        enclose("En", @enclosure, tokens, index, stop)
      when "Xr" then cross_reference(tokens, index, stop)
      when "Fn" then function(tokens, index, stop)
      when "Fo" then function_open(tokens, index, stop)
      when "Fc"
        put(")", Roff::Font::Regular, :close)
        @in_function = false
        if @section == "SYNOPSIS"
          put(";", Roff::Font::Regular, :close)
        end
        index
      when "Fa" then function_args(tokens, index, stop)
      when "Fl" then flags(tokens, index, stop)
      when "Nm" then name_macro(tokens, index, stop)
      when "Lk" then link(tokens, index, stop)
      when "In" then include_macro(tokens, index, stop)
      when "Rv" then return_values(tokens, index, stop)
      when "Ex" then exit_status(tokens, index, stop)
      when "St"
        if token = tokens[index]?
          put(STANDARDS[token.text]? || token.text, Roff::Font::Regular, :word)
          index + 1
        else
          index
        end
      when "Lb"
        if token = tokens[index]?
          put(LIBRARIES[token.text]?.try { |library| "library “#{token.text}” — #{library}" } || "library “#{token.text}”", Roff::Font::Regular, :word)
          index + 1
        else
          index
        end
      when "At"
        version = tokens[index]?
        if version && (text = AT_VERSIONS[version.text]?)
          put(text, Roff::Font::Regular, :word)
          index + 1
        else
          put("AT&T UNIX", Roff::Font::Regular, :word)
          index
        end
      when "Bx"
        bsd(tokens, index, stop)
      when "Bsx", "Fx", "Nx", "Ox", "Dx"
        system(name, tokens, index, stop)
      when "Ux", "Ud", "Bt"
        put(PHRASES[name], Roff::Font::Regular, :word)
        index
      when "An"
        authors(tokens, index, stop)
      else
        font = FONTS[name]? || Roff::Font::Regular
        words(name, font, tokens, index, stop)
      end
    end

    private def words(name : String, font : Roff::Font, tokens : Array(Token), index : Int32, stop : Int32) : Int32
      last = args_end(tokens, index, stop)
      if last == index || tokens[index...last].all? { |token| delimiter(token) != :word }
        case name
        when "Ar" then put("file ...", font, :word)
        when "Pa" then put("~", font, :word)
        end
      end
      (index...last).each do |position|
        token = tokens[position]
        kind = delimiter(token)
        put(token.text, kind == :word ? font : Roff::Font::Regular, kind)
      end
      last
    end

    private def enclose(name : String, pair : {String, String}, tokens : Array(Token), index : Int32, stop : Int32) : Int32
      cut = trailing(tokens, index, stop)
      put(pair[0], Roff::Font::Regular, :open)
      @keep += 1
      if name == "Ql"
        (index...cut).each { |position| put(tokens[position].text, Roff::Font::Regular, :word) }
      else
        parse_range(tokens, index, cut)
      end
      @keep -= 1
      put(pair[1], Roff::Font::Regular, :close)
      (cut...stop).each { |position| put(tokens[position].text, Roff::Font::Regular, :close) }
      stop
    end

    private def cross_reference(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      name = tokens[index]?
      return index unless name && !callable?(name)
      section = tokens[index + 1]?
      if section && !callable?(section) && delimiter(section) == :word
        put(name.text, Roff::Font::Bold, :word)
        @no_space = true
        put("(#{section.text})", Roff::Font::Regular, :word)
        index + 2
      else
        put(name.text, Roff::Font::Bold, :word)
        index + 1
      end
    end

    private def function(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      name = tokens[index]?
      return index unless name
      put(name.text, Roff::Font::Bold, :word)
      put("(", Roff::Font::Regular, :open)
      last = trailing(tokens, index + 1, args_end(tokens, index + 1, stop))
      (index + 1...last).each_with_index do |position, count|
        put(",", Roff::Font::Regular, :close) if count > 0
        put(tokens[position].text, Roff::Font::Italic, :word)
      end
      put(")", Roff::Font::Regular, :close)
      put(";", Roff::Font::Regular, :close) if @section == "SYNOPSIS"
      last
    end

    private def function_open(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      name = tokens[index]?
      return index unless name
      put(name.text, Roff::Font::Bold, :word)
      put("(", Roff::Font::Regular, :open)
      @in_function = true
      @function_args = 0
      index + 1
    end

    private def function_args(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      last = args_end(tokens, index, stop)
      (index...last).each do |position|
        token = tokens[position]
        kind = delimiter(token)
        if kind == :word
          if @in_function
            put(",", Roff::Font::Regular, :close) if @function_args > 0
            @function_args += 1
          end
          put(token.text, Roff::Font::Italic, :word)
        else
          put(token.text, Roff::Font::Regular, kind)
        end
      end
      last
    end

    private def flags(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      last = args_end(tokens, index, stop)
      words_present = (index...last).any? { |position| delimiter(tokens[position]) == :word }
      put("-", Roff::Font::Bold, :word) unless words_present
      (index...last).each do |position|
        token = tokens[position]
        kind = delimiter(token)
        if kind == :word
          put("-#{token.text}", Roff::Font::Bold, :word)
        else
          put(token.text, Roff::Font::Regular, kind)
        end
      end
      last
    end

    private def name_macro(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      last = args_end(tokens, index, stop)
      given = (index...last).find { |position| delimiter(tokens[position]) == :word }
      if given
        @name ||= tokens[given].text
      end
      put(@name || "", Roff::Font::Bold, :word) unless given
      (index...last).each do |position|
        token = tokens[position]
        kind = delimiter(token)
        put(token.text, kind == :word ? Roff::Font::Bold : Roff::Font::Regular, kind)
      end
      last
    end

    private def link(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      url = tokens[index]?
      return index unless url
      cut = trailing(tokens, index + 1, args_end(tokens, index + 1, stop))
      if cut > index + 1
        (index + 1...cut).each { |position| put(tokens[position].text, Roff::Font::Regular, :word) }
        put(":", Roff::Font::Regular, :close)
      end
      put(url.text, Roff::Font::Italic, :word)
      cut
    end

    private def include_macro(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      file = tokens[index]?
      return index unless file
      if @section == "SYNOPSIS"
        put("#include", Roff::Font::Bold, :word)
        put("<#{file.text}>", Roff::Font::Bold, :word)
      else
        put("⟨", Roff::Font::Regular, :open)
        put(file.text, Roff::Font::Italic, :word)
        put("⟩", Roff::Font::Regular, :close)
      end
      index + 1
    end

    private def return_values(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      last = args_end(tokens, index, stop)
      names = (index...last).map { |position| tokens[position].text }.reject(&.starts_with?('-'))
      names = [@name || ""] if names.empty?
      functions = names.map { |name| "\\fB#{name}\\fR()" }
      subject = functions.size == 1 ? "The #{functions[0]} function returns" : "The #{functions[0...-1].join(", ")} and #{functions[-1]} functions return"
      put("#{subject} the value 0 if successful; otherwise the value -1 is returned and the global variable \\fIerrno\\fR is set to indicate the error.", Roff::Font::Regular, :word)
      last
    end

    private def exit_status(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      last = args_end(tokens, index, stop)
      names = (index...last).map { |position| tokens[position].text }.reject(&.starts_with?('-'))
      names = [@name || ""] if names.empty?
      utilities = names.map { |name| "\\fB#{name}\\fR" }
      subject = utilities.size == 1 ? "The #{utilities[0]} utility exits" : "The #{utilities[0...-1].join(", ")} and #{utilities[-1]} utilities exit"
      put("#{subject} 0 on success, and >0 if an error occurs.", Roff::Font::Regular, :word)
      last
    end

    private def bsd(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      version = tokens[index]?
      if version.nil? || callable?(version) || delimiter(version) != :word
        put("BSD", Roff::Font::Regular, :word)
        return index
      end
      variant = tokens[index + 1]?
      if variant && !callable?(variant) && delimiter(variant) == :word
        put("#{version.text}BSD-#{variant.text}", Roff::Font::Regular, :word)
        index + 2
      else
        put("#{version.text}BSD", Roff::Font::Regular, :word)
        index + 1
      end
    end

    private def system(name : String, tokens : Array(Token), index : Int32, stop : Int32) : Int32
      version = tokens[index]?
      if version && !callable?(version) && delimiter(version) == :word
        put("#{SYSTEMS[name]} #{version.text}", Roff::Font::Regular, :word)
        index + 1
      else
        put(SYSTEMS[name], Roff::Font::Regular, :word)
        index
      end
    end

    private def authors(tokens : Array(Token), index : Int32, stop : Int32) : Int32
      first = tokens[index]?
      if first && (first.text == "-split" || first.text == "-nosplit")
        @authors_split = first.text == "-split"
        return index + 1
      end
      if @section == "AUTHORS"
        @engine.builder.break_line if @authors > 0 && @authors_split != false
        @authors += 1
      end
      words("An", Roff::Font::Regular, tokens, index, stop)
    end

    # --- synopsis ------------------------------------------------------------

    private def synopsis_break_before(name : String, tokens : Array(Token)) : Nil
      return unless @section == "SYNOPSIS"
      builder = @engine.builder
      case name
      when "Nm"
        return if @lists.any?
        builder.blank(1) if @synopsis_function
        builder.break_line
        @synopsis_function = false
        @synopsis_names += 1
        given = tokens.first?.try { |token| delimiter(token) == :word && !callable?(token) ? token.text : nil }
        hang = Unicode.text_width(plain(given || @name || "")) + 1
        @engine.env.indent = INDENT + hang
        builder.hang(-hang)
      when "Ft", "Ot"
        builder.blank(1) if @synopsis_function
        builder.break_line
        @engine.env.indent = INDENT
      when "Fd", "In", "Cd", "Vt"
        builder.break_line
      when "Fn", "Fo"
        builder.break_line unless @synopsis_after_type
      end
    end

    @synopsis_after_type = false

    private def synopsis_break_after(name : String) : Nil
      @synopsis_after_type = false
      return unless @section == "SYNOPSIS"
      builder = @engine.builder
      case name
      when "Ft", "Ot"
        @synopsis_after_type = true
      when "Fn", "Fc"
        builder.break_line
        @synopsis_function = true
        @engine.env.indent = INDENT
      when "Fd", "In", "Cd"
        builder.break_line
      end
    end

    # --- structure -----------------------------------------------------------

    private def title(tokens : Array(Token)) : Nil
      doc = @engine.doc
      doc.title = tokens[0]?.try { |token| plain(token.text) } || ""
      doc.section = tokens[1]?.try { |token| plain(token.text) } || ""
      volume = tokens[2]?.try(&.text)
      if volume && !VOLUMES.has_key?(volume) && volume.size > 3
        doc.manual = volume
      else
        doc.manual = VOLUMES[doc.section[0]?.to_s]? || ""
        doc.arch = volume || ""
      end
    end

    private def section(tokens : Array(Token), level : Int32) : Nil
      builder = @engine.builder
      env = @engine.env
      close_blocks
      builder.blank(1)
      env.font = Roff::Font::Bold
      spans = builder.capture { parse_range(tokens, 0, tokens.size) }
      env.font = Roff::Font::Regular
      @base_font = Roff::Font::Regular
      text = spans.join(&.text)
      @section = text if level == 1
      builder.heading(level, spans, level == 1 ? 0 : SUB_INDENT)
      builder.no_space = true
      env.indent = INDENT
      env.fill = true
      @synopsis_function = false
      @synopsis_names = 0
      @authors = 0
    end

    private def close_blocks : Nil
      until @lists.empty?
        end_list
      end
      until @displays.empty?
        end_display
      end
    end

    private def measure(text : String, fallback : Int32) : Int32
      case text
      when "indent", "Ds" then DISPLAY
      when "indent-two"   then DISPLAY * 2
      when "left"         then 0
      when "right", "center"
        DISPLAY * 2
      else
        if text.matches?(/\A-?\d+(\.\d+)?[uinmcpPvMsz]\z/) || text.matches?(/\A\d{1,3}\z/)
          Roff::Numeric.columns(text, 'n') || fallback
        elsif CALLABLE.includes?(text)
          fallback
        else
          Unicode.text_width(plain(text)) + 2
        end
      end
    end

    private def begin_list(tokens : Array(Token)) : Nil
      builder = @engine.builder
      env = @engine.env
      type = "item"
      width : Int32? = nil
      offset = 0
      compact = false
      columns = [] of Int32
      index = 0
      while index < tokens.size
        text = tokens[index].text
        case text
        when "-bullet", "-dash", "-hyphen", "-enum", "-item", "-tag", "-diag", "-hang", "-ohang", "-inset", "-column"
          type = text[1..]
          type = "dash" if type == "hyphen"
        when "-width"
          index += 1
          width = tokens[index]?.try { |token| measure(token.text, 8) }
        when "-offset"
          index += 1
          offset = tokens[index]?.try { |token| measure(token.text, DISPLAY) } || DISPLAY
        when "-compact"
          compact = true
        else
          columns << measure(text, 8) if type == "column"
        end
        index += 1
      end
      width ||= case type
                when "tag", "hang"    then 8
                when "bullet", "dash" then 4
                when "enum"           then 4
                else                       0
                end
      builder.break_line
      builder.blank(1) unless compact || @lists.any?(&.compact?)
      list = List.new(type, width, offset, compact, env.indent, env.indent + offset)
      if type == "column"
        table = Table.new
        table.columns = columns.size
        table.min_widths = columns
        table.vrules = Array.new(columns.size + 1, 0)
        table.gaps = Array.new(columns.size, 0)
        list.table = table
        list.columns = columns
      end
      @lists << list
    end

    private def end_list : Nil
      finish_head if @extending_head
      list = @lists.pop? || return
      builder = @engine.builder
      builder.break_line
      if table = list.table
        table.columns = table.rows.max_of? { |row| row.cells.size } || table.columns
        table.min_widths = list.columns + Array.new(Math.max(table.columns - list.columns.size, 0), 0)
        table.vrules = Array.new(table.columns + 1, 0)
        table.gaps = Array.new(table.columns, 0)
        builder.table(table, list.base)
      end
      @engine.env.indent = list.saved_indent
    end

    private def item(tokens : Array(Token)) : Nil
      list = @lists.last? || return
      builder = @engine.builder
      env = @engine.env
      finish_head if @extending_head
      builder.break_line
      builder.blank(1) unless list.compact? || list.items == 0 && list.type != "column"
      list.items += 1
      case list.type
      when "column"
        column_row(list, tokens)
      when "bullet", "dash", "enum"
        mark = case list.type
               when "bullet" then "•"
               when "dash"   then "-"
               else               "#{list.items}."
               end
        env.indent = list.base + list.width
        builder.tag([Span.new(mark)], list.base)
      when "item"
        env.indent = list.base
      when "inset", "diag"
        env.indent = list.base
        font = list.type == "diag" ? Roff::Font::Bold : Roff::Font::Regular
        tokens.each do |token|
          next if callable?(token)
          put(token.text, font, delimiter(token))
        end
        builder.word_space
      else
        env.indent = list.base + (list.type == "ohang" ? 0 : list.width)
        extend_head = !tokens.empty? && tokens.last.text == "Xo" && !tokens.last.quoted
        builder.begin_capture
        parse_range(tokens, 0, extend_head ? tokens.size - 1 : tokens.size)
        if extend_head
          @extending_head = true
          @head_list = list
        else
          finish_head(list)
        end
      end
    end

    private def finish_head(list : List? = @head_list) : Nil
      @extending_head = false
      @head_list = nil
      spans = @engine.builder.end_capture
      @no_space = false
      return unless list
      @engine.builder.tag(spans, list.base)
    end

    private def column_row(list : List, tokens : Array(Token)) : Nil
      table = list.table || return
      builder = @engine.builder
      cells = [] of Table::Cell
      start = 0
      (0..tokens.size).each do |position|
        if position == tokens.size || (tokens[position].text == "Ta" && !tokens[position].quoted)
          spans = builder.capture { parse_range(tokens, start, position) }
          @no_space = false
          cells << Table::Cell.new(Table::CellKind::Text, Table::CellAlign::Left, spans)
          start = position + 1
        end
      end
      table.rows << Table::Row.new(Table::RowKind::Data, cells)
    end

    private def begin_display(tokens : Array(Token)) : Nil
      builder = @engine.builder
      env = @engine.env
      type = "filled"
      offset = 0
      compact = false
      index = 0
      while index < tokens.size
        text = tokens[index].text
        case text
        when "-literal", "-unfilled", "-filled", "-ragged", "-centered"
          type = text[1..]
        when "-offset"
          index += 1
          offset = tokens[index]?.try { |token| measure(token.text, DISPLAY) } || DISPLAY
        when "-compact"
          compact = true
        end
        index += 1
      end
      builder.break_line
      builder.blank(1) unless compact
      @displays << Display.new(env.indent, env.fill?, env.center)
      env.indent += offset
      env.fill = !(type == "literal" || type == "unfilled")
      env.center = Int32::MAX if type == "centered"
    end

    private def end_display : Nil
      display = @displays.pop? || return
      builder = @engine.builder
      env = @engine.env
      builder.break_line
      env.indent = display.indent
      env.fill = display.fill
      env.center = display.center
    end

    private def one_line_display(tokens : Array(Token), literal : Bool) : Nil
      builder = @engine.builder
      env = @engine.env
      builder.break_line
      saved = env.indent
      env.indent += DISPLAY
      parse_range(tokens, 0, tokens.size)
      builder.break_line
      @no_space = false
      env.indent = saved
    end

    private def end_reference : Nil
      references = @references || return
      @references = nil
      parts = [] of String
      REFERENCE_ORDER.each do |field|
        values = references[field]? || next
        case field
        when "%A"
          parts << (values.size > 1 ? "#{values[0...-1].join(", ")} and #{values[-1]}" : values[0])
        when "%T"
          parts << "“#{values.join(' ')}”"
        when "%B", "%J"
          parts << "\\fI#{values.join(' ')}\\fR"
        else
          parts << values.join(' ')
        end
      end
      return if parts.empty?
      @engine.builder.break_line if @section == "SEE ALSO" || @section == "STANDARDS"
      @engine.emit(parts.join(", ") + ".")
      line_done
    end

    private def plain_join(tokens : Array(Token)) : String
      tokens.map { |token| plain(token.text) }.join(' ')
    end

    private def plain(text : String) : String
      @engine.plain_text(text)
    end
  end
end
