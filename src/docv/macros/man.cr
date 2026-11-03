# src/docv/macros/man.cr
module Docv::Macros
  # The man(7) macro package (groff an.tmac and an-ext.tmac), implemented
  # natively on the roff engine.
  class Man < Roff::Package
    # Default indents in columns: body (`IN`) and subsection headings (`SN`).
    IN = 7
    SN = 3

    MACROS = Set{
      "TH", "SH", "SS", "PP", "LP", "P", "TP", "TQ", "IP", "HP", "RS", "RE", "B", "I", "SM", "SB",
      "BI", "BR", "IB", "IR", "RB", "RI", "EX", "EE", "UR", "UE", "MT", "ME", "SY", "YS", "OP", "MR",
      "PD", "DT", "AT", "UC", "IX",
    }

    # Fonts of the alternating-font macros.
    ALTERNATING = {
      "BI" => {Roff::Font::Bold, Roff::Font::Italic}, "BR" => {Roff::Font::Bold, Roff::Font::Regular},
      "IB" => {Roff::Font::Italic, Roff::Font::Bold}, "IR" => {Roff::Font::Italic, Roff::Font::Regular},
      "RB" => {Roff::Font::Regular, Roff::Font::Bold}, "RI" => {Roff::Font::Regular, Roff::Font::Italic},
    }

    # Fonts of the one-line font macros.
    ONE_FONT = {
      "B" => Roff::Font::Bold, "I" => Roff::Font::Italic, "SB" => Roff::Font::Bold, "SM" => Roff::Font::Regular,
    }

    AT_SOURCES = {"3" => "7th Edition", "4" => "System III", "5" => "System V"}
    UC_SOURCES = {"3" => "3rd Berkeley Distribution", "4" => "4th Berkeley Distribution",
                  "5" => "4.2 Berkeley Distribution", "6" => "4.3 Berkeley Distribution",
                  "7" => "4.4 Berkeley Distribution"}

    @margin = IN
    @prevailing = IN
    @distance = 1
    @levels = [] of {Int32, Int32}
    @link : String? = nil

    def handles?(name : String) : Bool
      MACROS.includes?(name)
    end

    def format : Format
      Format::Man
    end

    def call(name : String, line : String) : Nil
      builder = @engine.builder
      env = @engine.env
      case name
      when "TH"
        header(@engine.split_args(line))
      when "SH", "SS"
        heading(name == "SH" ? 1 : 2, line)
      when "PP", "LP", "P"
        paragraph
        env.indent = @margin
      when "TP", "TQ"
        name == "TP" ? paragraph : builder.break_line
        width(@engine.split_args(line).first?)
        env.indent = @margin + @prevailing
        margin = @margin
        @engine.capture_next_line { |spans| @engine.builder.tag(spans, margin) }
      when "IP"
        args = @engine.split_args(line)
        paragraph
        width(args[1]?)
        env.indent = @margin + @prevailing
        if (tag = args[0]?) && !tag.empty?
          spans = builder.capture { @engine.emit(tag) }
          builder.tag(spans, @margin)
        end
      when "HP"
        paragraph
        width(@engine.split_args(line).first?)
        env.indent = @margin + @prevailing
        builder.hang(-@prevailing)
      when "RS"
        builder.break_line
        @levels << {@margin, @prevailing}
        shift = @engine.split_args(line).first?.try { |text| Roff::Numeric.columns(text, 'n') } || @prevailing
        @margin += shift
        @prevailing = IN
        env.indent = @margin
      when "RE"
        builder.break_line
        level = @engine.split_args(line).first?.try(&.to_i?)
        target = level ? Math.max(level - 1, 0) : @levels.size - 1
        while @levels.size > target && (saved = @levels.pop?)
          @margin, @prevailing = saved
        end
        env.indent = @margin
      when "B", "I", "SB", "SM"
        one_font(ONE_FONT[name], line)
      when "BI", "BR", "IB", "IR", "RB", "RI"
        alternate(ALTERNATING[name], @engine.split_args(line))
      when "EX"
        builder.break_line
        env.fill = false
      when "EE"
        builder.break_line
        env.fill = true
      when "UR", "MT"
        @link = @engine.split_args(line).first?
      when "UE", "ME"
        if link = @link
          @engine.emit("\\[la]#{link}\\[ra]#{@engine.split_args(line).first?}")
          @engine.text_line_done
        end
        @link = nil
      when "SY"
        synopsis(@engine.split_args(line).first? || "")
      when "YS"
        builder.break_line
        env.indent = @margin
      when "OP"
        args = @engine.split_args(line)
        option = "[\\fB#{args[0]? || ""}\\fR"
        option += " \\fI#{args[1]}\\fR" if args[1]?
        @engine.emit(option + "]")
        @engine.text_line_done
      when "MR"
        args = @engine.split_args(line)
        @engine.emit("\\fI#{args[0]? || ""}\\fR(#{args[1]? || ""})#{args[2]?}")
        @engine.text_line_done
      when "PD"
        @distance = @engine.split_args(line).first?.try { |text| Roff::Numeric.lines(text) } || 1
      when "DT"
        env.tabs = Tabs::DEFAULT
      when "AT"
        @engine.doc.source = AT_SOURCES[@engine.split_args(line).first? || "3"]? || "7th Edition" if @engine.doc.source.empty?
      when "UC"
        @engine.doc.source = UC_SOURCES[@engine.split_args(line).first? || "3"]? || "3rd Berkeley Distribution" if @engine.doc.source.empty?
      when "IX"
      end
    end

    private def header(args : Array(String)) : Nil
      doc = @engine.doc
      doc.title = plain(args[0]? || "")
      doc.section = plain(args[1]? || "")
      doc.date = plain(args[2]? || "")
      doc.source = plain(args[3]? || "")
      doc.manual = plain(args[4]? || "")
      doc.manual = MdocData::VOLUMES[doc.section[0]?.to_s]? || "" if doc.manual.empty?
      @margin = IN
      @prevailing = IN
      @levels.clear
      @engine.env.indent = @margin
    end

    private def heading(level : Int32, line : String) : Nil
      builder = @engine.builder
      env = @engine.env
      builder.blank(1)
      @levels.clear
      @margin = IN
      @prevailing = IN
      env.fill = true
      env.center = 0
      env.indent = @margin
      indent = level == 1 ? 0 : SN
      args = @engine.split_args(line)
      env.font = Roff::Font::Bold
      if args.empty?
        @engine.capture_next_line do |spans|
          @engine.env.font = Roff::Font::Regular
          @engine.builder.heading(level, spans, indent)
          @engine.builder.no_space = true
        end
      else
        spans = builder.capture { @engine.emit(args.join(' ')) }
        env.font = Roff::Font::Regular
        builder.heading(level, spans, indent)
        builder.no_space = true
      end
    end

    private def paragraph : Nil
      @engine.builder.blank(@distance)
      @engine.env.font = Roff::Font::Regular
      @prevailing = IN
    end

    private def width(text : String?) : Nil
      return unless text
      @prevailing = Roff::Numeric.columns(text, 'n') || @prevailing
    end

    private def one_font(font : Roff::Font, line : String) : Nil
      env = @engine.env
      args = @engine.split_args(line)
      if args.empty?
        env.font = font
        @engine.after_next_line { @engine.env.font = Roff::Font::Regular }
        return
      end
      env.font = font
      continued = @engine.emit(args.join(' '))
      env.font = Roff::Font::Regular
      @engine.text_line_done(continued)
    end

    private def alternate(fonts : {Roff::Font, Roff::Font}, args : Array(String)) : Nil
      env = @engine.env
      continued = false
      args.each_with_index do |arg, index|
        env.font = fonts[index % 2]
        continued = @engine.emit(arg)
      end
      env.font = Roff::Font::Regular
      @engine.text_line_done(continued)
    end

    private def synopsis(command : String) : Nil
      builder = @engine.builder
      env = @engine.env
      builder.break_line
      hang = Unicode.text_width(@engine.plain_text(command)) + 1
      env.indent = @margin + hang
      builder.hang(-hang)
      env.font = Roff::Font::Bold
      @engine.emit(command)
      env.font = Roff::Font::Regular
      builder.word_space
    end

    private def plain(text : String) : String
      @engine.plain_text(text)
    end
  end
end
