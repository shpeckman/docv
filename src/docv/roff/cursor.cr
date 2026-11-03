# src/docv/roff/cursor.cr

# :nodoc:
module Docv::Roff
  # `Char::Reader` in a class, so scanning helpers share one position.
  class Cursor
    getter text : String

    def initialize(@text : String)
      @reader = Char::Reader.new(@text)
    end

    def has_next? : Bool
      @reader.has_next?
    end

    def current_char : Char
      @reader.current_char
    end

    def next_char : Nil
      @reader.next_char if @reader.has_next?
    end

    # Consumes and returns the current character; `nil` at the end.
    def take : Char?
      return nil unless @reader.has_next?
      char = @reader.current_char
      @reader.next_char
      char
    end

    # Byte offset.
    def pos : Int32
      @reader.pos
    end

    def rest : String
      @text.byte_slice(@reader.pos, @text.bytesize - @reader.pos)
    end
  end
end
