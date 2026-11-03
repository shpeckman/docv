# spec/mdoc_spec.cr
require "./spec_helper"

MDOC = <<-ROFF
  .Dd January 1, 2024
  .Dt TOOL 1
  .Os
  .Sh NAME
  .Nm tool
  .Nd do things
  .Sh SYNOPSIS
  .Nm
  .Op Fl v
  .Op Fl o Ar file
  .Ar input ...
  .Sh DESCRIPTION
  The
  .Nm
  utility reads
  .Pa /etc/x ,
  see
  .Xr other 5 .
  .Bl -tag -width Ds
  .It Fl v
  Verbose.
  .It Fl o Ar file
  Output to
  .Ar file .
  .El
  .Bl -bullet -compact
  .It
  one
  .It
  two
  .El
  .Bd -literal -offset indent
  code  here
  .Ed
  .Sh EXIT STATUS
  .Ex -std
  ROFF

describe Docv::Macros::Mdoc do
  it "reads the title and volume" do
    doc = parse(MDOC)
    doc.format.mdoc?.should be_true
    doc.reference.should eq "TOOL(1)"
    doc.manual.should eq "General Commands Manual"
  end

  it "formats name, synopsis and inline macros" do
    lines = render(MDOC, 70)
    lines.should contain("     tool — do things")
    lines.should contain("     tool [-v] [-o file] input ...")
    lines.should contain("     The tool utility reads /etc/x, see other(5).")
  end

  it "formats tag and bullet lists" do
    lines = render(MDOC, 70)
    lines.should contain("     -v    Verbose.")
    lines.should contain("     -o file")
    lines.should contain("           Output to file.")
    lines.should contain("     •   one")
    lines.should contain("     •   two")
  end

  it "keeps literal displays" do
    render(MDOC, 70).should contain("           code  here")
  end

  it "expands standard sentences" do
    render(MDOC, 70).join(' ').should contain("The tool utility exits 0 on success, and >0 if an error occurs.")
  end
end
