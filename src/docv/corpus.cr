# src/docv/corpus.cr
require "wait_group"
require "../docv"

module Docv
  # The plain text of many pages, for finding text across all of them: each
  # page laid out at `WIDTH` columns (wrapped, without header and footer),
  # one line per line with text, its blanks at either end stripped.
  #
  # The text lives in a cache file (`Corpus.cache_path`) that is mapped into
  # memory, one record per page with the page's modification time. `build`
  # takes a page's text from the cache while the time matches and parses
  # the other pages, then writes a new cache. Parsing allocates constantly,
  # and the garbage collector's allocation lock keeps threads of one process
  # from parsing faster together, so with a `Corpus.worker` command the pages
  # are parsed by *threads* worker processes (`Corpus.serve`), otherwise one
  # by one in this process. `count` searches every page on *threads*
  # searcher threads, each a fiber in an isolated execution context (a
  # thread of its own) that waits for searches on a channel.
  #
  # ```
  # corpus = Docv::Corpus.new
  # corpus.build([Docv::Corpus::Source.new("/usr/share/man/man1/ls.1.gz", mtime)])
  # corpus.count("sort time") # => [3]
  # ```
  class Corpus
    FILE = "text.bin"
    # First line of the cache file; another value discards the file.
    HEADER = "docv text 1"
    # Columns the pages are laid out at.
    WIDTH = 80
    # Pages a search fiber takes at a time.
    CHUNK = 64
    # Longest wait for a worker process to send one page.
    PAGE_TIMEOUT = 30.seconds

    # The command that starts a worker process, which runs `Corpus.serve`;
    # `nil` parses in this process. The `docv` command sets itself with its
    # `text-worker` subcommand.
    class_property worker : Array(String)? = nil

    # A page: its file and modification time in nanoseconds since the
    # epoch (`Index::Entry#mtime`).
    record Source, path : String, mtime : Int64

    # A cached record: the page's modification time, and the offset and
    # size of its text in the cache file.
    private record Span, mtime : Int64, offset : Int64, size : Int32

    # One search, shared by the searchers: they take chunks of pages in
    # turn and write each page's count.
    private class Search
      getter terms : Array(String)
      getter counts : Array(Int32)
      getter chunk = Atomic(Int32).new(0)
      getter group : WaitGroup
      getter cancelled : Proc(Bool)

      def initialize(@terms, size : Int32, threads : Int32, @cancelled)
        @counts = Array(Int32).new(size, 0)
        @group = WaitGroup.new(threads)
      end
    end

    # The cache file.
    getter cache : String
    # Worker processes that parse, and fibers that search, in parallel.
    getter threads : Int32
    # True once `build` finished.
    getter? ready = false

    @sources = [] of Source
    @spans = [] of Span?
    @map : Bytes? = nil
    @searches : Channel(Search)? = nil

    # A corpus cached in *cache*, working on *threads* processes and fibers
    # (0: one less than the processor count).
    def initialize(@cache : String = Corpus.cache_path, threads : Int32 = 0)
      @threads = threads > 0 ? threads : Math.max(System.cpu_count.to_i - 1, 1)
    end

    # The default cache file: `$XDG_CACHE_HOME/docv/text.bin`, or
    # `~/.cache/docv/text.bin`.
    def self.cache_path : String
      File.join(Docv.user_directory("XDG_CACHE_HOME", ".cache"), FILE)
    end

    # The text of the page at *path*: its lines at `WIDTH` columns with text,
    # stripped, each ending in a newline. Empty when the page cannot be read.
    def self.extract(path : String) : String
      document = Docv.load(path)
      String.build do |io|
        Layout.new(document).lines(WIDTH, true, header: false, footer: false).each do |line|
          text = line.text.strip
          io << text << '\n' unless text.empty?
        end
      end
    rescue Exception
      ""
    end

    # Runs a worker process: reads page paths from *input*, one per line,
    # and writes the size of each page's text (`extract`) on a line of its
    # own, then the text, to *output*.
    def self.serve(input : IO = STDIN, output : IO = STDOUT) : Nil
      while path = input.gets
        text = extract(path)
        output << text.bytesize << '\n' << text
        output.flush
      end
    end

    # Makes the text of *sources* available, in their order: from the cache
    # where a page's modification time matches, from parsing it otherwise,
    # writing a new cache when anything was parsed. Yields the pages parsed
    # so far and the number to parse, in the calling fiber.
    def build(sources : Array(Source), & : Int32, Int32 ->) : Nil
      @ready = false
      @sources = sources
      cached = read_cache
      missing = (0...sources.size).select do |index|
        source = sources[index]
        cacheable?(source.path) && cached[source.path]?.try(&.mtime) != source.mtime
      end
      unless missing.empty?
        write_cache(cached, missing) { |done, total| yield done, total }
        cached = read_cache
      end
      @spans = sources.map { |source| cached[source.path]?.try { |span| span.mtime == source.mtime ? span : nil } }
      @ready = true
    end

    # Builds without reporting progress.
    def build(sources : Array(Source)) : Nil
      build(sources) { }
    end

    # The text of page *index*: lines ending in newlines; empty when the
    # page has none or the corpus is not built.
    def text(index : Int32) : Bytes
      span = @spans[index]? || return Bytes.empty
      map = @map || return Bytes.empty
      map[span.offset, span.size]
    end

    # Counts, per page, the lines that every space-separated term of *query*
    # matches (`Fuzzy#match?`), searching on `threads` threads in parallel.
    # Returns `nil` when the query has no terms, the corpus is not built, or
    # *cancelled* turned true meanwhile (it is called from those threads).
    def count(query : String, cancelled : Proc(Bool) = -> { false }) : Array(Int32)?
      terms = query.split
      return nil if terms.empty? || !@ready
      search = Search.new(terms, @spans.size, @threads, cancelled)
      searches = self.searches
      @threads.times { searches.send(search) }
      search.group.wait
      cancelled.call ? nil : search.counts
    end

    # Unmaps the cache file and stops the searchers.
    def close : Nil
      @searches.try &.close
      @searches = nil
      unmap
      @spans = [] of Span?
      @ready = false
    end

    private def count_lines(text : Bytes, matchers : Array(Fuzzy)) : Int32
      count = 0
      start = 0
      while start < text.size
        stop = text.index('\n'.ord.to_u8, start) || text.size
        line = text[start, stop - start]
        count += 1 if matchers.all?(&.match?(line))
        start = stop + 1
      end
      count
    end

    # The channel the searchers wait on, starting them on first use.
    private def searches : Channel(Search)
      @searches ||= begin
        channel = Channel(Search).new(@threads)
        @threads.times do |number|
          Fiber::ExecutionContext::Isolated.new("docv-search-#{number}") do
            while search = channel.receive?
              run(search)
            end
          end
        end
        channel
      end
    end

    # Counts chunks of pages for *search* until none is left.
    private def run(search : Search) : Nil
      matchers = search.terms.map { |term| Fuzzy.new(term) }
      size = search.counts.size
      chunks = (size + CHUNK - 1) // CHUNK
      loop do
        current = search.chunk.add(1)
        break if current >= chunks || search.cancelled.call
        (current * CHUNK...Math.min((current + 1) * CHUNK, size)).each do |index|
          search.counts[index] = count_lines(text(index), matchers)
        end
      end
    ensure
      search.group.done
    end

    # Paths that fit the record header.
    private def cacheable?(path : String) : Bool
      !path.includes?('\t') && !path.includes?('\n')
    end

    # Maps the cache file and reads its records; empty when there is none or
    # it is from another version.
    private def read_cache : Hash(String, Span)
      unmap
      spans = {} of String => Span
      map = mmap(@cache) || return spans
      @map = map
      header = HEADER.to_slice
      return spans unless map.size > header.size && map[0, header.size] == header && map[header.size] == '\n'.ord
      position = header.size + 1
      while position < map.size
        stop = map.index('\n'.ord.to_u8, position) || break
        fields = String.new(map[position, stop - position]).split('\t')
        break unless fields.size == 3
        mtime = fields[1].to_i64? || break
        size = fields[2].to_i? || break
        offset = stop + 1
        break if offset + size > map.size
        spans[fields[0]] = Span.new(mtime, offset.to_i64, size)
        position = offset + size + 1
      end
      spans
    end

    # Writes a new cache: the current records of *cached* that a source
    # still has, then the pages at *missing*, parsed.
    private def write_cache(cached : Hash(String, Span), missing : Array(Int32), & : Int32, Int32 ->) : Nil
      Dir.mkdir_p(File.dirname(@cache))
      temp = "#{@cache}.#{Process.pid}"
      File.open(temp, "w") do |io|
        io << HEADER << '\n'
        skip = missing.to_set
        @sources.each_with_index do |source, index|
          next if skip.includes?(index)
          span = cached[source.path]? || next
          next unless span.mtime == source.mtime
          map = @map || next
          record(io, source, map[span.offset, span.size])
        end
        parse(missing) do |index, text, done|
          record(io, @sources[index], text.to_slice)
          yield done, missing.size
        end
      end
      unmap
      File.rename(temp, @cache)
    rescue File::Error | IO::Error
      File.delete?(temp) if temp
    end

    # Parses the pages at *indices*; yields each page's index, its text and
    # the count done, in the calling fiber.
    private def parse(indices : Array(Int32), & : Int32, String, Int32 ->) : Nil
      unless command = Corpus.worker
        indices.each_with_index do |index, done|
          yield index, Corpus.extract(@sources[index].path), done + 1
          Fiber.yield
        end
        return
      end
      jobs = Channel(Int32).new(@threads * 2)
      results = Channel({Int32, String}).new(@threads * 2)
      paths = indices.to_h { |index| {index, @sources[index].path} }
      @threads.times { spawn(name: "docv-worker") { work(command, paths, jobs, results) } }
      spawn(name: "docv-feed") do
        indices.each { |index| jobs.send(index) }
        jobs.close
      end
      indices.size.times do |done|
        index, text = results.receive
        yield index, text, done + 1
      end
    end

    # Feeds the jobs to a worker process started with *command*, sending
    # every result; a page the process fails on (or that takes longer than
    # `PAGE_TIMEOUT`) gets no text, and a new process takes the next one.
    private def work(command : Array(String), paths : Hash(Int32, String), jobs : Channel(Int32),
                     results : Channel({Int32, String})) : Nil
      process = nil
      while index = jobs.receive?
        text = begin
          current = process ||= start(command)
          ask(current, paths[index])
        rescue IO::Error | File::Error
          stop(process)
          process = nil
          ""
        end
        results.send({index, text})
      end
    ensure
      stop(process)
    end

    private def start(command : Array(String)) : Process
      process = Process.new(command[0], command[1..], input: :pipe, output: :pipe, error: :close)
      process.output.read_timeout = PAGE_TIMEOUT
      process
    end

    private def ask(process : Process, path : String) : String
      process.input << path << '\n'
      process.input.flush
      size = process.output.gets.try(&.to_i?) || raise IO::Error.new("worker sent no size")
      String.new(size) do |buffer|
        process.output.read_fully(Bytes.new(buffer, size))
        {size, 0}
      end
    end

    private def stop(process : Process?) : Nil
      process = process || return
      process.input.close
      process.terminate unless process.terminated?
      process.wait
    rescue IO::Error | RuntimeError
    end

    private def record(io : IO, source : Source, text : Bytes) : Nil
      io << source.path << '\t' << source.mtime << '\t' << text.size << '\n'
      io.write(text)
      io << '\n'
    end

    private def mmap(path : String) : Bytes?
      File.open(path) do |file|
        size = file.size
        return nil if size == 0
        pointer = LibC.mmap(nil, size, LibC::PROT_READ, LibC::MAP_PRIVATE, file.fd, 0)
        return nil if pointer == LibC::MAP_FAILED
        Bytes.new(pointer.as(UInt8*), size, read_only: true)
      end
    rescue File::Error
      nil
    end

    private def unmap : Nil
      map = @map || return
      LibC.munmap(map.to_unsafe.as(Void*), map.size)
      @map = nil
    end
  end
end
