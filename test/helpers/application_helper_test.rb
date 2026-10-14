require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "whole_number matches number_with_precision with insignificant zeros stripped" do
    values = [ nil, "", 0, -0.001, 0.005, 0.004, 1, 999, 1000, 12_345.678, -98_765.4321, 1_234_567.5, 2.10,
               BigDecimal("123456789.995"), BigDecimal("-0.005"), "45.50" ]

    values.each do |value|
      decimal = value.to_d
      expected = "#{"-" if decimal.negative?}#{number_with_precision(decimal.abs, precision: 2, delimiter: ",", separator: ".", strip_insignificant_zeros: true)}"
      assert_equal expected, whole_number(value), "for #{value.inspect}"
    end
  end
end
