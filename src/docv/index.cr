# src/docv/index.cr

require "compress/gzip"

module Docv
  # The pages along a `Manpath` and the Markdown documents of its project,
  # with their descriptions (the NAME line, or a document's first heading and
  # paragraph), cached in `Index.cache_path`. Project entries come first.
  class Index
    # :nodoc:
    # First line of the cache file; bump it when description extraction changes.
    HEADER = "docv-index 1"
    # :nodoc:
    FILE = "index.tsv"
    # :nodoc:
    # Lines read from a page while looking for the end of its NAME section.
    MAX_LINES = 2000
    # :nodoc:
    # `.so` redirections followed for one description.
    MAX_DEPTH = 4
    # :nodoc:
    # Mtime written for a partly described directory, so the next load rescans it.
    INCOMPLETE = -1_i64

    # :nodoc:
    # Headings read without a NAME heading before the first one counts as NAME.
    MAX_HEADINGS = 4

    # :nodoc:
    # The NAME heading in translated pages.
    NAMES = Set{"NAME", "NAAM", "NAMN", "NAVN", "NOM", "NOMBRE", "NOME", "NAZWA", "NUME", "NIMI", "NÉV",
                "JMÉNO", "ΟΝΟΜΑ", "ИМЯ", "НАЗВАНИЕ", "НАЗВА", "ИМЕ", "名前", "名称", "名稱", "이름"}

    # :nodoc:
    HEADING = /\A[.'][ \t]*S[Hh](?:\s+(.*?))?\s*\z/
    # :nodoc:
    # Macro definitions are not scanned for headings.
    DEFINITION = /\A[.'][ \t]*(?:de|de1|dei|am|am1|ami)\s/
    # :nodoc:
    END_DEFINITION = /\A[.'][ \t]*\.\s*\z/
    # :nodoc:
    SO = /\A[.'][ \t]*so[ \t]+(\S+)/
    # :nodoc:
    # The dash between the names and the description of a NAME line.
    SEPARATOR = / (?:-|--|—|–|−) /

    # An indexed page, or a project document (*name* is its path from the
    # project root and *section* is empty).
    class Entry
      getter name : String
      getter section : String
      getter path : String
      # Whether the entry belongs to the project.
      getter? project : Bool
      # Modification time in nanoseconds since the epoch.
      getter mtime : Int64
      # The description; empty until described, or when there is none.
      property description : String
      property? described : Bool

      def initialize(@name, @section, @path, @mtime, @description = "", @described = false, @project = false)
      end

      # The page reference (`ls(1)`), or a document's name.
      def reference : String
        @section.empty? ? @name : "#{@name}(#{@section})"
      end

      # True for a Markdown document.
      def document? : Bool
        @section.empty?
      end
    end

    private class Directory
      getter path : String
      getter section : String
      getter mtime : Int64
      getter? project : Bool
      getter entries = [] of Entry
      property pending = 0

      def initialize(@path, @section, @mtime, @project)
      end
    end

    private record Cached, mtime : Int64, files : Array({String, Int64, String})

    # The project's pages, its documents, then the other pages; pages by
    # section order and name, one per name and section (the first found).
    getter entries = [] of Entry
    # The cache file, if any.
    getter cache : String?

    @directories = [] of Directory
    # Entries to describe with their directory (`nil` for documents).
    @pending = [] of {Directory?, Entry}
    @done = 0
    @dirty = false
    @memo = {} of String => String

    # Lists the pages along *manpath*, taking descriptions from *cache*
    # (`nil` disables caching).
    def initialize(manpath : Manpath = Manpath.default, @cache : String? = Index.cache_path)
      cached = (cache = @cache) ? Index.read_cache(cache) : {} of String => Cached
      scan(manpath, cached)
    end

    # The default cache file: `$XDG_CACHE_HOME/docv/index.tsv`.
    def self.cache_path : String
      File.join(Docv.user_directory("XDG_CACHE_HOME", ".cache"), FILE)
    end

    # Number of entries still to describe.
    def pending : Int32
      @pending.size - @done
    end

    # True when every entry is described.
    def complete? : Bool
      pending == 0
    end

    # Describes the remaining entries, yielding the count done and the total
    # after each, then saves the cache.
    def describe(& : Int32, Int32 ->) : Nil
      total = @pending.size
      while @done < total
        directory, entry = @pending[@done]
        entry.description = Index.description(entry.path, @memo, 0)
        entry.described = true
        if directory
          directory.pending -= 1
          @dirty = true
        end
        @done += 1
        yield @done, total
      end
      save
    end

    # Describes the remaining entries and saves the cache.
    def describe : Nil
      describe { }
    end

    # Writes the cache, with the descriptions done so far, if anything changed.
    def save : Nil
      path = @cache || return
      return unless @dirty
      Dir.mkdir_p(File.dirname(path))
      temp = "#{path}.#{Process.pid}"
      File.open(temp, "w") do |io|
        io << HEADER << '\n'
        @directories.each do |directory|
          io << directory.path << '\t' << (directory.pending == 0 ? directory.mtime : INCOMPLETE) << '\n'
          directory.entries.each do |entry|
            next unless entry.described?
            io << File.basename(entry.path) << '\t' << entry.mtime << '\t' << entry.description << '\n'
          end
        end
      end
      File.rename(temp, path)
      @dirty = false
    rescue File::Error | IO::Error
    end

    # The description of the page or Markdown document at *path*; empty when
    # it has none or cannot be read.
    def self.description(path : String) : String
      description(path, {} of String => String, 0)
    end

    protected def self.description(path : String, memo : Hash(String, String), depth : Int32) : String
      return Markdown.description(Source.read(path)) if Markdown.file?(path)
      text, redirect = prefix(path)
      if redirect
        return "" if depth >= MAX_DEPTH
        target = Source.new(path).resolve(redirect) || return ""
        return memo[target] ||= description(target, memo, depth + 1)
      end
      name_text(Docv.parse(text, path))
    rescue Exception
      ""
    end

    # The source up to the heading after NAME (or after the first heading
    # without NAME within `MAX_HEADINGS`), or the `.so` target of an alias.
    private def self.prefix(path : String) : {String, String?}
      File.open(path) do |file|
        head = file.peek
        if head && head.size >= 2 && head[0] == 0x1f && head[1] == 0x8b
          Compress::Gzip::Reader.open(file) { |gzip| read_prefix(gzip) }
        else
          read_prefix(file)
        end
      end
    end

    private def self.read_prefix(io : IO) : {String, String?}
      headings = 0
      named = false
      defining = false
      redirect = nil
      text = String.build do |buffer|
        count = 0
        while count < MAX_LINES && (line = io.gets(chomp: false))
          count += 1
          line = Source.decode(line.to_slice) unless line.valid_encoding?
          if defining
            defining = !line.matches?(END_DEFINITION)
          elsif line.matches?(DEFINITION)
            defining = true
          elsif match = line.match(HEADING)
            break if named || headings == MAX_HEADINGS
            headings += 1
            named = name?(match[1]?)
          elsif headings == 0 && (match = line.match(SO))
            redirect ||= match[1]
          end
          buffer << line
        end
      end
      {text, headings == 0 ? redirect : nil}
    end

    private def self.name?(title : String?) : Bool
      title ? NAMES.includes?(title.strip('"').strip.upcase) : false
    end

    private def self.name_text(document : Document) : String
      blocks = document.blocks
      start = blocks.index { |block| section?(block) && name?(block.text) } ||
              blocks.index { |block| section?(block) } || return ""
      text = String.build do |io|
        (start + 1...blocks.size).each do |index|
          block = blocks[index]
          break if section?(block)
          next unless block.kind.text?
          block.tag.try &.each { |span| io << span.text << ' ' }
          io << block.text << ' '
        end
      end
      clean = text.split.join(' ')
      (match = SEPARATOR.match(clean)) ? clean[match.end..] : clean
    end

    # `.SH` or `.Sh`.
    private def self.section?(block : Block) : Bool
      block.kind.heading? && block.level == 1
    end

    protected def self.read_cache(path : String) : Hash(String, Cached)
      cached = {} of String => Cached
      return cached unless File.file?(path)
      File.open(path) do |io|
        return cached unless io.gets == HEADER
        files = nil
        io.each_line do |line|
          if line.starts_with?('/')
            dir, _, mtime = line.rpartition('\t')
            files = [] of {String, Int64, String}
            cached[dir] = Cached.new(mtime.to_i64? || INCOMPLETE, files)
          elsif files
            parts = line.split('\t', 3)
            next unless parts.size == 3
            files << {parts[0], parts[1].to_i64? || 0_i64, parts[2]}
          end
        end
      end
      cached
    rescue File::Error | IO::Error
      {} of String => Cached
    end

    private def scan(manpath : Manpath, cached : Hash(String, Cached)) : Nil
      found = [] of {Int32, Int32, String, Directory}
      manpath.roots.each_with_index do |root, root_index|
        if root.flat
          info = File.info?(root.path) || next
          found << {root_index, 0, "", directory(root.path, "", Index.mtime(info), cached[root.path]?, root.project)}
          next
        end
        children(root.path).each do |child|
          next unless child.starts_with?("man") && child.size > 3
          path = File.join(root.path, child)
          info = File.info?(path) || next
          next unless info.directory?
          section = child[3..]
          rank, name = Manpath.rank(section)
          found << {root_index, rank, name, directory(path, section, Index.mtime(info), cached[path]?, root.project)}
        end
      end
      @directories = found.sort_by! { |root_index, rank, name, _| {root_index, rank, name} }.map(&.[3])
      @dirty ||= cached.size != @directories.size
      documents(manpath.project)
      seen = Set({String, String}).new
      @directories.each do |directory|
        directory.entries.each do |entry|
          @entries << entry if seen.add?({entry.name, entry.section})
          @pending << {directory, entry} unless entry.described?
        end
      end
      @entries.sort_by! { |entry| {entry.project? ? 0 : 1, entry.document? ? 1 : 0, Manpath.rank(entry.section), entry.name} }
      @dirty ||= @pending.any? { |directory, _| directory }
    end

    # Named by their path from the project root; always described again.
    private def documents(project : Manpath::Project?) : Nil
      project = project || return
      project.documents.each do |path|
        info = File.info?(path) || next
        name = Path[path].relative_to(project.root).to_s
        entry = Entry.new(name, "", path, Index.mtime(info), project: true)
        @entries << entry
        @pending << {nil, entry}
      end
    end

    # A flat directory when *section* is empty, where every file must look like a page.
    private def directory(path : String, section : String, mtime : Int64, cached : Cached?, project : Bool) : Directory
      directory = Directory.new(path, section, mtime, project)
      if cached && cached.mtime == mtime
        cached.files.each do |file, file_mtime, description|
          name, ext = Manpath.split(file, section) || next
          directory.entries << Entry.new(name, ext, File.join(path, file), file_mtime, description, true, project)
        end
        return directory
      end
      @dirty = true
      previous = cached ? cached.files.to_h { |file, file_mtime, description| {file, {file_mtime, description}} } : nil
      children(path).each do |file|
        next if file.includes?('\t') || file.includes?('\n')
        name, ext = Manpath.split(file, section) || next
        full = File.join(path, file)
        info = File.info?(full, follow_symlinks: false) || next
        next if info.directory? || (section.empty? && !Manpath.page?(full))
        file_mtime = Index.mtime(info)
        entry = Entry.new(name, ext, full, file_mtime, project: project)
        if previous && (old = previous[file]?) && old[0] == file_mtime
          entry.description = old[1]
          entry.described = true
        else
          directory.pending += 1
        end
        directory.entries << entry
      end
      directory
    end

    protected def self.mtime(info : File::Info) : Int64
      time = info.modification_time
      time.to_unix * 1_000_000_000 + time.nanosecond
    end

    private def children(dir : String) : Array(String)
      Dir.children(dir).sort!
    rescue File::Error
      [] of String
    end
  end
end
