# src/docv/source.cr

require "compress/gzip"

module Docv
  # :nodoc:
  # Reads page files and resolves `.so` and `.nx` includes.
  class Source
    getter path : String?

    def initialize(@path : String? = nil)
    end

    # Inflates gzip data.
    def self.read(path : String) : String
      bytes = File.open(path, &.getb_to_end)
      if bytes.size >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
        bytes = Compress::Gzip::Reader.open(IO::Memory.new(bytes), &.getb_to_end)
      end
      decode(bytes)
    end

    # Falls back to Latin-1 for invalid UTF-8.
    def self.decode(bytes : Bytes) : String
      text = String.new(bytes)
      return text if text.valid_encoding?
      String.build(bytes.size) { |io| bytes.each { |byte| io << byte.chr } }
    end

    # Tries the manual tree root (the parent of `manN/`), then the including
    # file's directory.
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

    # `nil` when the include cannot be found or read.
    def include(name : String) : String?
      resolve(name).try { |found| Source.read(found) }
    rescue IO::Error | Compress::Gzip::Error
      nil
    end
  end
end
