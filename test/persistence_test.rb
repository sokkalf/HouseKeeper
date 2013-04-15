require 'test/unit'
require_relative '../src/temperature'

require 'minitest/reporters'
MiniTest::Reporters.use!

class PersistenceTest < Test::Unit::TestCase

  # Called before every test method runs. Can be used
  # to set up fixture information.
  def setup
    @temp = Temperature.new(6.2, 'test', Time.now.to_s)
  end

  # Called after every test method runs. Can be used to tear
  # down fixture information.

  def teardown
    # Do nothing
  end

  def test_a_persist
    @temp.save
    Temperature.new(10, 'test', Time.now.to_s).save
    Temperature.new(15, 'test', Time.now.to_s).save
    Temperature.new(20, 'test', Time.now.to_s).save
    Temperature.new(25.4, 'test', Time.now.to_s).save
  end

  def test_b_find
    a = Temperature.find_by_source('test')
    assert_equal(5, a.size, 'Expected one result')
  end

  def test_c_find_highest
    a = Temperature.find_highest(1)
    assert_equal(25.4, a[0].temperature_reading, 'Expected 25.4')
  end

  def test_d_find_lowest
    a = Temperature.find_lowest(1)
    assert_equal(6.2, a[0].temperature_reading, 'Expected 6.2')
  end

  def test_e_delete
    Temperature.delete_by_column(:source, 'test')
  end

  def test_f_find
    a = Temperature.find_by_source('test')
    assert_equal(0, a.size, 'Expected no results')
  end
end