# src/docv/crystal_pages/session.cr

require "file_utils"

module Docv
  module CrystalPages
    # The pages of the shard at a root, generated for a viewer: kept in a
    # RAM-backed directory that `#close` removes (`PageStore::Memory`), or
    # written into the shard's man directory (`PageStore::Disk`). `#save`
    # writes them into the man directory either way.
    #
    # ```
    # root = Docv::CrystalPages::Shard.root(Dir.current) || abort "not in a shard"
    # session = Docv::CrystalPages::Session.new(root)
    # session.generate
    # Docv::Viewer.new(manpath: Docv::Manpath.default(root).prepend(session.directory)).run
    # session.close
    # ```
    class Session
      getter root : String
      getter store : PageStore
      # The directory the pages are generated into, a man page tree.
      getter directory : String

      @pages : Array(Page)? = nil

      # *memory* is the parent of the directory memory-stored pages go to.
      def initialize(@root : String, @store : PageStore = PageStore::Memory,
                     memory : String = Docv.runtime_directory)
        @directory = @store.memory? ? File.join(memory, "crystal-#{Process.pid}") : output
      end

      # The shard's man directory, where `#save` writes.
      def output : String
        File.join(@root, OUTPUT)
      end

      # The shard's name, from `shard.yml` or the root directory.
      def name : String
        @pages.try(&.first?).try(&.name) || File.basename(@root)
      end

      # Whether `#generate` succeeded.
      def generated? : Bool
        !@pages.nil?
      end

      # Runs `crystal docs` and writes the pages into `#directory`; returns
      # their references (`name(7cr)`). Raises `Error` when it fails.
      def generate : Array(String)
        pages = CrystalPages.pages(@root, OUTPUT, quiet: true)
        CrystalPages.write(pages, @directory)
        @pages = pages
        pages.map { |page| "#{page.name}(#{page.section})" }
      end

      # Writes the generated pages into `#output`; reports the counts.
      # Raises `Error` before `#generate` succeeded, or when `#output` holds
      # a page of the same name that was not generated.
      def save : String
        pages = @pages || raise Error.new("no pages generated yet")
        "#{OUTPUT}: #{CrystalPages.write(pages, output)}"
      end

      # Removes memory-stored pages.
      def close : Nil
        FileUtils.rm_rf(@directory) if @store.memory?
      end
    end
  end
end
