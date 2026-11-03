# src/docv/roff/cursor.cr
module Docv::Roff
  # A character reader passed by reference between scanning helpers.
  class Cursor
    getter text : String

    def initialize(@text : String)
      @reader = Char::Reader.new(@text)
    end

    # True while characters remain.
    def has_next? : Bool
      @reader.has_next?
    end

    # The character at the cursor.
    def current_char : Char
      @reader.current_char
    end

    # Advances past the current character.
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

    # The byte position.
    def pos : Int32
      @reader.pos
    end

    # The unread rest of the text.
    def rest : String
      @text.byte_slice(@reader.pos, @text.bytesize - @reader.pos)
    end
  end
end
