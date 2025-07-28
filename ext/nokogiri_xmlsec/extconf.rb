# frozen_string_literal: true

# rubocop:disable Style/GlobalVars

ENV["RC_ARCHS"] = "" if RUBY_PLATFORM.include?("darwin")

require "mkmf"
require "nokogiri"

# helpful constants
PACKAGE_ROOT_DIR = File.expand_path(File.join(File.dirname(__FILE__), "..", ".."))

REQUIRED_MINI_PORTILE_VERSION = "~> 2.8.2" # keep this version in sync with the one in the gemspec

NOKOGIRI_XMLSEC_HELP_MESSAGE = <<~TEXT.freeze
  USAGE: ruby #{$PROGRAM_NAME} [options]

    Flags that are always valid:

      --use-system-libraries
      --enable-system-libraries
          Use system libraries instead of building and using the packaged libraries.

      --disable-system-libraries
          Use the packaged libraries, and ignore the system libraries. This is the default on most
          platforms, and overrides `--use-system-libraries` and the environment variable
          `NOKOGIRI_USE_SYSTEM_LIBRARIES`.

      --disable-clean
          Do not clean out intermediate files after successful build.

      --prevent-strip
          Take steps to prevent stripping the symbol table and debugging info from the shared
          library, potentially overriding RbConfig's CFLAGS/LDFLAGS/DLDFLAGS.


    Flags only used when using system libraries:

      General:

        --with-opt-dir=DIRECTORY
            Look for headers and libraries in DIRECTORY.

        --with-opt-lib=DIRECTORY
            Look for libraries in DIRECTORY.

        --with-opt-include=DIRECTORY
            Look for headers in DIRECTORY.


      Related to xmlsec:

        --with-xmlsec-dir=DIRECTORY
            Look for xmlsec headers and library in DIRECTORY.

        --with-xmlsec-lib=DIRECTORY
            Look for xmlsec library in DIRECTORY.

        --with-xmlsec-include=DIRECTORY
            Look for xmlsec headers in DIRECTORY.


    Flags only used when building and using the packaged libraries:

      --disable-static
          Do not statically link packaged libraries, instead use shared libraries.

      --enable-cross-build
          Enable cross-build mode. (You probably do not want to set this manually.)


    Environment variables used:

      NOKOGIRI_USE_SYSTEM_LIBRARIES
          Equivalent to `--enable-system-libraries` when set, even if nil or blank.

      AR
          Use this path to invoke the library archiver instead of `RbConfig::CONFIG['AR']`

      CC
          Use this path to invoke the compiler instead of `RbConfig::CONFIG['CC']`

      CPPFLAGS
          If this string is accepted by the C preprocessor, add it to the flags passed to the C preprocessor

      CFLAGS
          If this string is accepted by the compiler, add it to the flags passed to the compiler

      LD
          Use this path to invoke the linker instead of `RbConfig::CONFIG['LD']`

      LDFLAGS
          If this string is accepted by the linker, add it to the flags passed to the linker

      LIBS
          Add this string to the flags passed to the linker
TEXT

#
#  utility functions
#
def config_clean?
  enable_config("clean", true)
end

def config_static?
  default_static = !truffle?
  enable_config("static", default_static)
end

def config_cross_build?
  enable_config("cross-build")
end

def config_system_libraries?
  enable_config("system-libraries", ENV.key?("NOKOGIRI_USE_SYSTEM_LIBRARIES")) do |_, default|
    arg_config("--use-system-libraries", default)
  end
end

def windows?
  RbConfig::CONFIG["target_os"].match?(/mingw|mswin/)
end

def solaris?
  RbConfig::CONFIG["target_os"].include?("solaris")
end

def darwin?
  RbConfig::CONFIG["target_os"].include?("darwin")
end

def openbsd?
  RbConfig::CONFIG["target_os"].include?("openbsd")
end

def unix?
  !(windows? || solaris? || darwin?)
end

def truffle?
  RUBY_ENGINE == "truffleruby"
end

def concat_flags(*args)
  args.compact.join(" ")
end

def local_have_library(lib, func = nil, headers = nil)
  have_library(lib, func, headers) || have_library("lib#{lib}", func, headers)
end

# set up mkmf to link against the library if we can find it
def have_package_configuration(lib:, func:, headers:, opt: nil, pc: nil) # rubocop:disable Naming/PredicatePrefix, Naming/MethodParameterName
  if opt
    dir_config(opt)
    dir_config("opt")
  end

  # see if we have enough path info to do this without trying any harder
  return true if !ENV.key?("NOKOGIRI_TEST_PKG_CONFIG") && local_have_library(lib, func, headers)

  pkg_config(pc) if pc

  # verify that we can compile and link against the library
  local_have_library(lib, func, headers)
end

def ensure_package_configuration(lib:, func:, headers:, opt: nil, pc: nil) # rubocop:disable Naming/MethodParameterName
  have_package_configuration(opt:, pc:, lib:, func:, headers:) ||
    abort_could_not_find_library(lib)
end

def ensure_func(func, headers = nil)
  have_func(func, headers) || abort_could_not_find_library(func)
end

def preserving_globals
  values = [$arg_config, $INCFLAGS, $CFLAGS, $CPPFLAGS, $LDFLAGS, $DLDFLAGS, $LIBPATH, $libs].map(&:dup)
  yield
ensure
  $arg_config, $INCFLAGS, $CFLAGS, $CPPFLAGS, $LDFLAGS, $DLDFLAGS, $LIBPATH, $libs = values
end

def abort_could_not_find_library(lib)
  callers = caller(1..2).join("\n")
  abort("-----\n#{callers}\n#{lib} is missing. Please locate mkmf.log to investigate how it is failing.\n-----")
end

def chdir_for_build(&)
  # When using rake-compiler-dock on Windows, the underlying Virtualbox shared
  # folders don't support symlinks, but libiconv expects it for a build on
  # Linux. We work around this limitation by using the temp dir for cooking.
  build_dir = /mingw|mswin|cygwin/.match?(ENV["RCD_HOST_RUBY_PLATFORM"].to_s) ? "/tmp" : "."
  Dir.chdir(build_dir, &)
end

def libflag_to_filename(ldflag)
  case ldflag
  when /\A-l(.+)/
    "lib#{Regexp.last_match(1)}.#{$LIBEXT}"
  end
end

def process_recipe(name, version, static:, cross_build:, cacheable: true)
  require "rubygems"
  gem("mini_portile2", REQUIRED_MINI_PORTILE_VERSION) # gemspec is not respected at install time
  require "mini_portile2"
  message("Using mini_portile version #{MiniPortile::VERSION}\n")

  MiniPortile.new(name, version).tap do |recipe|
    def recipe.port_path
      "#{@target}/#{RUBY_PLATFORM}/#{@name}/#{@version}"
    end

    # We use 'host' to set compiler prefix for cross-compiling. Prefer host_alias over host. And
    # prefer i686 (what external dev tools use) to i386 (what ruby's configure.ac emits).
    recipe.host = RbConfig::CONFIG["host_alias"].empty? ? RbConfig::CONFIG["host"] : RbConfig::CONFIG["host_alias"]
    recipe.host = recipe.host.gsub("i386", "i686")

    recipe.target = File.join(PACKAGE_ROOT_DIR, "ports") if cacheable
    recipe.configure_options << "--libdir=#{File.join(recipe.path, "lib")}"

    yield recipe

    env = Hash.new do |hash, key|
      hash[key] = ENV[key].to_s
    end

    recipe.configure_options.flatten!

    recipe.configure_options.delete_if do |option|
      case option
      when /\A(\w+)=(.*)\z/
        env[Regexp.last_match(1)] = if env.key?(Regexp.last_match(1))
                                      concat_flags(env[Regexp.last_match(1)], Regexp.last_match(2))
                                    else
                                      Regexp.last_match(2)
                                    end
        true
      else
        false
      end
    end

    if static
      recipe.configure_options += [
        "--disable-shared",
        "--enable-static"
      ]
      env["CFLAGS"] = concat_flags(env["CFLAGS"], "-fPIC")
    else
      recipe.configure_options += [
        "--enable-shared",
        "--disable-static"
      ]
    end

    if cross_build
      recipe.configure_options += [
        "--target=#{recipe.host}",
        "--host=#{recipe.host}"
      ]
    end

    if RbConfig::CONFIG["target_cpu"] == "universal"
      %w[CFLAGS LDFLAGS].each do |key|
        env[key] = concat_flags(env[key], RbConfig::CONFIG["ARCH_FLAG"]) unless env[key].include?("-arch")
      end
    end

    recipe.configure_options += env.map do |key, value|
      "#{key}=#{value.strip}"
    end

    checkpoint = "#{recipe.target}/#{recipe.name}-#{recipe.version}-#{RUBY_PLATFORM}.installed"
    if File.exist?(checkpoint) && !recipe.source_directory
      message("Building Nokogiri-XMLSec with a packaged version of #{name}-#{version}.\n")
    else
      message(<<~TEXT)
        ---------- IMPORTANT NOTICE ----------
        Building Nokogiri-XMLSec with a packaged version of #{name}-#{version}.
        Configuration options: #{recipe.configure_options.shelljoin}
      TEXT

      unless recipe.patch_files.empty?
        message("The following patches are being applied:\n")

        recipe.patch_files.each do |patch|
          message(format("  - %s\n", File.basename(patch)))
        end
      end

      message(<<~TEXT)

        The Nokogiri-XMLSec maintainers intend to provide timely security updates, but if
        this is a concern for you and want to use your OS/distro system library
        instead, then abort this installation process and install nokogiri-xmlsec as
        instructed at:

          https://nokogiri.org/tutorials/installing_nokogiri.html#installing-using-standard-system-libraries

        Note, however, that nokogiri-xmlsec cannot guarantee compatibility with every
        version of XMLSec that may be provided by OS/package vendors.

      TEXT

      chdir_for_build { recipe.cook }
      FileUtils.touch(checkpoint)
    end
    recipe.activate
  end
end

def copy_packaged_libraries_headers(to_path:, from_recipes:)
  FileUtils.rm_rf(to_path, secure: true)
  FileUtils.mkdir(to_path)
  from_recipes.each do |recipe|
    FileUtils.cp_r(Dir[File.join(recipe.path, "include/*")], to_path)
  end
end

def do_help
  print(NOKOGIRI_XMLSEC_HELP_MESSAGE)
  exit!(0)
end

def do_clean
  root = Pathname(PACKAGE_ROOT_DIR)
  pwd  = Pathname(Dir.pwd)

  # Skip if this is a development work tree
  unless (root / ".git").exist?
    message("Cleaning files only used during build.\n")

    # (root + 'tmp') cannot be removed at this stage because
    # nokogiri.so is yet to be copied to lib.

    # clean the ports build directory
    Pathname.glob(pwd.join("tmp", "*", "ports")) do |dir|
      FileUtils.rm_rf(dir, verbose: true)
    end

    if config_static?
      # ports installation can be safely removed if statically linked.
      FileUtils.rm_rf(root / "ports", verbose: true)
    else
      FileUtils.rm_rf(root / "ports" / "archives", verbose: true)
    end
  end

  exit!(0)
end

# In ruby 3.2, symbol resolution changed on Darwin, to introduce the `-bundle_loader` flag to
# resolve symbols against the ruby binary.
#
# This makes it challenging to build a single extension that works with both a ruby with
# `--enable-shared` and one with `--disable-shared. To work around that, we choose to add
# `-flat_namespace` to the link line (later in this file).
#
# The `-flat_namespace` line introduces its own behavior change, which is that (similar to on
# Linux), any symbols in the extension that are exported may now be resolved by shared libraries
# loaded by the Ruby process. Specifically, that means that libxml2 and libxslt, which are
# statically linked into the nokogiri bundle, will resolve (at runtime) to a system libxml2 loaded
# by Ruby on Darwin. And it appears that often Ruby on Darwin does indeed load the system libxml2,
# and that messes with our assumptions about whether we're running with a patched libxml2 or a
# vanilla libxml2.
#
# We choose to use `-load_hidden` in this case to prevent exporting those symbols from xmlsec1
# which ensures that they will be resolved to the static libraries in the bundle. In other
# words, when we use `load_hidden`, what happens in the extension stays in the extension.
#
# See https://github.com/rake-compiler/rake-compiler-dock/issues/87 for more info.
#
# Anyway, this method is the logical bit to tell us when to turn on these workarounds.
def needs_darwin_linker_hack?
  config_cross_build? &&
    darwin? &&
    RbConfig::MAKEFILE_CONFIG["EXTDLDFLAGS"].include?("-bundle_loader")
end

#
#  main
#
do_help if arg_config("--help")
do_clean if arg_config("--clean")

if openbsd? && !config_system_libraries?
  unless `#{ENV["CC"] || "/usr/bin/cc"} -v 2>&1`.include?("clang")
    (ENV["CC"] ||= find_executable("egcc")) ||
      abort("Please install gcc 4.9+ from ports using `pkg_add -v gcc`")
  end
  append_cppflags "-I/usr/local/include"
end

RbConfig::CONFIG["AR"] = RbConfig::MAKEFILE_CONFIG["AR"] = ENV["AR"] if ENV["AR"]

RbConfig::CONFIG["CC"] = RbConfig::MAKEFILE_CONFIG["CC"] = ENV["CC"] if ENV["CC"]

RbConfig::CONFIG["LD"] = RbConfig::MAKEFILE_CONFIG["LD"] = ENV["LD"] if ENV["LD"]

# use same toolchain for libxml and libxslt
ENV["AR"] = RbConfig::CONFIG["AR"]
ENV["CC"] = RbConfig::CONFIG["CC"]
ENV["LD"] = RbConfig::CONFIG["LD"]

if arg_config("--prevent-strip")
  old_cflags = $CFLAGS.split.join(" ")
  old_ldflags = $LDFLAGS.split.join(" ")
  old_dldflags = $DLDFLAGS.split.join(" ")
  $CFLAGS = $CFLAGS.split.reject { |flag| flag == "-s" }.join(" ")
  $LDFLAGS = $LDFLAGS.split.reject { |flag| flag == "-s" }.join(" ")
  $DLDFLAGS = $DLDFLAGS.split.reject { |flag| flag == "-s" }.join(" ")
  puts "Prevent stripping by removing '-s' from $CFLAGS" if old_cflags != $CFLAGS
  puts "Prevent stripping by removing '-s' from $LDFLAGS" if old_ldflags != $LDFLAGS
  puts "Prevent stripping by removing '-s' from $DLDFLAGS" if old_dldflags != $DLDFLAGS
end

# adopt environment config
append_cflags(ENV["CFLAGS"]) unless ENV["CFLAGS"].nil?
append_cppflags(ENV["CPPFLAGS"]) unless ENV["CPPFLAGS"].nil?
append_ldflags(ENV["LDFLAGS"]) unless ENV["LDFLAGS"].nil?
$LIBS = concat_flags($LIBS, ENV["LIBS"])

append_cflags("-O2")

# always include debugging information
append_cflags("-g")

# good to have no matter what Ruby was compiled with
append_cflags("-Wmissing-noreturn")

# Work around a character escaping bug in MSYS by passing an arbitrary double-quoted parameter to gcc.
# See https://sourceforge.net/p/mingw/bugs/2142
append_cppflags(' "-Idummypath"') if windows?

if config_system_libraries?
  message "Building nokogiri-xmlsec using system libraries.\n"
  ensure_package_configuration(
    opt: "xmlsec1",
    pc: "xmlsec1-2.0",
    lib: "xmlsec1",
    headers: "xmlsec/xmlsec.h",
    func: "xmlSecInit"
  )
else
  message "Building nokogiri-xmlsec using packaged libraries.\n"

  static = config_static?
  message "Static linking is #{static ? "enabled" : "disabled"}.\n"

  cross_build = config_cross_build?
  message "Cross build is #{cross_build ? "enabled" : "disabled"}.\n"

  require "yaml"
  dependencies = YAML.load_file(File.join(PACKAGE_ROOT_DIR, "dependencies.yml"))

  xmlsec_recipe = process_recipe("xmlsec1", dependencies["xmlsec1"]["version"], static:, cross_build:) do |recipe|
    source_dir = arg_config("--with-xmlsec-source-dir")
    if source_dir
      recipe.source_directory = source_dir
    else
      recipe.files = [{
        url: "https://github.com/lsh123/xmlsec/releases/download/#{recipe.version}/xmlsec1-#{recipe.version}.tar.gz",
        sha256: dependencies["xmlsec1"]["sha256"]
      }]
    end

    cppflags = concat_flags(ENV["CPPFLAGS"])
    cflags = concat_flags(ENV["CFLAGS"], "-O2", "-g")

    cppflags = concat_flags(cppflags, "-DNOKOGIRI_PRECOMPILED_LIBRARIES") if cross_build

    if darwin? && !cross_build
      recipe.configure_options << "RANLIB=/usr/bin/ranlib" unless ENV.key?("RANLIB")
      recipe.configure_options << "AR=/usr/bin/ar" unless ENV.key?("AR")
    end

    recipe.configure_options << if source_dir
                                  "--config-cache"
                                else
                                  "--disable-dependency-tracking"
                                end

    recipe.configure_options += [
      "--enable-debugging",
      "--enable-static-linking",
      "CPPFLAGS=#{cppflags}",
      "CFLAGS=#{cflags}"
    ]
  end

  append_cppflags("-DNOKOGIRI_PACKAGED_LIBRARIES")
  append_cppflags("-DNOKOGIRI_PRECOMPILED_LIBRARIES") if cross_build

  $libs = $libs.shellsplit.tap do |libs|
    [xmlsec_recipe].each do |recipe|
      libname = recipe.name[/\A(?:lib)?(.+)\z/, 1]
      config_basename = "#{libname}-config"
      File.join(recipe.path, "bin", config_basename).tap do |config|
        # call config scripts explicit with 'sh' for compat with Windows
        cflags = `sh #{config} --cflags`.strip
        message("#{config_basename} cflags: #{cflags}\n")
        $CPPFLAGS = concat_flags(cflags, $CPPFLAGS) # prepend

        `sh #{config} --libs`.strip.shellsplit.each do |arg|
          case arg
          when /\A-L(.+)\z/
            # Prioritize ports' directories
            $LIBPATH = if Regexp.last_match(1).start_with?("#{PACKAGE_ROOT_DIR}/")
                         [Regexp.last_match(1)] | $LIBPATH
                       else
                         $LIBPATH | [Regexp.last_match(1)]
                       end
          when /\A-l./
            libs.unshift(arg)
          else
            $LDFLAGS << " " << arg.shellescape
          end
        end

        case libname
        when "xmlsec1"
          # xmlsec1-config --libs or pkg-config xmlsec1 --libs does not include
          # -llzma, so we need to add it manually when linking statically.
          if static && (crypto = `sh #{config} --crypto`.strip) &&
            preserving_globals { local_have_library("xmlsec1-#{crypto}") }
            # Add it at the end
            libs << "-lxmlsec1-#{crypto}"
          end
        end
      end
    end
  end.shelljoin

  if static
    static_archive_ld_flag = needs_darwin_linker_hack? ? ["-load_hidden"] : []
    $libs = $libs.shellsplit.map do |arg|
      case arg
      when "-lxmlsec"
        static_archive_ld_flag + [File.join(xmlsec_recipe.path, "lib", libflag_to_filename(arg))]
      else
        arg
      end
    end.flatten.shelljoin
  end

  ensure_func("xmlSecInit", "xmlsec/xmlsec.h")
end

unless config_system_libraries?
  if cross_build
    # When precompiling native gems, copy packaged libraries' headers to ext/nokogiri_xmlsec/include
    # These are packaged up by the cross-compiling callback in the ExtensionTask
    copy_packaged_libraries_headers(
      to_path: File.join(PACKAGE_ROOT_DIR, "ext/nokogiri_xmlsec/include"),
      from_recipes: [libxml2_recipe, libxslt_recipe]
    )
  else
    # When compiling during installation, install packaged libraries' header files into ext/nokogiri_xmlsec/include
    copy_packaged_libraries_headers(
      to_path: "include",
      from_recipes: [xmlsec_recipe]
    )
    $INSTALLFILES << ["include/**/*.h", "$(rubylibdir)"]
  end
end

abort unless find_header("nokogiri.h", *Dir["#{Gem.loaded_specs["nokogiri"].full_gem_path}/ext/*"])

create_makefile("nokogiri_xmlsec/nokogiri_xmlsec")

if config_clean?
  # Do not clean if run in a development work tree.
  File.open("Makefile", "at") do |mk|
    mk.print(<<~TEXT)

      all: clean-ports
      clean-ports: $(TARGET_SO)
      \t-$(Q)$(RUBY) $(srcdir)/extconf.rb --clean --#{static ? "enable" : "disable"}-static
    TEXT
  end
end

# rubocop:enable Style/GlobalVars
