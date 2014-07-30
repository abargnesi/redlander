require "spec_helper"

describe Redland do
  subject(:redland) {
    Redland
  }

  it "can load FFI library" do
    expect {
      redland::load_ffi
    }.not_to raise_error
  end

  it "can load librdf shared library" do
    expect {
      redland::load_ffi
      redland.librdf_new_world
    }.not_to raise_error
  end
end
