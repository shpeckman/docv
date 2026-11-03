# src/docv/roff/builder.cr

# :nodoc:
module Docv::Roff
  # Collects output into blocks, or into the innermost capture (tags, headings, cells).
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

    # Space before the next text; a *hard* space does not break.
    def word_space(hard : Bool = false) : Nil
      @space = true
      @hard_space = hard
    end

    def no_word_space : Nil
      @space = false
    end

    def capturing? : Bool
      !@captures.empty?
    end

    def begin_capture : Nil
      @captures << [] of Span
      @space = false
    end

    def end_capture : Array(Span)
      @space = false
      @captures.pop? || [] of Span
    end

    def capture(& : ->) : Array(Span)
      begin_capture
      yield
      end_capture
    end

    # Ends the current line; a pending tag still gets a block of its own.
    def break_line : Nil
      if @current.nil? && @tag
        current
      end
      @current = nil
      @space = false
    end

    # Soft space merges with soft space before it; dropped at the start and in no-space mode.
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

    # *level* 1 is a section, 2 a subsection.
    def heading(level : Int32, spans : Array(Span), indent : Int32) : Nil
      break_line
      block = Block.new(BlockKind::Heading)
      block.level = level
      block.spans = spans
      block.indent = indent
      @blocks << block
      @no_space = false
    end

    def table(table : Table, indent : Int32) : Nil
      break_line
      block = Block.new(BlockKind::Table)
      block.table = table
      block.indent = indent
      @blocks << block
      @no_space = false
    end

    # Tags the next block, at column *indent*.
    def tag(spans : Array(Span), indent : Int32) : Nil
      @tag = spans
      @tag_indent = indent
    end

    # First-line offset of the next block (hanging paragraphs).
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

    # Ends output and drops trailing blank blocks.
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
