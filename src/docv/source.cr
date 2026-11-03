# src/docv/source.cr
require "compress/gzip"

module Docv
  # Reads page files (plain or gzip) and resolves `.so` and `.nx` includes
  # against the page's manual tree.
  class Source
    # The file the document came from, if any.
    getter path : String?

    def initialize(@path : String? = nil)
    end

    # Reads *path* as text, inflating gzip data and decoding invalid UTF-8 as
    # Latin-1.
    def self.read(path : String) : String
      bytes = File.open(path, &.getb_to_end)
      if bytes.size >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
        bytes = Compress::Gzip::Reader.open(IO::Memory.new(bytes), &.getb_to_end)
      end
      decode(bytes)
    end

    # Decodes *bytes* as UTF-8, falling back to Latin-1.
    def self.decode(bytes : Bytes) : String
      text = String.new(bytes)
      return text if text.valid_encoding?
      String.build(bytes.size) { |io| bytes.each { |byte| io << byte.chr } }
    end

    # Resolves an include name: relative to the manual tree root (the
    # directory holding `manN/`), then to the including file's directory.
    def resolve(name : String) : String?
      candidates = [] of String
      if Path[name].absolute?
        candidates << name
      else
        if path = @path
          dir = File.dirname(path)
          candidates << File.join(File.dirname(dir), name)
          candidates << File.join(dir, name)
        end
        candidates << name
      end
      candidates.each do |candidate|
        return candidate if File.file?(candidate)
        gz = candidate + ".gz"
        return gz if File.file?(gz)
      end
      nil
    end

    # Reads an include; `nil` when it cannot be found or read.
    def include(name : String) : String?
      resolve(name).try { |found| Source.read(found) }
    rescue IO::Error | Compress::Gzip::Error
      nil
    end
  end
end
