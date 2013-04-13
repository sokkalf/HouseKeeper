require 'sqlite3'
$LOAD_PATH.unshift File.dirname(__FILE__)
require 'logging'

# super simple "Persistence framework"
# does not support other data types than strings, foreign keys, etc
module Persistence
  include Logging

  def self.included(o)
    o.extend(FindMethods)
  end

  def db
    Persistence.db
  end

  def self.db
    @db ||= SQLite3::Database.open 'housekeeper.db'
  end

  def create_table(table, col_names)
    columns = []
    col_names.each do |name|
      columns << name + ' TEXT'
    end
    sql = "CREATE TABLE IF NOT EXISTS #{table} (#{columns.join(',')})"
    db.execute sql
  end

  def persist(*a)
    table = self.class.name
    col_names = []
    col_values = []
    a.each do |k|
      k.each do |key, value|
        col_names << key.to_s
        col_values << "'" + value + "'"
      end
    end

    create_table(table, col_names)
    sql = "INSERT INTO #{table}(#{col_names.join(',')}) VALUES(#{col_values.join(',')})"
    logger.debug sql
    begin
      db.execute sql
    rescue SQLite3::SQLException => e
      logger.error 'Error inserting row in database'
    end
  end

  module FindMethods
    include Persistence

    def find_all
      table = self.inspect
      sql = "SELECT * FROM #{table}"
      begin
        stm = db.prepare sql
        stm.execute
      rescue SQLite3::SQLException => e
        nil
      end
    end

    def find_by_column(col, value)
      table = self.inspect
      sql = "SELECT * FROM #{table} WHERE #{col} = '#{value}'"
      logger.debug sql
      begin
        stm = db.prepare sql
        stm.execute
      rescue SQLite3::SQLException => e
        nil
      end
    end

    def delete_by_column(col, value)
      table = self.inspect
      sql = "DELETE FROM #{table} WHERE #{col} = '#{value}'"
      logger.debug sql
      begin
        db.execute sql
      rescue SQLite3::SQLException => e
        nil
      end
    end
  end
end