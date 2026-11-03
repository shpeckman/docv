# spec/numeric_spec.cr
require "./spec_helper"

describe Docv::Roff::Numeric do
  it "applies scale indicators in terminal units" do
    Docv::Roff::Numeric.eval("1i").should eq 240
    Docv::Roff::Numeric.eval("2n").should eq 48
    Docv::Roff::Numeric.eval("1v").should eq 40
  end

  it "evaluates operators left to right" do
    Docv::Roff::Numeric.eval("1+2*3").should eq 9
    Docv::Roff::Numeric.eval("1+(2*3)").should eq 7
    Docv::Roff::Numeric.eval("3>2&1").should eq 1
    Docv::Roff::Numeric.eval("5>?7").should eq 7
  end

  it "converts to columns with a default unit" do
    Docv::Roff::Numeric.columns("7").should eq 7
    Docv::Roff::Numeric.columns("0.5i").should eq 5
  end

  it "rejects invalid expressions" do
    Docv::Roff::Numeric.eval("abc").should be_nil
  end

  it "clamps huge extents" do
    Docv::Roff::Numeric.columns("99999999999999").should eq Docv::Roff::Numeric::MAX_EXTENT
  end
end
