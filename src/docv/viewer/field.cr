# src/docv/viewer/field.cr

module Docv
  class Viewer
    # :nodoc:
    # The text of the search field.
    class Field
      getter text : String = ""

      def empty? : Bool
        @text.empty?
      end

      def insert(text : String) : Nil
        @text += text
      end

      # Removes the last grapheme; false when the field was empty.
      def delete_back : Bool
        return false if @text.empty?
        graphemes = @text.graphemes
        @text = graphemes[0...-1].join(&.to_s)
        true
      end

      def clear : Nil
        @text = ""
      end
    end
  end
end
