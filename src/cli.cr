# src/cli.cr

require "./docv/viewer"
require "./docv/crystal_pages"

# :nodoc:
# The `docv` command.
module Docv::CLI
  USAGE = <<-TEXT
    usage: docv [-u]
           docv [-u] [section] name
           docv [-u] name(section)
           docv [-u] file          (a page, or a Markdown document: *.md ...)
           docv path-add dir...
           docv path-rm dir...
           docv path-list
           docv gen-cr [-o dir] [shard]
      -u, --unwrapped   start with unwrapped (one line per paragraph) layout
                        (also [viewer] start-wrapped = false in config.ini)
      -h, --help        show this help

    Without a page, the viewer opens on an empty page; Ctrl-b opens the dock
    with the pages and documents of the current folder's project. Inside a
    Crystal shard the viewer generates its pages as gen-cr does ([crystal]
    in config.ini), in memory unless store = disk; Ctrl-s saves them.

    Pages are looked up in the man page directories of the project around
    the current directory, then in the added directories, then along the
    system path (MANPATH, or man-db's rules from PATH and man_db.conf).
    The page search (/) also lists the project's Markdown documents; the
    project's pages and documents come first.

      path-add dir...   add directories of man pages: trees (man1/, man3/...)
                        or directories with pages in them
      path-rm dir...    remove added directories
      path-list         print the search path and where each entry comes from
      gen-cr            generate man pages of the Crystal shard at or above
                        shard (default: the current directory) from README.md
                        and its doc comments: name.7cr and foo-bar.3cr pages in
                        dir (default: man), relative to the shard root
      text-worker       (used by the viewer) read page paths from standard
                        input and write the text of each page to standard
                        output, for finding text across all pages

    Configuration: $XDG_CONFIG_HOME/docv/config.ini (created on first run)
    Added directories: $XDG_CONFIG_HOME/docv/paths
    TEXT

  def self.run(args : Array(String)) : Int32
    case args.first?
    when "path-add"  then return path_add(args[1..])
    when "path-rm"   then return path_rm(args[1..])
    when "path-list" then return args.size == 1 ? path_list : usage_error
    when "gen-cr"    then return gen_cr(args[1..])
    when "text-worker"
      Corpus.serve
      return 0
    end
    unwrapped = false
    names = [] of String
    args.each do |arg|
      case arg
      when "-u", "--unwrapped" then unwrapped = true
      when "-h", "--help"
        puts USAGE
        return 0
      else
        if arg.starts_with?('-') && arg.size > 1
          STDERR.puts "docv: unknown option #{arg}\n#{USAGE}"
          return 2
        end
        names << arg
      end
    end
    Corpus.worker = Process.executable_path.try { |executable| [executable, "text-worker"] }
    tty = Term::Tty.new
    return usage_error if names.size > 2 || (names.empty? && !tty.tty?)
    config = configuration || return 1
    wrap = config.start_wrapped? && !unwrapped
    manpath = Manpath.default(Dir.current)
    if names.empty?
      crystal = crystal_session(config)
      viewer = Viewer.new(wrap: wrap, manpath: manpath, tty: tty, options: config.options, theme: config.theme,
        settings: config.picker, crystal: crystal)
      viewer.run
      return 0
    end
    path = resolve(names, manpath) || return 1
    document = Docv.load(path, config.options(STDIN))
    if tty.tty?
      crystal = crystal_session(config)
      Viewer.new(document, path, wrap, manpath, tty, config.options, config.theme, settings: config.picker,
        crystal: crystal).run
    else
      width = ENV["MANWIDTH"]?.try(&.to_i?) || 80
      Layout.new(document).lines(width, wrap).each { |line| STDOUT.puts line.text.rstrip }
    end
    0
  rescue ex : IO::Error | Compress::Gzip::Error
    STDERR.puts "docv: #{ex.message}"
    1
  ensure
    crystal.try &.close
  end

  # The pages the viewer generates for the Crystal shard around the current
  # directory (`[crystal]` in the configuration); `nil` outside a shard.
  private def self.crystal_session(config : Config) : CrystalPages::Session?
    return nil unless config.crystal.generate
    root = CrystalPages::Shard.root(Dir.current) || return nil
    CrystalPages::Session.new(root, config.crystal.store)
  end

  private def self.usage_error : Int32
    STDERR.puts USAGE
    2
  end

  # Creates the file on first run; `nil` when it is invalid.
  private def self.configuration : Config?
    Config.load
  rescue ex : Config::Error
    STDERR.puts "docv: #{ex.message}"
    nil
  rescue ex : File::Error
    STDERR.puts "docv: cannot create #{Config.path}: #{ex.message}"
    Config.new
  end

  private def self.resolve(names : Array(String), manpath : Manpath) : String?
    if names.size == 1
      name = names[0]
      return name if name.includes?('/') || (File.file?(name) && !name.matches?(Manpath::SECTION))
      name, section = Manpath.parse_reference(name)
    else
      section, name = names[0], names[1]
      unless section.matches?(Manpath::SECTION)
        STDERR.puts "docv: invalid section #{section}"
        return nil
      end
    end
    found = manpath.find(name, section)
    STDERR.puts "docv: no manual entry for #{name}#{section ? "(#{section})" : ""}" unless found
    found
  end

  # All directories must exist.
  private def self.path_add(dirs : Array(String)) : Int32
    return usage_error if dirs.empty?
    missing = dirs.reject { |dir| Dir.exists?(Manpath.absolute(dir)) }
    unless missing.empty?
      missing.each { |dir| STDERR.puts "docv: not a directory: #{dir}" }
      return 1
    end
    added = Manpath.add_paths(dirs)
    dirs.map { |dir| Manpath.absolute(dir) }.uniq.each do |dir|
      if added.includes?(dir)
        puts "added #{dir}"
        STDERR.puts "docv: warning: no man pages in #{dir}" unless Manpath.pages?(dir)
      else
        puts "already added: #{dir}"
      end
    end
    0
  rescue ex : File::Error
    STDERR.puts "docv: cannot write #{Manpath.paths_file}: #{ex.message}"
    1
  end

  # Fails for a directory that was not added.
  private def self.path_rm(dirs : Array(String)) : Int32
    return usage_error if dirs.empty?
    removed = Manpath.remove_paths(dirs)
    status = 0
    dirs.map { |dir| Manpath.absolute(dir) }.uniq.each do |dir|
      if removed.includes?(dir)
        puts "removed #{dir}"
      else
        STDERR.puts "docv: not added: #{dir}"
        status = 1
      end
    end
    status
  rescue ex : File::Error
    STDERR.puts "docv: cannot write #{Manpath.paths_file}: #{ex.message}"
    1
  end

  # `gen-cr [-o dir] [shard]`; *dir* is relative to the shard root.
  private def self.gen_cr(args : Array(String)) : Int32
    output = CrystalPages::OUTPUT
    dirs = [] of String
    index = 0
    while arg = args[index]?
      case arg
      when "-o", "--output"
        output = args[index + 1]? || return usage_error
        index += 1
      else
        return usage_error if arg.starts_with?('-')
        dirs << arg
      end
      index += 1
    end
    return usage_error if dirs.size > 1
    dir = dirs.first? || Dir.current
    root = CrystalPages::Shard.root(dir)
    unless root
      STDERR.puts "docv: no shard.yml in #{dir} or above"
      return 1
    end
    puts CrystalPages.generate(root, File.expand_path(output, root))
    0
  rescue ex : CrystalPages::Error | File::Error | IO::Error | JSON::ParseException | JSON::SerializableError
    STDERR.puts "docv: gen-cr: #{ex.message}"
    1
  end

  # Each root with its source (`project`, `added`, `system`); `(pages)` marks a flat one.
  private def self.path_list : Int32
    project = Manpath.discover(Dir.current)
    added = Manpath.read_paths
    sources = {"project" => project, "added" => added}.transform_values(&.map { |dir| Manpath.absolute(dir) }.to_set)
    Manpath.new(project + added + Manpath.system).roots.each do |root|
      source = sources.find { |_, dirs| dirs.includes?(root.path) || dirs.includes?(File.dirname(root.path)) }.try(&.[0]) || "system"
      puts "#{source.ljust(8)} #{root.path}#{root.flat ? " (pages)" : ""}"
    end
    0
  end
end

exit Docv::CLI.run(ARGV)
