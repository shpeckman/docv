# src/docv/roff/builder.cr
module Docv::Roff
  # Collects formatted output into `Block`s. Text goes to the current block,
  # created on demand from the formatting environment, or to the innermost
  # capture (tags, headings, table cells).
  class Builder
    getter blocks = [] of Block
    # No-space mode (`.ns`): soft vertical space is dropped until text.
    property? no_space : Bool = false

    @current : Block? = nil
    @captures = [] of Array(Span)
    @space = false
    @hard_space = false
    @tag : Array(Span)? = nil
    @tag_indent = 0
    @hang : Int32? = nil

    # The formatting environment new blocks take their properties from.
    property env : Env

    def initialize(@env : Env)
    end

    # Appends *text* in *style*, preceded by a pending word space.
    def text(text : String, style : UInt16) : Nil
      return if text.empty?
      target = @captures.last? || current.spans
      append(target, @hard_space ? "\u00A0" : " ", 0_u16) if @space && !target.empty?
      @space = false
      append(target, text, style)
    end

    # Requests a word space before the next text (end of a filled input
    # line); a *hard* space does not break.
    def word_space(hard : Bool = false) : Nil
      @space = true
      @hard_space = hard
    end

    # Cancels a pending word space.
    def no_word_space : Nil
      @space = false
    end

    # True when text is being captured instead of set in a block.
    def capturing? : Bool
      !@captures.empty?
    end

    # Starts capturing text; pair with `end_capture`.
    def begin_capture : Nil
      @captures << [] of Span
      @space = false
    end

    # Ends the innermost capture and returns its spans.
    def end_capture : Array(Span)
      @space = false
      @captures.pop? || [] of Span
    end

    # Captures the text produced by the block.
    def capture(& : ->) : Array(Span)
      begin_capture
      yield
      end_capture
    end

    # Ends the current output line.
    def break_line : Nil
      if @current.nil? && @tag
        current
      end
      @current = nil
      @space = false
    end

    # Adds *lines* of vertical space. Soft space merges with adjacent soft
    # space and is dropped at the start and in no-space mode.
    def blank(lines : Int32, hard : Bool = false) : Nil
      break_line
      return if lines <= 0
      unless hard
        return if @no_space || @blocks.empty?
        last = @blocks.last
        if last.kind.blank? && last.soft?
          last.lines = Math.max(last.lines, lines)
          return
        end
      end
      block = Block.new(BlockKind::Blank)
      block.lines = lines
      block.soft = !hard
      @blocks << block
    end

    # Adds a heading of *level* (1 section, 2 subsection) at *indent*.
    def heading(level : Int32, spans : Array(Span), indent : Int32) : Nil
      break_line
      block = Block.new(BlockKind::Heading)
      block.level = level
      block.spans = spans
      block.indent = indent
      @blocks << block
      @no_space = false
    end

    # Adds a table at *indent*.
    def table(table : Table, indent : Int32) : Nil
      break_line
      block = Block.new(BlockKind::Table)
      block.table = table
      block.indent = indent
      @blocks << block
      @no_space = false
    end

    # Sets the tag of the next block, placed at column *indent*.
    def tag(spans : Array(Span), indent : Int32) : Nil
      @tag = spans
      @tag_indent = indent
    end

    # Sets the first-line offset of the next block (hanging paragraphs).
    def hang(offset : Int32) : Nil
      @hang = offset
    end

    # The block receiving text, created from the environment on demand.
    def current : Block
      @current ||= begin
        env = @env
        block = Block.new(BlockKind::Text)
        block.indent = env.indent
        if temp = env.temp_indent
          block.offset = temp - env.indent
          env.temp_indent = nil
        elsif hang = @hang
          block.offset = hang
        end
        @hang = nil
        block.fill = env.fill?
        block.align = if env.center > 0
                        Align::Center
                      elsif env.rjust > 0
                        Align::Right
                      elsif env.fill?
                        env.adjust
                      else
                        Align::Left
                      end
        block.tabs = env.tabs
        if tag = @tag
          block.tag = tag
          block.tag_indent = @tag_indent
          @tag = nil
        end
        @no_space = false
        @blocks << block
        block
      end
    end

    # Finishes output: a pending tag becomes a block of its own.
    def finish : Nil
      break_line
      while (last = @blocks.last?) && last.kind.blank?
        @blocks.pop
      end
    end

    private def append(target : Array(Span), text : String, style : UInt16) : Nil
      if (last = target.last?) && last.style == style && last.text.bytesize + text.bytesize <= 256
        target[-1] = Span.new(last.text + text, style)
      else
        target << Span.new(text, style)
      end
    end
  end
end
