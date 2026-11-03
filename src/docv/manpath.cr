# src/docv/manpath.cr

require "compress/gzip"

module Docv
  # The manual search path: man page directories (trees of `man<section>`
  # directories, or flat directories of pages) searched in order, plus the
  # current project's Markdown documents.
  class Manpath
    # Section search order (man-db's default); other sections come after.
    ORDER = %w(1 n l 8 3 0 2 3type 3posix 3pm 3perl 3am 5 4 9 6 7)

    # A section name: `1`, `3p`, `3type`, `n`, `l`.
    SECTION = /\A(?:[0-9][a-zA-Z0-9]*|n|l)\z/

    # :nodoc:
    # man-db configuration files; the first that exists is read.
    CONFIGS = ["/etc/man_db.conf", "/etc/manpath.config"]
    # :nodoc:
    # Mandatory directories without a man-db configuration.
    DEFAULTS = ["/usr/share/man", "/usr/local/share/man", "/usr/man"]
    # :nodoc:
    # Tried next to a `PATH` element without a `MANPATH_MAP` line, as man-db does.
    NEIGHBORS = ["../man", "man", "../share/man", "share/man"]

    # :nodoc:
    # Files and directories that mark a project root.
    MARKERS = %w(.git .hg .svn .jj shard.yml Cargo.toml package.json go.mod pyproject.toml setup.py Gemfile
      pom.xml build.gradle CMakeLists.txt meson.build configure.ac Makefile makefile)
    # :nodoc:
    # Skipped in a project walk, besides hidden directories.
    SKIP = Set{"node_modules", "vendor", "lib", "target", "__pycache__"}
    # :nodoc:
    MAX_DEPTH = 4
    # :nodoc:
    MAX_DIRS = 2000

    # :nodoc:
    PATHS_FILE = "paths"
    # :nodoc:
    PATHS_HEADER = "# Man page directories added with docv path-add, one per line.\n"

    # :nodoc:
    record Root, path : String, flat : Bool = false, project : Bool = false

    # The project around a directory: its *root*, its man page directories
    # (*pages*) and its Markdown documents (*documents*), in search order.
    record Project, root : String, pages : Array(String), documents : Array(String)

    # :nodoc:
    record ManDb, map : Hash(String, Array(String)), mandatory : Array(String)

    # :nodoc:
    # In search order; a tree's locale subdirectories come before it.
    getter roots : Array(Root)
    # The project whose pages and documents come first, if any.
    getter project : Project?

    @listing = Hash(String, Array(String)).new
    @paths : Array(String)
    @locale : String?

    # The search path of *roots* in order, each a tree or a flat directory;
    # missing and repeated directories are dropped, and a tree's *locale*
    # subdirectories come first. *project* is returned by `#project`.
    def initialize(roots : Enumerable(String), @locale : String? = Manpath.locale, @project : Project? = nil)
      @paths = roots.to_a
      variants = Manpath.locale_variants(locale)
      own = @project.try(&.pages.map { |dir| Manpath.absolute(dir) }.to_set) || Set(String).new
      seen = Set(String).new
      @roots = [] of Root
      roots.each do |root|
        path = Path[root].expand(home: true).to_s
        next unless Dir.exists?(path) && seen.add?(path)
        project = own.includes?(path)
        if Manpath.flat?(path)
          @roots << Root.new(path, true, project)
        else
          variants.each do |variant|
            dir = File.join(path, variant)
            @roots << Root.new(dir, project: project) if Dir.exists?(dir) && seen.add?(dir)
          end
          @roots << Root.new(path, project: project)
        end
      end
    end

    # This search path with *dir*, a directory of pages of the project (a
    # tree or flat), searched first.
    def prepend(dir : String) : Manpath
      project = @project.try { |found| found.copy_with(pages: [dir] + found.pages) } ||
                Project.new(File.dirname(Manpath.absolute(dir)), [dir], [] of String)
      Manpath.new([dir] + @paths, @locale, project)
    end

    # The search path of the `docv` command: the project around *dir* (if
    # given), then the directories added with `docv path-add`, then the
    # system path.
    def self.default(dir : String? = nil) : Manpath
      found = dir ? project(dir) : nil
      new((found.try(&.pages) || [] of String) + read_paths + system, project: found)
    end

    # The system search path as man-db builds it (manpath(5)) from *manpath*
    # (`MANPATH`), *path* (`PATH`) and the man-db configuration.
    def self.system(manpath : String? = ENV["MANPATH"]?, path : String? = ENV["PATH"]?,
                    config : ManDb = man_db) : Array(String)
      default = derived(path, config)
      return default if manpath.nil? || manpath.empty?
      manpath.split(':').flat_map { |part| part.empty? ? default : [part] }
    end

    private def self.derived(path : String?, config : ManDb) : Array(String)
      dirs = [] of String
      (path || "").split(':').each do |element|
        next if element.empty?
        if mapped = config.map[element]?
          dirs.concat(mapped)
        else
          NEIGHBORS.each do |relative|
            dir = File.expand_path(relative, element)
            dirs << dir if Dir.exists?(dir)
          end
        end
      end
      dirs + config.mandatory
    end

    # :nodoc:
    # Without a configuration file: no maps, `DEFAULTS` mandatory.
    def self.man_db(files : Array(String) = CONFIGS) : ManDb
      file = files.find { |candidate| File.file?(candidate) }
      return ManDb.new(Hash(String, Array(String)).new, DEFAULTS) unless file
      parse_man_db(File.read(file))
    rescue File::Error
      ManDb.new(Hash(String, Array(String)).new, DEFAULTS)
    end

    # :nodoc:
    def self.parse_man_db(text : String) : ManDb
      map = {} of String => Array(String)
      mandatory = [] of String
      text.each_line do |line|
        fields = line.split
        case fields[0]?
        when "MANDATORY_MANPATH"
          fields[1]?.try { |dir| mandatory << dir }
        when "MANPATH_MAP"
          if (bin = fields[1]?) && (man = fields[2]?)
            (map[bin] ||= [] of String) << man
          end
        end
      end
      ManDb.new(map, mandatory)
    end

    # The project root around *dir*: the nearest directory below the home
    # directory with a project marker (`.git`, `shard.yml`, ...), else *dir*
    # itself; `nil` when that is the home directory or `/`.
    def self.project_root(dir : String) : String?
      start = Path[dir].expand(home: true).to_s
      home = Path.home.to_s
      current = start
      until current == home || current == "/"
        return current if MARKERS.any? { |marker| File.exists?(File.join(current, marker)) }
        parent = File.dirname(current)
        break if parent == current
        current = parent
      end
      start == home || start == "/" ? nil : start
    end

    # The man page directories of the project around *dir*.
    def self.discover(dir : String) : Array(String)
      project(dir).try(&.pages) || [] of String
    end

    # The project around *dir* (`project_root`) with the man page directories
    # and Markdown documents found a few levels below its root, skipping
    # hidden and vendored directories; `nil` without a project root.
    def self.project(dir : String) : Project?
      root = project_root(dir) || return nil
      pages = [] of String
      documents = [] of String
      queue = Deque({String, Int32}).new
      queue << {root, 0}
      visited = 0
      while visited < MAX_DIRS && (item = queue.shift?)
        path, depth = item
        visited += 1
        children = entries(path)
        if children.any? { |child| section_dir?(path, child) }
          pages << path
          next
        end
        pages << path if children.any? { |child| page?(File.join(path, child)) }
        children.each do |child|
          next if child.starts_with?('.') || !Markdown.file?(child)
          full = File.join(path, child)
          documents << full if File.file?(full)
        end
        next if depth >= MAX_DEPTH
        children.each do |child|
          next if child.starts_with?('.') || SKIP.includes?(child)
          full = File.join(path, child)
          queue << {full, depth + 1} if File.directory?(full) && !File.symlink?(full)
        end
      end
      Project.new(root, pages, documents)
    end

    # True for a directory with pages in it and no `man<section>` directories.
    def self.flat?(dir : String) : Bool
      children = entries(dir)
      children.none? { |child| section_dir?(dir, child) } && children.any? { |child| page?(File.join(dir, child)) }
    end

    # True for a directory with man pages: a tree or a flat directory.
    def self.pages?(dir : String) : Bool
      children = entries(dir)
      children.any? { |child| section_dir?(dir, child) } || children.any? { |child| page?(File.join(dir, child)) }
    end

    # True for a file named like a page (`split`) whose text, gzipped or
    # not, starts with a roff control character.
    def self.page?(path : String) : Bool
      return false unless split(File.basename(path)) && File.file?(path)
      File.open(path) do |file|
        head = file.peek || return false
        text = if head.size >= 2 && head[0] == 0x1f && head[1] == 0x8b
                 Compress::Gzip::Reader.open(file, &.gets(64))
               else
                 file.gets(64)
               end
        stripped = (text || "").lstrip
        stripped.starts_with?('.') || stripped.starts_with?('\'')
      end
    rescue IO::Error | Compress::Gzip::Error
      false
    end

    # Splits a page file name into name and section: `printf.3.gz` gives
    # `{"printf", "3"}`. The extension must start like *section* when given,
    # else match `SECTION`; `nil` otherwise.
    def self.split(file : String, section : String = "") : {String, String}?
      base = file.rchop(".gz")
      dot = base.rindex('.') || return nil
      return nil if dot == 0 || dot == base.size - 1
      ext = base[(dot + 1)..]
      fits = section.empty? ? ext.matches?(SECTION) : ext[0] == section[0]
      fits ? {base[0, dot], ext} : nil
    end

    # The file of directories added with `docv path-add`:
    # `$XDG_CONFIG_HOME/docv/paths`.
    def self.paths_file : String
      File.join(Docv.user_directory("XDG_CONFIG_HOME", ".config"), PATHS_FILE)
    end

    # The added directories listed in *file*.
    def self.read_paths(file : String = paths_file) : Array(String)
      return [] of String unless File.file?(file)
      File.read_lines(file).map(&.strip).reject { |line| line.empty? || line.starts_with?('#') }
    rescue File::Error
      [] of String
    end

    # Adds *dirs*, made absolute, to *file*; returns those it did not hold.
    def self.add_paths(dirs : Array(String), file : String = paths_file) : Array(String)
      current = read_paths(file)
      added = dirs.map { |dir| absolute(dir) }.uniq.reject { |dir| current.includes?(dir) }
      write_paths(current + added, file) unless added.empty?
      added
    end

    # Removes *dirs*, made absolute, from *file*; returns those it held.
    def self.remove_paths(dirs : Array(String), file : String = paths_file) : Array(String)
      current = read_paths(file)
      removed = dirs.map { |dir| absolute(dir) }.uniq.select { |dir| current.includes?(dir) }
      write_paths(current - removed, file) unless removed.empty?
      removed
    end

    # :nodoc:
    def self.absolute(dir : String) : String
      Path[dir].expand(home: true).to_s
    end

    private def self.write_paths(dirs : Array(String), file : String) : Nil
      Dir.mkdir_p(File.dirname(file))
      File.write(file, String.build { |io| io << PATHS_HEADER; dirs.each { |dir| io << dir << '\n' } })
    end

    private def self.section_dir?(parent : String, child : String) : Bool
      child.starts_with?("man") && child[3..].matches?(SECTION) && File.directory?(File.join(parent, child))
    end

    private def self.entries(dir : String) : Array(String)
      Dir.children(dir).sort!
    rescue File::Error
      [] of String
    end

    # The message locale from the environment; `nil` for C/POSIX.
    def self.locale : String?
      value = ENV["LC_ALL"]?.presence || ENV["LC_MESSAGES"]?.presence || ENV["LANG"]?.presence
      return nil if value.nil? || value == "C" || value == "POSIX" || value.starts_with?("C.")
      value
    end

    # :nodoc:
    # Most specific first: `nl_NL.UTF-8`, `nl_NL`, `nl`.
    def self.locale_variants(locale : String?) : Array(String)
      return [] of String unless locale
      variants = [locale] of String
      base = locale.split('.').first.split('@').first
      variants << base
      variants << base.split('_').first
      variants.uniq
    end

    # Splits a `name(section)` reference into `{name, section}`; the section
    # is `nil` for other text.
    def self.parse_reference(text : String) : {String, String?}
      if match = text.match(/\A(.+)\(([0-9a-zA-Z]+)\)\z/)
        {match[1], match[2]}
      else
        {text, nil}
      end
    end

    # Sort key of *section* in search order (`ORDER`, then by name).
    def self.rank(section : String) : {Int32, String}
      {ORDER.index(section) || ORDER.size, section}
    end

    # The file of page *name*, in *section* when given (`3` also matches
    # `3p`, `3type`); `nil` when not found.
    def find(name : String, section : String? = nil) : String?
      sections(section).each do |sec, exact|
        @roots.each do |root|
          dir = root.flat ? root.path : File.join(root.path, "man#{sec}")
          listing(dir).each do |file|
            next unless file.starts_with?(name) && file.byte_at?(name.bytesize) == '.'.ord
            page, ext = Manpath.split(file, root.flat ? "" : sec) || next
            next unless page == name && (exact ? ext == section : ext.starts_with?(sec))
            path = File.join(dir, file)
            next if root.flat && !Manpath.page?(path)
            return path
          end
        end
      end
      nil
    end

    # All sections across the roots, in search order.
    def all_sections : Array(String)
      found = @roots.flat_map do |root|
        if root.flat
          listing(root.path).compact_map { |file| Manpath.split(file).try(&.[1]) }
        else
          listing(root.path).select { |child| child.starts_with?("man") && child[3..].matches?(SECTION) }.map(&.[3..])
        end
      end
      found.uniq.sort_by! { |sec| Manpath.rank(sec) }
    end

    private def sections(section : String?) : Array({String, Bool})
      if section
        list = [] of {String, Bool}
        all_sections.each do |sec|
          list << {sec, sec != section} if sec == section || (section.starts_with?(sec) && sec.size == 1)
        end
        list.empty? ? [{section, false}] : list
      else
        all_sections.map { |sec| {sec, false} }.as(Array({String, Bool}))
      end
    end

    private def listing(dir : String) : Array(String)
      @listing[dir] ||= Dir.children(dir).sort!
    rescue File::Error
      [] of String
    end
  end
end
