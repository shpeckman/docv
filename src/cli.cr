# src/cli.cr
require "./docv/viewer"
require "./docv/crystal_pages"

# The `docv` command: shows a manual page or a Markdown document in the
# viewer, or prints it as text when standard output is not a terminal.
# Without a page it opens the viewer on an empty page in the page search.
# `path-add`, `path-rm` and `path-list` manage the added man page
# directories; `gen-cr` generates the man pages of a Crystal shard.
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
      -h, --help        show this help

    Without a page, the viewer opens on an empty page in the page search.

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
                        and its doc comments: name.7cr and Type.3cr pages in
                        dir (default: man), relative to the shard root

    Configuration: $XDG_CONFIG_HOME/docv/config.ini (created on first run)
    Added directories: $XDG_CONFIG_HOME/docv/paths
    TEXT

  def self.run(args : Array(String)) : Int32
    case args.first?
    when "path-add"  then return path_add(args[1..])
    when "path-rm"   then return path_rm(args[1..])
    when "path-list" then return args.size == 1 ? path_list : usage_error
    when "gen-cr"    then return gen_cr(args[1..])
    end
    wrap = true
    names = [] of String
    args.each do |arg|
      case arg
      when "-u", "--unwrapped" then wrap = false
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
    tty = Term::Tty.new
    return usage_error if names.size > 2 || (names.empty? && !tty.tty?)
    config = configuration || return 1
    manpath = Manpath.default(Dir.current)
    if names.empty?
      viewer = Viewer.new(wrap: wrap, manpath: manpath, tty: tty, options: config.options, theme: config.theme)
      viewer.perform(Viewer::Action::OpenPage)
      viewer.run
      return 0
    end
    path = resolve(names, manpath) || return 1
    document = Docv.load(path, config.options(STDIN))
    if tty.tty?
      Viewer.new(document, path, wrap, manpath, tty, config.options, config.theme).run
    else
      width = ENV["MANWIDTH"]?.try(&.to_i?) || 80
      Layout.new(document).lines(width, wrap).each { |line| STDOUT.puts line.text.rstrip }
    end
    0
  rescue ex : IO::Error | Compress::Gzip::Error
    STDERR.puts "docv: #{ex.message}"
    1
  end

  private def self.usage_error : Int32
    STDERR.puts USAGE
    2
  end

  # Loads (or creates) the configuration; `nil` when it is invalid.
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

  # Adds directories to the added list; all must exist.
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

  # Removes directories from the added list; fails for one not in it.
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

  # Generates the man pages of the shard at or above the directory in
  # *args* (the current one by default) into `-o dir`, relative to the shard
  # root (`CrystalPages::OUTPUT` by default).
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

  # Prints the search path in order, each entry with its source (`project`,
  # `added`, `system`); `(pages)` marks a directory with pages in it.
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
