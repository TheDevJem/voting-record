require "test_helper"

class RollCallTest < ActiveSupport::TestCase
  test "House vote type codes are shown in citation style" do
    assert_equal "H.Res. 1247", RollCall.legislation_label("HRES 1247")
    assert_equal "H.R. 2140", RollCall.legislation_label("HR 2140")
    assert_equal "S.J.Res. 7", RollCall.legislation_label("SJRES 7")
  end

  test "labels that are already citation style, or unknown, pass through" do
    assert_equal "S.Res. 20", RollCall.legislation_label("S.Res. 20")
    assert_equal "PN 1129", RollCall.legislation_label("PN 1129")
    assert_equal "S.Amdt.", RollCall.legislation_label("S.Amdt.")
    assert_nil RollCall.legislation_label(nil)
  end
end
