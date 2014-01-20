require 'sqlite3'
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'logging'

# super simple "Persistence framework"
# supports strings, floats, integers
# does not support foreign keys, etc
module Persistence
  include Logging
  class << self; attr_accessor :tables end

  def self.included(o)
    o.extend(FindMethods)
    Persistence.tables = Hash.new
  end

  def db
    Persistence.db
  end

  def self.db
    @db ||= SQLite3::Database.open 'housekeeper.db'
  end

  def create_table(table, names_datatypes)
    columns = []
    names_datatypes.each do |name, type|
      case type
        when 'Fixnum' || 'Integer' || 'TrueClass' || 'FalseClass'
          sql_type = 'INTEGER'
        when 'Float'
          sql_type = 'REAL'
        else
          sql_type = 'TEXT'
      end
      columns << name + ' ' + sql_type
    end
    execute("CREATE TABLE IF NOT EXISTS #{table} (#{columns.join(',')})")
  end

  def execute(sql)
    logger.debug sql
    begin
      db.execute sql
      Persistence.tables[get_table_name] = true
      true
    rescue SQLite3::SQLException => e
      Persistence.tables[get_table_name] = false
      logger.error "Error executing SQL: #{sql} => Exception #{e.to_s}"
      false
    end
  end

  def prepare_and_execute(sql)
    logger.debug sql
    begin
      stm = db.prepare sql
      Persistence.tables[get_table_name] = true
      result = []
      stm.execute.each do |r| result << r end
      result.empty? ? false : result
    rescue SQLite3::SQLException => e
      Persistence.tables[get_table_name] = false
      logger.error "Error executing SQL: #{sql} => Exception #{e.to_s}"
      false
    end
  end

  def quote(column_value)
    case column_value.class.to_s
      when 'Fixnum' || 'Integer' || 'Float' then column_value
      when 'FalseClass' then 0
      when 'TrueClass' then 1
      else "'" + column_value + "'"
    end
  end

  def get_datatype(column_value) column_value.class.to_s end

  def persist(*a)
    sql = a.map {|k| lambda {|cn, cv|
      "INSERT INTO #{get_table_name} (#{cn.join(',')}) VALUES (#{cv.map { |value| quote(value) }.join(',')})"
    }.call(k.keys, k.values)}.join
    unless Persistence.tables[get_table_name]
      col_datatypes = Hash.new
      a.map {|k| k.map{|key, val| col_datatypes[key.to_s] = get_datatype(val)}}
      create_table(get_table_name, col_datatypes)
    end
    execute(sql)
  end

  def get_table_name
    self.class.name != 'Class' ? self.class.name.tr(':','') : self.inspect.tr(':', '')
  end

  module FindMethods
    include Persistence
    def create_where_statement(*a)
      a.map {|k| k.map {|key, value| "#{key} = '#{value}'"}.join(' AND ')}.join
    end

    def find_all
      prepare_and_execute("SELECT * FROM #{get_table_name}")
    end

    def find_by_column(col, value) find_by_columns(col => value) end
    def find_by_columns(*a)
      prepare_and_execute("SELECT * FROM #{get_table_name} WHERE #{create_where_statement(*a)}")
    end

    def find_count_by_column(col, value) find_count_by_columns(col => value) end
    def find_count_by_columns(*a)
      prepare_and_execute("SELECT COUNT(*) FROM #{get_table_name} WHERE #{create_where_statement(*a)}")
    end

    def delete_by_column(col, value) delete_by_columns(col => value) end
    def delete_by_columns(*a)
      execute("DELETE FROM #{get_table_name} WHERE #{create_where_statement(*a)}")
    end
  end
end