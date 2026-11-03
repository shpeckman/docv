# src/docv/macros/mdoc_data.cr
module Docv::Macros
  # Static tables of the mdoc(7) package.
  module MdocData
    # Body indent of sections, subsection heading indent, display indent.
    INDENT     = 5
    SUB_INDENT = 3
    DISPLAY    = 6

    # Manual names per section (`.Dt` without a volume).
    VOLUMES = {
      "1" => "General Commands Manual", "2" => "System Calls Manual", "3" => "Library Functions Manual",
      "4" => "Device Drivers Manual", "5" => "File Formats Manual", "6" => "Games Manual",
      "7" => "Miscellaneous Information Manual", "8" => "System Manager's Manual",
      "9" => "Kernel Developer's Manual",
    }

    # Fonts of the inline semantic macros.
    FONTS = {
      "Ad" => Roff::Font::Italic, "An" => Roff::Font::Regular, "Ar" => Roff::Font::Italic,
      "Cd" => Roff::Font::Bold, "Cm" => Roff::Font::Bold, "Dv" => Roff::Font::Regular,
      "Em" => Roff::Font::Italic, "Er" => Roff::Font::Regular, "Ev" => Roff::Font::Regular,
      "Fa" => Roff::Font::Italic, "Fd" => Roff::Font::Bold, "Fl" => Roff::Font::Bold,
      "Ft" => Roff::Font::Italic, "Ic" => Roff::Font::Bold, "Li" => Roff::Font::Regular,
      "Ms" => Roff::Font::Regular, "Mt" => Roff::Font::Italic, "Nm" => Roff::Font::Bold,
      "No" => Roff::Font::Regular, "Ot" => Roff::Font::Italic, "Pa" => Roff::Font::Italic,
      "Sx" => Roff::Font::Regular, "Sy" => Roff::Font::Bold, "Tn" => Roff::Font::Regular,
      "Va" => Roff::Font::Italic, "Vt" => Roff::Font::Italic, "Fr" => Roff::Font::Regular,
    }

    # One-line enclosures.
    ENCLOSE = {
      "Aq" => {"⟨", "⟩"}, "Bq" => {"[", "]"}, "Brq" => {"{", "}"}, "Dq" => {"“", "”"},
      "Op" => {"[", "]"}, "Pq" => {"(", ")"}, "Qq" => {"\"", "\""}, "Sq" => {"‘", "’"},
      "Ql" => {"‘", "’"},
    }

    # Multi-line enclosure openers and closers.
    OPEN  = {"Ao" => "⟨", "Bo" => "[", "Bro" => "{", "Do" => "“", "Oo" => "[", "Po" => "(", "Qo" => "\"", "So" => "‘"}
    CLOSE = {"Ac" => "⟩", "Bc" => "]", "Brc" => "}", "Dc" => "”", "Oc" => "]", "Pc" => ")", "Qc" => "\"", "Sc" => "’"}

    # Operating system names (`.Bsx`, `.Fx`, ...).
    SYSTEMS = {"Bsx" => "BSD/OS", "Fx" => "FreeBSD", "Nx" => "NetBSD", "Ox" => "OpenBSD", "Dx" => "DragonFly"}

    # Fixed phrases.
    PHRASES = {"Ux" => "UNIX", "Ud" => "currently under development.", "Bt" => "is currently in beta test."}

    # Macros that may be called from within a macro line.
    CALLABLE = Set{
      "Ac", "Ad", "An", "Ao", "Ap", "Aq", "Ar", "At", "Bc", "Bo", "Bq", "Brc", "Bro", "Brq", "Bsx",
      "Bx", "Cd", "Cm", "Dc", "Do", "Dq", "Dv", "Dx", "Ec", "Em", "En", "Eo", "Er", "Es", "Ev", "Fa",
      "Fc", "Fl", "Fn", "Fo", "Fr", "Ft", "Fx", "Ic", "Li", "Lk", "Ms", "Mt", "Nm", "No", "Ns", "Nx",
      "Oc", "Oo", "Op", "Ot", "Ox", "Pa", "Pc", "Pf", "Po", "Pq", "Qc", "Ql", "Qo", "Qq", "Sc", "So",
      "Sq", "Sx", "Sy", "Ta", "Tn", "Ux", "Va", "Vt", "Xc", "Xo", "Xr", "%A", "%B", "%C", "%D", "%I",
      "%J", "%N", "%O", "%P", "%Q", "%R", "%T", "%U", "%V", "Ex", "Rv", "St", "Lb", "Ud", "Bt",
    }

    # Every macro of the package.
    MACROS = CALLABLE + Set{
      "Dd", "Dt", "Os", "Sh", "Ss", "Pp", "Lp", "Nd", "Bl", "El", "It", "Bd", "Ed", "D1", "Dl", "Bf",
      "Ef", "Bk", "Ek", "Rs", "Re", "Sm", "Hf", "Db", "Tg", "In", "Fn", "Ad", "Ud",
    }

    # `.St` standards.
    STANDARDS = {
      "-p1003.1-88" => "IEEE Std 1003.1-1988 (“POSIX.1”)", "-p1003.1-90" => "IEEE Std 1003.1-1990 (“POSIX.1”)",
      "-p1003.1-96" => "ISO/IEC 9945-1:1996 (“POSIX.1”)", "-p1003.1-2001" => "IEEE Std 1003.1-2001 (“POSIX.1”)",
      "-p1003.1-2004" => "IEEE Std 1003.1-2004 (“POSIX.1”)", "-p1003.1-2008" => "IEEE Std 1003.1-2008 (“POSIX.1”)",
      "-p1003.1-2024" => "IEEE Std 1003.1-2024 (“POSIX.1”)", "-p1003.1" => "IEEE Std 1003.1 (“POSIX.1”)",
      "-p1003.1b" => "IEEE Std 1003.1b (“POSIX.1b”)", "-p1003.1b-93" => "IEEE Std 1003.1b-1993 (“POSIX.1b”)",
      "-p1003.1c-95" => "IEEE Std 1003.1c-1995 (“POSIX.1c”)", "-p1003.1g-2000" => "IEEE Std 1003.1g-2000 (“POSIX.1g”)",
      "-p1003.1i-95" => "IEEE Std 1003.1i-1995 (“POSIX.1i”)", "-p1003.2" => "IEEE Std 1003.2 (“POSIX.2”)",
      "-p1003.2-92" => "IEEE Std 1003.2-1992 (“POSIX.2”)", "-p1003.2a-92" => "IEEE Std 1003.2a-1992 (“POSIX.2”)",
      "-isoC" => "ISO/IEC 9899:1990 (“ISO C90”)", "-isoC-90" => "ISO/IEC 9899:1990 (“ISO C90”)",
      "-isoC-amd1" => "ISO/IEC 9899/AMD1:1995 (“ISO C90, Amendment 1”)", "-isoC-tcor1" => "ISO/IEC 9899/TCOR1:1994 (“ISO C90, Technical Corrigendum 1”)",
      "-isoC-tcor2" => "ISO/IEC 9899/TCOR2:1995 (“ISO C90, Technical Corrigendum 2”)", "-isoC-99" => "ISO/IEC 9899:1999 (“ISO C99”)",
      "-isoC-2011" => "ISO/IEC 9899:2011 (“ISO C11”)", "-isoC-2023" => "ISO/IEC 9899:2024 (“ISO C23”)",
      "-ansiC" => "ANSI X3.159-1989 (“ANSI C89”)", "-ansiC-89" => "ANSI X3.159-1989 (“ANSI C89”)",
      "-ieee754" => "IEEE Std 754-1985", "-iso8601" => "ISO 8601", "-iso8802-3" => "ISO 8802-3: 1989",
      "-ieee1275-94" => "IEEE Std 1275-1994 (“Open Firmware”)", "-xpg3" => "X/Open Portability Guide Issue 3 (“XPG3”)",
      "-xpg4" => "X/Open Portability Guide Issue 4 (“XPG4”)", "-xpg4.2" => "X/Open Portability Guide Issue 4, Version 2 (“XPG4.2”)",
      "-xpg4.3" => "X/Open Portability Guide Issue 4, Version 3 (“XPG4.3”)", "-xbd5" => "X/Open Base Definitions Issue 5 (“XBD5”)",
      "-xcu5" => "X/Open Commands and Utilities Issue 5 (“XCU5”)", "-xsh5" => "X/Open System Interfaces and Headers Issue 5 (“XSH5”)",
      "-xns5" => "X/Open Networking Services Issue 5 (“XNS5”)", "-xns5.2" => "X/Open Networking Services Issue 5.2 (“XNS5.2”)",
      "-xcurses4.2" => "X/Open Curses Issue 4, Version 2 (“XCURSES4.2”)", "-susv1" => "Version 1 of the Single UNIX Specification (“SUSv1”)",
      "-susv2" => "Version 2 of the Single UNIX Specification (“SUSv2”)", "-susv3" => "Version 3 of the Single UNIX Specification (“SUSv3”)",
      "-susv4" => "Version 4 of the Single UNIX Specification (“SUSv4”)", "-svid4" => "System V Interface Definition, Fourth Edition (“SVID4”)",
    }

    # `.Lb` library names.
    LIBRARIES = {
      "libc" => "Standard C Library (libc, -lc)", "libm" => "Math Library (libm, -lm)",
      "libpthread" => "POSIX Threads Library (libpthread, -lpthread)", "libutil" => "System Utilities Library (libutil, -lutil)",
      "libcrypt" => "Crypt Library (libcrypt, -lcrypt)", "libdl" => "Dynamic Linker Library (libdl, -ldl)",
      "librt" => "POSIX Real-time Library (librt, -lrt)", "libbsd" => "Utility functions from BSD systems (libbsd, -lbsd)",
      "libkvm" => "Kernel Data Access Library (libkvm, -lkvm)", "libz" => "Compression Library (libz, -lz)",
      "libedit" => "Command Line Editor Library (libedit, -ledit)", "libcurses" => "Curses Library (libcurses, -lcurses)",
      "libncurses" => "Ncurses Library (libncurses, -lncurses)", "libutil-linux" => "util-linux Library",
    }

    # `.At` versions.
    AT_VERSIONS = {
      "v1" => "Version 1 AT&T UNIX", "v2" => "Version 2 AT&T UNIX", "v3" => "Version 3 AT&T UNIX",
      "v4" => "Version 4 AT&T UNIX", "v5" => "Version 5 AT&T UNIX", "v6" => "Version 6 AT&T UNIX",
      "v7" => "Version 7 AT&T UNIX", "32v" => "Version 32V AT&T UNIX", "III" => "AT&T System III UNIX",
      "V" => "AT&T System V UNIX", "V.1" => "AT&T System V Release 1 UNIX", "V.2" => "AT&T System V Release 2 UNIX",
      "V.3" => "AT&T System V Release 3 UNIX", "V.4" => "AT&T System V Release 4 UNIX",
    }

    # Order of `.Rs` reference fields in output.
    REFERENCE_ORDER = %w(%A %T %B %I %J %R %N %V %P %Q %C %D %O %U)
  end
end
